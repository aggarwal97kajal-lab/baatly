import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

import '../config.dart';
import 'api.dart';
import 'app_state.dart';
import 'contacts.dart';
import 'e2e.dart';
import 'models.dart';

/// Someone we chat with: their public key is cached so we can encrypt.
class Peer {
  final String id;
  String name;
  String phone;
  String about;
  String? key;
  Peer(this.id, this.name, this.phone, this.about, this.key);

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone, 'about': about, 'key': key};
  factory Peer.fromJson(String id, Map<String, dynamic> j) =>
      Peer(id, j['name'] as String? ?? '', j['phone'] as String? ?? '', j['about'] as String? ?? '', j['key'] as String?);
}

/// Real 1:1 messaging: encrypts on this phone, relays through the server,
/// receives live over a WebSocket and keeps chats in a file on this phone.
class Messenger {
  Messenger._();
  static final Messenger instance = Messenger._();

  String? _uid;
  final Map<String, Peer> _peers = {};
  IOWebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry, _ping, _saveTimer, _presenceTimer;
  int _backoff = 1;
  bool _paused = false;
  bool _syncing = false;
  final Set<String> _handled = {};
  final Map<String, Timer> _typingTimers = {};
  DateTime _lastTypingSent = DateTime(0);
  final _rnd = Random.secure();

  AppState get _s => AppState.instance;
  bool get active => _uid != null;

  // ------------------------------------------------------------------ start / stop
  Future<void> start() async {
    if (!kHasBackend || !Api.instance.loggedIn) return;
    var uid = Api.instance.userId;
    if (uid == null) {
      try {
        final d = await Api.instance.request('GET', '/v1/me');
        uid = (d['user'] as Map<String, dynamic>)['id'] as String;
        await Api.instance.rememberUserId(uid);
      } catch (_) {
        return;
      }
    }
    if (_uid != uid) {
      _uid = uid;
      await E2E.instance.load(uid);
      await _publishKey(uid);
      await _loadLocal(uid);
      _s.removeListener(_scheduleSave);
      _s.addListener(_scheduleSave);
    }
    _paused = false;
    unawaited(_connect());
  }

  Future<void> _publishKey(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      final k = 'e2e_published_$uid';
      if (p.getString(k) == E2E.instance.publicKey) return;
      await Api.instance.request('PUT', '/v1/keys', {'x25519': E2E.instance.publicKey});
      await p.setString(k, E2E.instance.publicKey);
    } catch (_) {
      // Retried on next start.
    }
  }

  Future<void> stop() async {
    _s.removeListener(_scheduleSave);
    await _saveNow();
    _closeSocket();
    _retry?.cancel();
    _uid = null;
    _peers.clear();
    _handled.clear();
  }

  void pause() {
    _paused = true;
    _closeSocket();
    _retry?.cancel();
    unawaited(_saveNow());
  }

  void resume() {
    if (_uid == null) {
      unawaited(start());
      return;
    }
    _paused = false;
    unawaited(_connect());
  }

  // ------------------------------------------------------------------ local storage
  Future<File> _file(String uid) async => File('${(await getApplicationDocumentsDirectory()).path}/chats_$uid.json');

  Future<void> _loadLocal(String uid) async {
    final chats = <Chat>[];
    _peers.clear();
    try {
      final f = await _file(uid);
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        for (final c in (j['chats'] as List? ?? [])) {
          chats.add(Chat.fromJson(c as Map<String, dynamic>));
        }
        (j['peers'] as Map<String, dynamic>? ?? {}).forEach((id, v) => _peers[id] = Peer.fromJson(id, v as Map<String, dynamic>));
      }
    } catch (_) {}
    _s.useRealChats(chats);
  }

  void _scheduleSave() {
    if (_uid == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveNow);
  }

  Future<void> _saveNow() async {
    final uid = _uid;
    if (uid == null || !_s.realChats) return;
    _saveTimer?.cancel();
    try {
      final data = jsonEncode({
        'chats': _s.chats.where((c) => c.isReal).map((c) => c.toJson()).toList(),
        'peers': _peers.map((k, v) => MapEntry(k, v.toJson())),
      });
      final f = await _file(uid);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  // ------------------------------------------------------------------ socket
  Future<void> _connect() async {
    if (_uid == null || _ws != null || _paused) return;
    _retry?.cancel();
    final uri = Uri.parse('${kApiBase.replaceFirst(RegExp(r'^http'), 'ws')}/v1/ws');
    final ch = IOWebSocketChannel.connect(uri, headers: {'authorization': 'Bearer ${Api.instance.token}'});
    _ws = ch;
    _sub = ch.stream.listen(
      (d) {
        if (d is! String || d == 'pong') return;
        try {
          unawaited(_onLive(jsonDecode(d) as Map<String, dynamic>));
        } catch (_) {}
      },
      onDone: _dropped,
      onError: (_) => _dropped(),
      cancelOnError: true,
    );
    try {
      await ch.ready;
    } catch (_) {
      _dropped();
      return;
    }
    _backoff = 1;
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        _ws?.sink.add('ping');
      } catch (_) {}
    });
    await sync();
  }

  void _closeSocket() {
    _ping?.cancel();
    _sub?.cancel();
    try {
      _ws?.sink.close();
    } catch (_) {}
    _ws = null;
  }

  void _dropped() {
    if (_ws == null) return;
    _closeSocket();
    if (_uid == null || _paused) return;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _backoff), () => unawaited(_connect()));
    _backoff = min(_backoff * 2, 30);
  }

  /// Picks up everything that arrived while we were away, then resends
  /// anything that didn't go out.
  Future<void> sync() async {
    if (_uid == null || _syncing) return;
    _syncing = true;
    try {
      final d = await Api.instance.request('GET', '/v1/inbox');
      final done = <String>[];
      for (final e in (d['events'] as List? ?? [])) {
        final ev = e as Map<String, dynamic>;
        if (await _handle(ev)) done.add(ev['id'] as String);
      }
      if (done.isNotEmpty) await Api.instance.request('POST', '/v1/inbox/ack', {'ids': done});
      for (final c in _s.chats.where((c) => c.isReal).toList()) {
        for (final m in c.messages.where((m) => m.fromMe && m.status == MsgStatus.sending).toList()) {
          await _deliver(c, m);
        }
      }
    } catch (_) {
    } finally {
      _syncing = false;
    }
  }

  Future<void> _onLive(Map<String, dynamic> ev) async {
    final id = ev['id'] as String?;
    if (await _handle(ev) && id != null) {
      try {
        await Api.instance.request('POST', '/v1/inbox/ack', {'ids': [id]});
      } catch (_) {}
    }
  }

  /// Returns true when the event is safely stored and can be removed from the server.
  Future<bool> _handle(Map<String, dynamic> ev) async {
    final id = ev['id'] as String?;
    if (id != null && _handled.contains(id)) return true;
    bool ok;
    switch (ev['type']) {
      case 'msg':
        ok = await _onMessage(ev);
      case 'receipt':
        _onReceipt(ev);
        ok = true;
      case 'typing':
        _onTyping(ev);
        ok = false;
      default:
        ok = true;
    }
    if (ok && id != null) _handled.add(id);
    return ok;
  }

  // ------------------------------------------------------------------ peers & chats
  Future<Peer> _peer(String id, {bool refresh = false}) async {
    final p = _peers[id];
    if (p != null && !refresh && p.key != null) return p;
    final d = await Api.instance.request('GET', '/v1/users/$id');
    final u = d['user'] as Map<String, dynamic>;
    final phone = u['phone'] as String? ?? '';
    final profile = u['name'] as String? ?? '';
    final name = ContactBook.instance.names[phone] ?? p?.name ?? (profile.isNotEmpty ? profile : ContactBook.pretty(phone));
    final peer = Peer(id, name, phone, u['about'] as String? ?? '', u['x25519'] as String?);
    _peers[id] = peer;
    return peer;
  }

  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(w[0])).toList();
    if (words.isEmpty) return '#';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  Chat _chatFor(Peer p) {
    for (final c in _s.chats) {
      if (c.peerId == p.id) return c;
    }
    final c = Chat(
      id: p.id,
      name: p.name,
      initials: initialsOf(p.name),
      colorIndex: p.id.codeUnits.fold<int>(0, (a, b) => a + b) % 7,
      about: p.about,
      peerId: p.id,
      phone: p.phone,
    );
    _s.chats.add(c);
    return c;
  }

  /// Opens (or creates) the chat with a contact picked from the phone book.
  Chat chatWith(BaatlyContact c) {
    final p = _peers[c.userId] ?? Peer(c.userId, c.name, c.phone, c.about, c.key);
    p.name = c.name;
    if (c.key != null) p.key = c.key;
    _peers[c.userId] = p;
    final chat = _chatFor(p);
    chat.name = c.name;
    chat.initials = initialsOf(c.name);
    _s.changed();
    return chat;
  }

  // ------------------------------------------------------------------ incoming
  Future<bool> _onMessage(Map<String, dynamic> ev) async {
    final from = ev['from'] as String;
    final msgId = ev['msgId'] as String;
    final body = ev['body'] as String;
    Peer peer;
    try {
      peer = await _peer(from);
    } catch (_) {
      return false; // offline: keep it on the server and try again later
    }
    String text;
    DateTime at = DateTime.fromMillisecondsSinceEpoch(ev['at'] as int? ?? DateTime.now().millisecondsSinceEpoch);
    try {
      final plain = await _open(body, peer);
      text = plain['t'] as String? ?? '';
      final ts = plain['ts'];
      if (ts is int) at = DateTime.fromMillisecondsSinceEpoch(ts);
    } catch (_) {
      text = "🔒 This message couldn't be decrypted. Ask them to send it again.";
    }
    final chat = _chatFor(peer);
    chat.typing = false;
    if (!chat.messages.any((m) => m.id == msgId)) {
      final m = Message(id: msgId, text: text, fromMe: false, time: at);
      chat.messages.add(m);
      chat.messages.sort((a, b) => a.time.compareTo(b.time));
      if (chat.archived && !chat.muted) chat.archived = false;
      final open = _s.activeChatId == chat.id;
      if (!open) chat.unread++;
      _s.changed();
      await _saveNow();
      if (open && _s.readReceipts) {
        m.readSent = true;
        unawaited(_receipt(from, [msgId], 'read'));
      } else {
        unawaited(_receipt(from, [msgId], 'delivered'));
      }
    }
    return true;
  }

  Future<Map<String, dynamic>> _open(String body, Peer peer) async {
    try {
      if (peer.key == null) throw StateError('no key');
      return await E2E.instance.open(body, peer.key!);
    } catch (_) {
      // Their key may have changed (new phone / reinstall): fetch and retry once.
      final fresh = await _peer(peer.id, refresh: true);
      return E2E.instance.open(body, fresh.key!);
    }
  }

  void _onReceipt(Map<String, dynamic> ev) {
    final from = ev['from'] as String;
    final status = ev['status'] == 'read' ? MsgStatus.read : MsgStatus.delivered;
    final ids = (ev['msgIds'] as List? ?? []).cast<String>().toSet();
    for (final c in _s.chats) {
      if (c.peerId != from) continue;
      for (final m in c.messages) {
        if (m.fromMe && ids.contains(m.id) && m.status.index < status.index) m.status = status;
      }
    }
    _s.changed();
  }

  void _onTyping(Map<String, dynamic> ev) {
    final from = ev['from'] as String;
    for (final c in _s.chats) {
      if (c.peerId != from) continue;
      c.typing = ev['typing'] == true;
      _typingTimers[from]?.cancel();
      if (c.typing) {
        _typingTimers[from] = Timer(const Duration(seconds: 6), () {
          c.typing = false;
          _s.changed();
        });
      }
      _s.changed();
    }
  }

  Future<void> _receipt(String to, List<String> ids, String status) async {
    try {
      await Api.instance.request('POST', '/v1/receipts', {'to': to, 'msgIds': ids, 'status': status});
    } catch (_) {}
  }

  // ------------------------------------------------------------------ outgoing
  String _newId() => base64Url.encode(List<int>.generate(12, (_) => _rnd.nextInt(256))).replaceAll('=', '');

  void send(Chat chat, String text) {
    final m = Message(id: _newId(), text: text, fromMe: true, time: DateTime.now(), status: MsgStatus.sending);
    chat.messages.add(m);
    if (chat.archived) chat.archived = false;
    _s.changed();
    unawaited(_deliver(chat, m));
  }

  Future<void> _deliver(Chat chat, Message m) async {
    try {
      var peer = await _peer(chat.peerId!);
      if (peer.key == null) peer = await _peer(chat.peerId!, refresh: true);
      if (peer.key == null) return; // they haven't opened the new app yet; retried on next sync
      final body = await E2E.instance.seal({'t': m.text, 'ts': m.time.millisecondsSinceEpoch}, peer.key!);
      await Api.instance.request('POST', '/v1/messages', {'to': chat.peerId, 'msgId': m.id, 'body': body});
      if (m.status == MsgStatus.sending) m.status = MsgStatus.sent;
      _s.changed();
    } catch (_) {
      // Stays "sending" (clock icon); retried when the connection comes back.
    }
  }

  /// Called while the user types (throttled).
  void typing(Chat chat) {
    if (!chat.isReal) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inSeconds < 4) return;
    _lastTypingSent = now;
    unawaited(Api.instance.request('POST', '/v1/typing', {'to': chat.peerId, 'typing': true}).catchError((_) => <String, dynamic>{}));
  }

  // ------------------------------------------------------------------ open chat
  void openChat(Chat chat) {
    if (!chat.isReal) return;
    chat.unread = 0;
    markRead(chat);
    unawaited(_refresh(chat));
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_presence(chat)));
  }

  void closeChat(Chat chat) {
    _presenceTimer?.cancel();
  }

  void markRead(Chat chat) {
    if (!_s.readReceipts) return;
    final ids = [for (final m in chat.messages) if (!m.fromMe && !m.readSent) m.id];
    if (ids.isEmpty) return;
    for (final m in chat.messages) {
      if (!m.fromMe) m.readSent = true;
    }
    _s.changed();
    unawaited(_receipt(chat.peerId!, ids, 'read'));
  }

  Future<void> _refresh(Chat chat) async {
    try {
      final p = await _peer(chat.peerId!, refresh: true);
      chat.about = p.about;
    } catch (_) {}
    await _presence(chat);
  }

  Future<void> _presence(Chat chat) async {
    try {
      final d = await Api.instance.request('GET', '/v1/users/${chat.peerId}/presence');
      if (d['online'] == true) {
        chat.presence = 'online';
      } else if (d['lastSeen'] is int) {
        chat.presence = 'last seen ${_ago(DateTime.fromMillisecondsSinceEpoch(d['lastSeen'] as int))}';
      } else {
        chat.presence = '';
      }
      _s.changed();
    } catch (_) {}
  }

  static String _ago(DateTime t) {
    final now = DateTime.now();
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final time = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return 'today at $time';
    if (today.difference(day).inDays == 1) return 'yesterday at $time';
    return '${t.day}/${t.month} at $time';
  }
}
