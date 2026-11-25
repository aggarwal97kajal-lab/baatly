import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart' show Sha512;
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

import '../config.dart';
import 'api.dart';
import 'app_state.dart';
import 'contacts.dart';
import 'e2e.dart';
import 'media.dart';
import 'models.dart';
import 'push.dart';
import 'notifier.dart';
import 'calls.dart';
import 'group_calls.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'status_service.dart';

/// Someone we chat with: their public key is cached so we can encrypt.
class Peer {
  final String id;
  String name;
  String phone;
  String about;
  String? key;
  int photoVer = 0;
  String? photo;
  Peer(this.id, this.name, this.phone, this.about, this.key);

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone, 'about': about, 'key': key, 'pv': photoVer, 'photo': photo};
  factory Peer.fromJson(String id, Map<String, dynamic> j) =>
      Peer(id, j['name'] as String? ?? '', j['phone'] as String? ?? '', j['about'] as String? ?? '', j['key'] as String?)
        ..photoVer = (j['pv'] as int?) ?? 0
        ..photo = j['photo'] as String?;
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
  Timer? _retry, _ping, _saveTimer, _presenceTimer, _purgeTimer;
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
      _s.useRealStatuses([], []);
    }
    _paused = false;
    unawaited(_connect());
    unawaited(Push.instance.start());
    unawaited(StatusService.instance.refresh());
    unawaited(_pullPrivacy());
    _resumeLive();
    unawaited(_loadBlocks());
    unawaited(CallService.instance.loadLog());
    // Keeps "My contacts" privacy and contact names up to date.
    unawaited(ContactBook.instance.load().then((_) {}, onError: (_) {}));
    unawaited(_refreshPeers());
    unawaited(loadGroups().then((_) => _mergeNotificationReplies()));
    _purge();
    _purgeTimer?.cancel();
    _purgeTimer = Timer.periodic(const Duration(seconds: 20), (_) => _purge());
  }

  // ------------------------------------------------------------------ block / report
  final Set<String> blockedIds = {};

  Future<void> _loadBlocks() async {
    try {
      final d = await Api.instance.request('GET', '/v1/blocks');
      blockedIds
        ..clear()
        ..addAll([for (final x in (d['blocked'] as List? ?? [])) x.toString()]);
      _s.changed();
    } catch (_) {}
  }

  bool isBlocked(String? id) => id != null && blockedIds.contains(id);

  Future<void> setBlocked(String id, bool block) async {
    await Api.instance.request(block ? 'PUT' : 'DELETE', '/v1/blocks/$id');
    block ? blockedIds.add(id) : blockedIds.remove(id);
    _s.changed();
  }

  /// Report a user; optionally share their last 5 messages from this chat and block them.
  Future<void> report(Chat chat, {required bool includeMessages, required bool alsoBlock}) async {
    final evidence = includeMessages
        ? [for (final m in chat.messages.where((m) => !m.fromMe && m.kind != MsgKind.system && !m.deleted).toList().reversed.take(5).toList().reversed) m.text]
        : <String>[];
    await Api.instance.request('POST', '/v1/reports', {'user': chat.peerId, 'reason': 'spam', 'evidence': evidence, 'block': alsoBlock});
    if (alsoBlock) blockedIds.add(chat.peerId!);
    _s.changed();
  }

  // ------------------------------------------------------------------ safety number
  /// 60-digit number both people see; it matches only if no one swapped keys.
  Future<String?> safetyNumber(String peerId) async {
    final p = _peers[peerId];
    if (p?.key == null || _uid == null) return null;
    final mine = E2E.instance.publicKey;
    final keys = [mine, p!.key!]..sort();
    final digest = await Sha512().hash(utf8.encode('baatly-safety-v1|${keys[0]}|${keys[1]}'));
    final b = digest.bytes;
    final groups = <String>[];
    for (var i = 0; i < 12; i++) {
      var n = 0;
      for (var j = 0; j < 5; j++) {
        n = (n * 256 + b[i * 5 + j]) % 100000;
      }
      groups.add(n.toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }

  // ------------------------------------------------------------------ privacy & profile photo
  Future<void> _pullPrivacy() async {
    try {
      final d = await Api.instance.request('GET', '/v1/me/privacy');
      _s.applyPrivacyJson(d['privacy'] as Map<String, dynamic>);
    } catch (_) {}
  }

  /// Saves privacy settings on the server (which enforces them).
  Future<String?> pushPrivacy() async {
    try {
      await Api.instance.request('PUT', '/v1/me/privacy', {'privacy': _s.privacyJson()});
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return "Couldn't save. Check your internet.";
    }
  }

  Future<void> uploadMyPhoto(String path) async {
    final bytes = await File(path).readAsBytes();
    await Api.instance.request('PUT', '/v1/me/photo', {'photo': base64Encode(bytes)});
  }

  Future<void> removeMyPhoto() async {
    await Api.instance.request('DELETE', '/v1/me/photo');
  }

  Future<void> _refreshPeers() async {
    for (final c in _s.chats.where((c) => c.peerId != null).toList()) {
      try {
        await _peer(c.peerId!, refresh: true);
      } catch (_) {}
    }
  }

  /// Replies sent from a notification while the app was closed.
  Future<void> _mergeNotificationReplies() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final out = p.getStringList('notif_outbox') ?? [];
      if (out.isEmpty) return;
      for (final e in out) {
        final j = jsonDecode(e) as Map<String, dynamic>;
        final target = j['chat'] as String;
        Chat? chat;
        for (final c in _s.chats) {
          if (c.peerId == target || c.groupId == target) chat = c;
        }
        if (chat == null || chat.messages.any((m) => m.id == j['id'])) continue;
        chat.messages.add(Message(
          id: j['id'] as String,
          text: j['t'] as String,
          fromMe: true,
          time: DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
          status: MsgStatus.sent,
        ));
        chat.messages.sort((a, b) => a.time.compareTo(b.time));
      }
      await p.remove('notif_outbox');
      _s.changed();
    } catch (_) {}
  }

  /// Disappearing messages: drop expired ones from this phone.
  void _purge() {
    final now = DateTime.now();
    var changed = false;
    for (final c in _s.chats) {
      final before = c.messages.length;
      c.messages.removeWhere((m) => m.expiresAt != null && m.expiresAt!.isBefore(now));
      if (c.messages.length != before) changed = true;
    }
    if (changed) _s.changed();
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
    _purgeTimer?.cancel();
    _presenceTimer?.cancel();
    Push.instance.forget();
    _peers.clear();
    _handled.clear();
  }

  void pause() {
    if (CallService.instance.current != null) return; // keep signalling alive during a call
    _paused = true;
    _closeSocket();
    _retry?.cancel();
    unawaited(_saveNow());
  }

  /// Chat for a notification's chat id (peer id or group id).
  Chat? chatById(String id) {
    for (final c in _s.chats) {
      if (c.peerId == id || c.groupId == id) return c;
    }
    return null;
  }

  void resume() {
    unawaited(_mergeNotificationReplies());
    if (_uid == null) {
      unawaited(start());
      return;
    }
    _paused = false;
    unawaited(_connect());
    StatusService.instance.refreshSoon();
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

  /// Writes chats to disk right now (before a backup).
  Future<void> flushLocal() => _saveNow();

  /// Reloads chats from disk (after restoring a backup).
  Future<void> reloadLocal() async {
    final uid = _uid;
    if (uid != null) await _loadLocal(uid);
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
        for (final m in c.messages.where((m) => m.fromMe && m.status == MsgStatus.sending && !m.busy).toList()) {
          // Files go in the background so text messages aren't stuck behind them.
          if (_fileKinds.contains(m.kind)) {
            unawaited(_deliver(c, m));
          } else {
            await _deliver(c, m);
          }
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
      case 'presence':
        _onPresence(ev);
        ok = false;
      case 'group':
        ok = await _onGroupEvent(ev);
      case 'call':
        CallService.instance.onEvent(ev);
        ok = false;
      case 'gcall':
        GroupCallService.instance.onEvent(ev);
        ok = false;
      case 'profile':
        unawaited(_onProfile(ev['user'] as String));
        ok = false;
      case 'status':
        StatusService.instance.refreshSoon();
        ok = false;
      case 'status_view':
        StatusService.instance.onView(ev['statusId'] as String, ev['viewer'] as String, ev['at'] as int);
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
    final peer = Peer(id, name, phone, u['about'] as String? ?? '', u['x25519'] as String?)
      ..photoVer = p?.photoVer ?? 0
      ..photo = p?.photo;
    if (p?.key != null && peer.key != null && p!.key != peer.key && _s.securityNotices) {
      // Like WhatsApp: tell the user their contact's security code changed (new phone / reinstall).
      for (final c in _s.chats) {
        if (c.peerId == id) {
          c.messages.add(Message(
            id: 'sys_key_${DateTime.now().millisecondsSinceEpoch}',
            text: "${p.name}'s security code changed. Tap to verify.",
            fromMe: false,
            time: DateTime.now(),
            kind: MsgKind.system,
          ));
        }
      }
    }
    _peers[id] = peer;
    final ver = (u['photo_ver'] as int?) ?? 0;
    if (ver != peer.photoVer || (ver > 0 && peer.photo == null)) await _syncPhoto(peer, ver);
    return peer;
  }

  Future<void> _syncPhoto(Peer peer, int ver) async {
    try {
      String? path;
      if (ver > 0) {
        final d = await Api.instance.request('GET', '/v1/users/${peer.id}/photo');
        final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/photos');
        await dir.create(recursive: true);
        final f = File('${dir.path}/${peer.id}_$ver.jpg');
        await f.writeAsBytes(base64Decode(d['photo'] as String), flush: true);
        path = f.path;
      }
      final old = peer.photo;
      peer.photoVer = ver;
      peer.photo = path;
      for (final c in _s.chats) {
        if (c.peerId == peer.id) c.photo = path;
      }
      _s.changed();
      if (old != null && old != path) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Loads a user's profile (photo etc.) if we don't know them yet.
  Future<void> ensurePeer(String id) async {
    if (_peers.containsKey(id)) return;
    try {
      await _peer(id);
    } catch (_) {}
  }

  /// Profile photo of a user, if we have it.
  String? photoOf(String id) => _peers[id]?.photo;

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
    c.photo = p.photo;
    c.disappear = _s.defaultTimer;
    _s.chats.add(c);
    return c;
  }

  /// Best display name for a BAATLY user.
  String nameFor(String id, {String? phone, String? profileName}) {
    final ph = phone ?? _peers[id]?.phone;
    final book = ph == null ? null : ContactBook.instance.names[ph];
    if (book != null) return book;
    final p = _peers[id];
    if (p != null && p.name.isNotEmpty) return p.name;
    if ((profileName ?? '').isNotEmpty) return profileName!;
    return ph == null ? 'BAATLY user' : ContactBook.pretty(ph);
  }

  /// Opens (or creates) the chat with any BAATLY user.
  Chat chatWithUser(String id, String name, String phone, String? key) =>
      chatWith(BaatlyContact(id, name, phone, _peers[id]?.about ?? '', key ?? _peers[id]?.key));

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
    int ttl = 0;
    Map<String, dynamic>? md;
    Map<String, dynamic>? control;
    DateTime at = DateTime.fromMillisecondsSinceEpoch(ev['at'] as int? ?? DateTime.now().millisecondsSinceEpoch);
    try {
      final plain = await _open(body, peer);
      text = plain['t'] as String? ?? '';
      final ts = plain['ts'];
      if (ts is int) at = DateTime.fromMillisecondsSinceEpoch(ts);
      ttl = (plain['ttl'] as int?) ?? 0;
      md = (plain['md'] as Map?)?.cast<String, dynamic>();
      for (final k in const ['del', 'opened', 'vote', 'pin', 'unpin', 'live']) {
        if (plain.containsKey(k)) control = {k: plain[k]};
      }
    } catch (_) {
      text = "🔒 This message couldn't be decrypted. Ask them to send it again.";
    }
    // Control messages (delete for everyone, view-once opened, poll votes).
    if (control != null) {
      _onControl(from, control);
      return true;
    }
    final gid = ev['group'] as String?;
    final Chat chat;
    if (gid != null) {
      final g = await _groupChat(gid);
      if (g == null) return false;
      chat = g;
      chat.typingName = null;
    } else {
      chat = _chatFor(peer);
      chat.disappear = ttl; // follow the sender's disappearing-messages setting
    }
    chat.typing = false;
    if (!chat.messages.any((m) => m.id == msgId)) {
      final kind = kindOf(md?['type'] as String?);
      final m = Message(
        id: msgId,
        text: text,
        fromMe: false,
        time: at,
        kind: kind,
        voiceSeconds: (md?['dur'] as int?) ?? 0,
        media: md,
        expiresAt: ttl > 0 ? DateTime.now().add(Duration(seconds: ttl)) : null,
      )..from = from;
      // Auto-download as set in Storage and data (stickers always: they're tiny).
      if (md != null && md['once'] != true) unawaited(_autoDownload(m));
      chat.messages.add(m);
      chat.messages.sort((a, b) => a.time.compareTo(b.time));
      if (chat.archived && !_s.keepArchived) chat.archived = false;
      final open = _s.activeChatId == chat.id;
      if (!open) chat.unread++;
      _s.changed();
      await _saveNow();
      if (open && _s.readReceipts) {
        m.readSent = true;
        unawaited(_receipt(from, [msgId], 'read', group: gid));
      } else {
        unawaited(_receipt(from, [msgId], 'delivered', group: gid));
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
    final gid = ev['group'] as String?;
    if (gid != null) {
      final read = ev['status'] == 'read';
      final ids = (ev['msgIds'] as List? ?? []).cast<String>().toSet();
      for (final c in _s.chats) {
        if (c.groupId != gid) continue;
        final others = c.members.where((u) => u != _uid).toSet();
        for (final m in c.messages) {
          if (!m.fromMe || !ids.contains(m.id)) continue;
          m.deliveredBy.add(from);
          if (read) m.readBy.add(from);
          if (others.isNotEmpty && others.every(m.readBy.contains) && _s.readReceipts) {
            m.status = MsgStatus.read;
          } else if (others.isNotEmpty && others.every(m.deliveredBy.contains) && m.status.index < MsgStatus.delivered.index) {
            m.status = MsgStatus.delivered;
          }
        }
      }
      _s.changed();
      return;
    }
    // With read receipts off you don't see others' blue ticks either.
    final status = ev['status'] == 'read' && _s.readReceipts ? MsgStatus.read : MsgStatus.delivered;
    final ids = (ev['msgIds'] as List? ?? []).cast<String>().toSet();
    for (final c in _s.chats) {
      if (c.peerId != from) continue;
      for (final m in c.messages) {
        if (m.fromMe && ids.contains(m.id) && m.status.index < status.index) m.status = status;
      }
    }
    _s.changed();
  }

  /// A contact changed photo/name/about: fetch it now so it shows instantly.
  Future<void> _onProfile(String user) async {
    if (!_peers.containsKey(user) && !_s.chats.any((c) => c.peerId == user)) {
      StatusService.instance.refreshSoon();
      return;
    }
    try {
      final p = await _peer(user, refresh: true);
      for (final c in _s.chats) {
        if (c.peerId == user) c.about = p.about;
      }
      _s.changed();
    } catch (_) {}
  }

  /// Muted chats: the server must know, so it doesn't send notifications.
  void syncMute(Chat c) {
    final until = c.mutedUntil;
    unawaited(Api.instance
        .request('PUT', '/v1/mutes', {'peer': c.peerId ?? c.groupId, 'until': until == null ? null : (until.year >= 9999 ? DateTime(9999).millisecondsSinceEpoch : until.millisecondsSinceEpoch)})
        .then((_) {}, onError: (_) {}));
  }

  void _onPresence(Map<String, dynamic> ev) {
    final user = ev['user'] as String?;
    for (final c in _s.chats) {
      if (c.peerId != user) continue;
      c.presence = _presenceText(ev);
    }
    _s.changed();
  }

  static String _presenceText(Map<String, dynamic> d) {
    if (d['online'] == true) return 'online';
    if (d['lastSeen'] is int) return 'last seen ${_ago(DateTime.fromMillisecondsSinceEpoch(d['lastSeen'] as int))}';
    return '';
  }

  void _onTyping(Map<String, dynamic> ev) {
    final from = ev['from'] as String;
    final gid = ev['group'] as String?;
    if (gid != null) {
      for (final c in _s.chats) {
        if (c.groupId != gid) continue;
        c.typing = true;
        c.typingName = nameFor(from);
        _typingTimers['g:$gid']?.cancel();
        _typingTimers['g:$gid'] = Timer(const Duration(seconds: 6), () {
          c.typing = false;
          c.typingName = null;
          _s.changed();
        });
      }
      _s.changed();
      return;
    }
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

  Future<void> _receipt(String to, List<String> ids, String status, {String? group}) async {
    try {
      await Api.instance.request('POST', '/v1/receipts', {'to': to, 'msgIds': ids, 'status': status, if (group != null) 'group': group});
    } catch (_) {}
  }

  // ------------------------------------------------------------------ outgoing
  String _newId() => base64Url.encode(List<int>.generate(12, (_) => _rnd.nextInt(256))).replaceAll('=', '');

  void send(Chat chat, String text, {Map<String, dynamic>? lp}) {
    final m = Message(
      id: _newId(),
      media: lp == null ? null : {'lp': lp},
      text: text,
      fromMe: true,
      time: DateTime.now(),
      status: MsgStatus.sending,
      expiresAt: chat.disappear > 0 ? DateTime.now().add(Duration(seconds: chat.disappear)) : null,
    );
    chat.messages.add(m);
    if (chat.archived) chat.archived = false;
    _s.changed();
    unawaited(_deliver(chat, m));
  }

  static const _fileKinds = {MsgKind.image, MsgKind.voice, MsgKind.doc, MsgKind.video};

  Future<void> _deliver(Chat chat, Message m) async {
    try {
      if (_fileKinds.contains(m.kind) && m.media?['id'] == null) {
        await _uploadMedia(m);
      }
      final ttl = m.expiresAt == null ? 0 : m.expiresAt!.difference(m.time).inSeconds;
      final ok = await _sendPayload(chat, m.id, {
        't': m.text,
        'ts': m.time.millisecondsSinceEpoch,
        if (ttl > 0) 'ttl': ttl,
        if (m.media != null) 'md': m.media,
      });
      if (!ok) return;
      if (m.status == MsgStatus.sending) m.status = MsgStatus.sent;
      _s.changed();
    } catch (_) {
      // Stays "sending" (clock icon); retried when the connection comes back.
    }
  }

  /// Encrypts [payload] for the chat (each group member separately) and sends it.
  Future<bool> _sendPayload(Chat chat, String msgId, Map<String, dynamic> payload, {bool silent = false, String? onlyTo}) async {
    if (chat.groupId != null && onlyTo == null) {
      if (chat.left) return false;
      final bodies = <String, String>{};
      for (final u in chat.members) {
        if (u == _uid) continue;
        try {
          var p = await _peer(u);
          if (p.key == null) p = await _peer(u, refresh: true);
          if (p.key != null) bodies[u] = await E2E.instance.seal(payload, p.key!);
        } catch (_) {}
      }
      await Api.instance.request('POST', '/v1/groups/${chat.groupId}/messages', {'msgId': msgId, 'bodies': bodies, if (silent) 'silent': true, if (silent) 'control': true});
      return true;
    }
    final to = onlyTo ?? chat.peerId!;
    var peer = await _peer(to);
    if (peer.key == null) peer = await _peer(to, refresh: true);
    if (peer.key == null) return false; // they haven't opened the new app yet; retried on next sync
    final body = await E2E.instance.seal(payload, peer.key!);
    await Api.instance.request('POST', '/v1/messages', {'to': to, 'msgId': msgId, 'body': body, if (silent) 'silent': true});
    return true;
  }

  // ------------------------------------------------------------------ control messages
  static MsgKind kindOf(String? type) => switch (type) {
        'image' => MsgKind.image,
        'voice' => MsgKind.voice,
        'doc' => MsgKind.doc,
        'poll' => MsgKind.poll,
        'location' => MsgKind.location,
        'contact' => MsgKind.contact,
        'event' => MsgKind.event,
        'video' => MsgKind.video,
        _ => MsgKind.text,
      };

  Message? _find(String msgId) {
    for (final c in _s.chats) {
      for (final m in c.messages) {
        if (m.id == msgId) return m;
      }
    }
    return null;
  }

  void _onControl(String from, Map<String, dynamic> c) {
    if (c['del'] is String) {
      final m = _find(c['del'] as String);
      // Only the sender can delete it, and only for a short while.
      if (m != null && !m.fromMe && (m.from == null || m.from == from) && DateTime.now().difference(m.time).inMinutes < 10) {
        _wipe(m);
      }
    } else if (c['opened'] is String) {
      final m = _find(c['opened'] as String);
      if (m != null && m.fromMe) m.opened = true;
    } else if (c['pin'] is String || c['unpin'] is String) {
      final id = (c['pin'] ?? c['unpin']) as String;
      for (final ch in _s.chats) {
        if (ch.messages.any((m) => m.id == id)) ch.pinnedId = c['pin'] is String ? id : null;
      }
    } else if (c['live'] is Map) {
      final v = (c['live'] as Map).cast<String, dynamic>();
      final m = _find(v['m'] as String? ?? '');
      if (m != null && m.kind == MsgKind.location && !m.fromMe) {
        if (v['stop'] == true) {
          m.media!['stopped'] = true;
        } else {
          m.media!['lat'] = v['lat'];
          m.media!['lng'] = v['lng'];
          m.media!['upd'] = DateTime.now().millisecondsSinceEpoch;
        }
      }
    } else if (c['vote'] is Map) {
      final v = (c['vote'] as Map).cast<String, dynamic>();
      final m = _find(v['m'] as String? ?? '');
      if (m != null && m.kind == MsgKind.poll) {
        final votes = ((m.media!['votes'] as Map?) ?? {}).cast<String, dynamic>();
        votes[from] = [for (final x in (v['c'] as List? ?? [])) (x as num).toInt()];
        m.media!['votes'] = votes;
      }
    }
    _s.changed();
  }

  void _wipe(Message m) {
    m.deleted = true;
    m.text = '';
    m.kind = MsgKind.text;
    m.media = null;
    final p = m.mediaPath;
    m.mediaPath = null;
    if (p != null) {
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
  }

  /// Delete for everyone (my messages, recent ones).
  Future<void> deleteForEveryone(Chat chat, Message m) async {
    _wipe(m);
    _s.changed();
    if (!chat.isReal) return;
    try {
      await _sendPayload(chat, _newId(), {'del': m.id, 'ts': DateTime.now().millisecondsSinceEpoch}, silent: true);
    } catch (_) {}
  }

  /// View once: after I've seen it, remove the file and tell the sender.
  Future<void> markOpened(Chat chat, Message m) async {
    m.opened = true;
    final p = m.mediaPath;
    m.mediaPath = null;
    if (p != null) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    m.media?.remove('thumb');
    _s.changed();
    final sender = m.from ?? chat.peerId;
    if (sender == null) return;
    try {
      await _sendPayload(chat, _newId(), {'opened': m.id}, silent: true, onlyTo: sender);
    } catch (_) {}
  }

  /// Vote in a poll (replaces my previous vote).
  Future<void> vote(Chat chat, Message m, List<int> choices) async {
    final votes = ((m.media!['votes'] as Map?) ?? {}).cast<String, dynamic>();
    votes[_uid ?? 'me'] = choices;
    m.media!['votes'] = votes;
    _s.changed();
    if (!chat.isReal) return;
    try {
      await _sendPayload(chat, _newId(), {'vote': {'m': m.id, 'c': choices}}, silent: true);
    } catch (_) {}
  }

  /// Location / contact / event / poll: no file, just details.
  void sendCard(Chat chat, MsgKind kind, Map<String, dynamic> md, {String text = '', bool forwarded = false}) {
    if (forwarded) md['fw'] = true;
    final m = Message(
      id: _newId(),
      text: text,
      fromMe: true,
      time: DateTime.now(),
      status: chat.isReal ? MsgStatus.sending : MsgStatus.read,
      kind: kind,
      media: md,
      expiresAt: chat.disappear > 0 ? DateTime.now().add(Duration(seconds: chat.disappear)) : null,
    );
    chat.messages.add(m);
    if (chat.archived) chat.archived = false;
    _s.changed();
    if (chat.isReal) unawaited(_deliver(chat, m));
  }

  String? get myId => _uid;

  // ------------------------------------------------------------------ live location
  final Map<String, StreamSubscription<Position>> _live = {};

  /// Starts live location: posts the card, then keeps sending position updates
  /// (a "BAATLY is sharing your location" notification keeps it running).
  void shareLive(Chat chat, Map<String, dynamic> md) {
    sendCard(chat, MsgKind.location, md);
    _startLive(chat, chat.messages.last);
  }

  void _startLive(Chat chat, Message m) {
    final until = DateTime.fromMillisecondsSinceEpoch((m.media?['until'] as int?) ?? 0);
    if (!until.isAfter(DateTime.now()) || _live.containsKey(m.id)) return;
    DateTime last = DateTime(0);
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
      intervalDuration: const Duration(seconds: 20),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Sharing live location',
        notificationText: 'BAATLY is sharing your live location',
        enableWakeLock: true,
      ),
    );
    _live[m.id] = Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      if (!until.isAfter(DateTime.now()) || m.media?['stopped'] == true) {
        unawaited(stopLive(chat, m));
        return;
      }
      m.media!['lat'] = p.latitude;
      m.media!['lng'] = p.longitude;
      m.media!['upd'] = DateTime.now().millisecondsSinceEpoch;
      _s.changed();
      if (DateTime.now().difference(last).inSeconds < 15) return;
      last = DateTime.now();
      unawaited(_sendPayload(chat, _newId(), {'live': {'m': m.id, 'lat': p.latitude, 'lng': p.longitude}}, silent: true).then((_) {}, onError: (_) {}));
    }, onError: (_) {});
  }

  Future<void> stopLive(Chat chat, Message m) async {
    await _live.remove(m.id)?.cancel();
    m.media?['stopped'] = true;
    _s.changed();
    try {
      await _sendPayload(chat, _newId(), {'live': {'m': m.id, 'stop': true}}, silent: true);
    } catch (_) {}
  }

  /// After a restart, keep sharing anything still live.
  void _resumeLive() {
    for (final c in _s.chats) {
      for (final m in c.messages) {
        if (m.fromMe && m.kind == MsgKind.location && m.media?['live'] == true && m.media?['stopped'] != true) _startLive(c, m);
      }
    }
  }

  // ------------------------------------------------------------------ groups
  Chat _upsertGroup(Map<String, dynamic> g) {
    final gid = g['id'] as String;
    Chat? chat;
    for (final c in _s.chats) {
      if (c.groupId == gid) chat = c;
    }
    final name = g['name'] as String? ?? 'Group';
    chat ??= () {
      final c = Chat(
        id: 'g_$gid',
        name: name,
        initials: initialsOf(name),
        colorIndex: gid.codeUnits.fold<int>(0, (a, b) => a + b) % 7,
        isGroup: true,
        groupId: gid,
      );
      c.disappear = _s.defaultTimer;
      _s.chats.add(c);
      return c;
    }();
    chat.name = name;
    chat.initials = initialsOf(name);
    final members = <String>[];
    final admins = <String>{};
    for (final x in (g['members'] as List? ?? [])) {
      final m = (x as Map).cast<String, dynamic>();
      final id = m['id'] as String;
      members.add(id);
      if (m['role'] == 'admin') admins.add(id);
      if (id == _uid) continue;
      final phone = m['phone'] as String? ?? '';
      final p = _peers[id] ?? Peer(id, nameFor(id, phone: phone, profileName: m['name'] as String?), phone, '', null);
      if (m['x25519'] != null) p.key = m['x25519'] as String;
      if (p.phone.isEmpty) p.phone = phone;
      _peers[id] = p;
    }
    chat.members = members;
    chat.admins = admins;
    final pv = (g['photo_ver'] as int?) ?? 0;
    if (pv > 0 && pv != chat.photoVer) unawaited(_syncGroupPhoto(chat, pv));
    if (pv == 0 && chat.photo != null) {
      chat.photo = null;
      chat.photoVer = 0;
    }
    chat.description = g['about'] as String? ?? chat.description;
    chat.editInfo = g['edit_info'] as String? ?? chat.editInfo;
    chat.sendMessages = g['send_messages'] as String? ?? chat.sendMessages;
    chat.left = _uid != null && !members.contains(_uid);
    chat.about = memberLine(chat);
    return chat;
  }

  /// "You, Riya, Aman" for the header.
  String memberLine(Chat c) {
    final names = <String>[];
    for (final u in c.members) {
      names.add(u == _uid ? 'You' : nameFor(u));
    }
    names.sort((a, b) => a == 'You' ? 1 : b == 'You' ? -1 : a.compareTo(b));
    return names.join(', ');
  }

  Future<Chat?> _groupChat(String gid, {bool refresh = false}) async {
    for (final c in _s.chats) {
      if (c.groupId == gid && !refresh && c.members.isNotEmpty) return c;
    }
    try {
      final d = await Api.instance.request('GET', '/v1/groups/$gid');
      return _upsertGroup((d['group'] as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (e.code == 'NOT_IN_GROUP') {
        for (final c in _s.chats) {
          if (c.groupId == gid) {
            c.left = true;
            return c;
          }
        }
      }
      return null;
    }
  }

  /// All my groups (e.g. after logging in on a new phone).
  Future<void> loadGroups() async {
    try {
      final d = await Api.instance.request('GET', '/v1/groups');
      for (final g in (d['groups'] as List? ?? [])) {
        _upsertGroup((g as Map).cast<String, dynamic>());
      }
      _s.changed();
    } catch (_) {}
  }

  String _who(String id) => id == _uid ? 'You' : nameFor(id);

  Future<bool> _onGroupEvent(Map<String, dynamic> ev) async {
    final gid = ev['group'] as String;
    final actor = ev['actor'] as String? ?? '';
    final targets = [for (final x in (ev['targets'] as List? ?? [])) x.toString()];
    Chat? chat = await _groupChat(gid, refresh: true);
    if (chat == null) {
      // Removed before we ever saw it.
      return true;
    }
    final names = targets.map(_who).join(', ');
    final text = switch (ev['action']) {
      'created' => '${_who(actor)} created group "${ev['name'] ?? chat.name}"',
      'added' => '${_who(actor)} added $names',
      'removed' => '${_who(actor)} removed $names',
      'left' => '$names left',
      'renamed' => '${_who(actor)} changed the group name to "${ev['name']}"',
      'about' => '${_who(actor)} changed the group description',
      'photo' => "${_who(actor)} changed this group's icon",
      'admin' => '$names ${targets.contains(_uid) ? 'are' : 'is'} now an admin',
      'unadmin' => '$names ${targets.contains(_uid) ? 'are' : 'is'} no longer an admin',
      'photo_removed' => "${_who(actor)} deleted this group's icon",
      'edit_info' => ev['value'] == 'admins'
          ? "${_who(actor)} changed this group's settings to allow only admins to edit this group's info"
          : "${_who(actor)} changed this group's settings to allow all members to edit this group's info",
      'send_messages' => ev['value'] == 'admins'
          ? "${_who(actor)} changed this group's settings to allow only admins to send messages to this group"
          : "${_who(actor)} changed this group's settings to allow all members to send messages to this group",
      _ => null,
    };
    if (text != null) {
      chat.messages.add(Message(
        id: 'sys_${ev['id'] ?? _newId()}',
        text: text,
        fromMe: false,
        time: DateTime.fromMillisecondsSinceEpoch(ev['at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        kind: MsgKind.system,
      ));
    }
    _s.changed();
    await _saveNow();
    return true;
  }

  Future<Chat> createGroup(String name, List<String> memberIds) async {
    final d = await Api.instance.request('POST', '/v1/groups', {'name': name, 'members': memberIds});
    final chat = _upsertGroup((d['group'] as Map).cast<String, dynamic>());
    _s.changed();
    return chat;
  }

  Future<void> addMembers(Chat chat, List<String> ids) async {
    final d = await Api.instance.request('POST', '/v1/groups/${chat.groupId}/members', {'add': ids});
    _upsertGroup((d['group'] as Map).cast<String, dynamic>());
    _s.changed();
  }

  // Group changes show instantly; the server call runs after (and undoes on error).
  Future<void> removeMember(Chat chat, String id) async {
    final before = [...chat.members];
    chat.members.remove(id);
    chat.admins.remove(id);
    chat.about = memberLine(chat);
    _s.changed();
    try {
      await Api.instance.request('DELETE', '/v1/groups/${chat.groupId}/members/$id');
    } catch (e) {
      chat.members = before;
      chat.about = memberLine(chat);
      _s.changed();
      rethrow;
    }
  }

  Future<void> setAdmin(Chat chat, String id, bool admin) async {
    admin ? chat.admins.add(id) : chat.admins.remove(id);
    _s.changed();
    try {
      await Api.instance.request(admin ? 'POST' : 'DELETE', '/v1/groups/${chat.groupId}/admins/$id');
    } catch (e) {
      admin ? chat.admins.remove(id) : chat.admins.add(id);
      _s.changed();
      rethrow;
    }
  }

  Future<void> renameGroup(Chat chat, String name) async {
    final d = await Api.instance.request('PATCH', '/v1/groups/${chat.groupId}', {'name': name});
    _upsertGroup((d['group'] as Map).cast<String, dynamic>());
    _s.changed();
  }

  Future<void> setGroupPhoto(Chat chat, String path) async {
    final bytes = await File(path).readAsBytes();
    // Show it right away; upload in the same step.
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/photos');
    await dir.create(recursive: true);
    final local = File('${dir.path}/g_${chat.groupId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await local.writeAsBytes(bytes, flush: true);
    final old = chat.photo;
    chat.photo = local.path;
    _s.changed();
    try {
      final d = await Api.instance.request('PUT', '/v1/groups/${chat.groupId}/photo', {'photo': base64Encode(bytes)});
      chat.photoVer = (d['ver'] as int?) ?? chat.photoVer + 1;
      if (old != null && old != local.path) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
    } catch (e) {
      chat.photo = old;
      _s.changed();
      rethrow;
    }
  }

  Future<void> removeGroupPhoto(Chat chat) async {
    await Api.instance.request('DELETE', '/v1/groups/${chat.groupId}/photo');
    chat.photo = null;
    chat.photoVer = 0;
    _s.changed();
  }

  Future<void> setGroupDescription(Chat chat, String text) async {
    final d = await Api.instance.request('PATCH', '/v1/groups/${chat.groupId}', {'about': text});
    _upsertGroup((d['group'] as Map).cast<String, dynamic>());
    _s.changed();
  }

  Future<void> setGroupSettings(Chat chat, {String? editInfo, String? sendMessages}) async {
    final oldE = chat.editInfo, oldS = chat.sendMessages;
    if (editInfo != null) chat.editInfo = editInfo;
    if (sendMessages != null) chat.sendMessages = sendMessages;
    _s.changed();
    try {
      await Api.instance.request('PATCH', '/v1/groups/${chat.groupId}/settings', {
        if (editInfo != null) 'editInfo': editInfo,
        if (sendMessages != null) 'sendMessages': sendMessages,
      });
    } catch (e) {
      chat.editInfo = oldE;
      chat.sendMessages = oldS;
      _s.changed();
      rethrow;
    }
  }

  /// Can I change this group's name / icon / description / pins?
  bool canEditGroup(Chat chat) => !chat.left && (chat.editInfo == 'all' || chat.admins.contains(_uid));
  bool canSendInGroup(Chat chat) => !chat.left && (chat.sendMessages == 'all' || chat.admins.contains(_uid));

  /// Pin / unpin a message for everyone in the chat.
  Future<void> pin(Chat chat, Message? m) async {
    final old = chat.pinnedId;
    chat.pinnedId = m?.id;
    _s.changed();
    if (!chat.isReal) return;
    try {
      await _sendPayload(chat, _newId(), m == null ? {'unpin': old ?? ''} : {'pin': m.id}, silent: true);
    } catch (_) {}
  }

  Future<void> _syncGroupPhoto(Chat chat, int ver) async {
    try {
      final d = await Api.instance.request('GET', '/v1/groups/${chat.groupId}/photo');
      final v = (d['ver'] as int?) ?? 1;
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/photos');
      await dir.create(recursive: true);
      final f = File('${dir.path}/g_${chat.groupId}_$v.jpg');
      await f.writeAsBytes(base64Decode(d['photo'] as String), flush: true);
      final old = chat.photo;
      chat.photo = f.path;
      chat.photoVer = v;
      _s.changed();
      if (old != null && old != f.path) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> leaveGroup(Chat chat) async {
    await Api.instance.request('DELETE', '/v1/groups/${chat.groupId}/members/$_uid');
    chat.left = true;
    _s.changed();
  }

  // ------------------------------------------------------------------ media
  /// Sends a photo / voice note / document. The file is encrypted on this
  /// phone with a fresh key; the key goes inside the E2E message.
  void sendMedia(Chat chat,
      {required String path,
      required MsgKind kind,
      String caption = '',
      String? name,
      int seconds = 0,
      bool once = false,
      bool forwarded = false,
      Map<String, dynamic>? extra}) {
    final fileName = name ?? path.split('/').last;
    final m = Message(
      id: _newId(),
      text: caption,
      fromMe: true,
      time: DateTime.now(),
      status: MsgStatus.sending,
      kind: kind,
      voiceSeconds: seconds,
      mediaPath: path,
      media: {
        'type': switch (kind) { MsgKind.image => 'image', MsgKind.voice => 'voice', MsgKind.video => 'video', _ => 'doc' },
        'name': fileName,
        'mime': MediaFiles.mime(fileName),
        if (seconds > 0) 'dur': seconds,
        if (once) 'once': true,
        if (forwarded) 'fw': true,
        ...?extra,
      },
      expiresAt: chat.disappear > 0 ? DateTime.now().add(Duration(seconds: chat.disappear)) : null,
    );
    chat.messages.add(m);
    if (chat.archived) chat.archived = false;
    _s.changed();
    unawaited(_deliver(chat, m));
  }

  Future<void> _uploadMedia(Message m) async {
    m.busy = true;
    _s.changed();
    try {
      final file = File(m.mediaPath!);
      final bytes = await file.readAsBytes();
      if (m.kind == MsgKind.image && m.media!['once'] != true && m.media!['stk'] != true) {
        final t = await MediaFiles.thumb(file.path);
        if (t != null) {
          m.media!['thumb'] = t.$1;
          m.media!['w'] = t.$2;
          m.media!['h'] = t.$3;
        }
      }
      final (key, blob) = await E2E.lockInBackground(bytes);
      m.progress = 0;
      final id = await Api.instance.upload(blob, onProgress: (p) {
        m.progress = p;
        _s.changed();
      });
      m.media!['id'] = id;
      m.media!['k'] = base64Encode(key);
      m.media!['size'] = bytes.length;
    } finally {
      m.busy = false;
      _s.changed();
    }
  }

  Future<void> _autoDownload(Message m) async {
    final md = m.media!;
    final size = (md['size'] as int?) ?? 0;
    if (md['stk'] == true) {
      await downloadMedia(m);
      return;
    }
    final rule = switch (m.kind) {
      MsgKind.image => _s.autoPhotos,
      MsgKind.voice => md['audio'] == true ? _s.autoDocs : _s.autoAudio,
      MsgKind.video => _s.autoVideos,
      MsgKind.doc => _s.autoDocs,
      _ => 0,
    };
    if (rule == 0 || size > 100 * 1024 * 1024) return;
    if (rule == 1) {
      try {
        final c = await Connectivity().checkConnectivity();
        if (!c.contains(ConnectivityResult.wifi) && !c.contains(ConnectivityResult.ethernet)) return;
      } catch (_) {
        return;
      }
    }
    await downloadMedia(m);
  }

  /// Downloads + decrypts a received file to this phone.
  Future<String?> downloadMedia(Message m) async {
    final md = m.media;
    if (m.mediaPath != null && File(m.mediaPath!).existsSync()) return m.mediaPath;
    if (md == null || md['id'] == null || m.busy) return null;
    m.busy = true;
    _s.changed();
    try {
      m.progress = 0;
      final blob = await Api.instance.download(md['id'] as String, onProgress: (p) {
        m.progress = p;
        _s.changed();
      });
      final clear = await E2E.unlockInBackground(blob, base64Decode(md['k'] as String));
      final name = (md['name'] as String?) ?? 'file';
      final ext = MediaFiles.ext(name);
      final f = File('${(await MediaFiles.dir()).path}/${m.id}${ext.isEmpty ? '' : '.$ext'}');
      await f.writeAsBytes(clear, flush: true);
      m.mediaPath = f.path;
      return f.path;
    } catch (_) {
      return null;
    } finally {
      m.busy = false;
      _s.changed();
    }
  }

  /// Forward a text message (shows "Forwarded").
  void forwardText(Chat chat, String text) {
    if (!chat.isReal) {
      AppState.instance.send(chat, text);
      return;
    }
    final m = Message(
      id: _newId(),
      text: text,
      fromMe: true,
      time: DateTime.now(),
      status: MsgStatus.sending,
      media: {'type': 'text', 'fw': true},
      expiresAt: chat.disappear > 0 ? DateTime.now().add(Duration(seconds: chat.disappear)) : null,
    );
    chat.messages.add(m);
    _s.changed();
    unawaited(_deliver(chat, m));
  }

  /// Called while the user types (throttled).
  void typing(Chat chat) {
    if (!chat.isReal || chat.left) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inSeconds < 4) return;
    _lastTypingSent = now;
    if (chat.groupId != null) {
      unawaited(Api.instance.request('POST', '/v1/groups/${chat.groupId}/typing').then((_) {}, onError: (_) {}));
      return;
    }
    unawaited(Api.instance.request('POST', '/v1/typing', {'to': chat.peerId, 'typing': true}).catchError((_) => <String, dynamic>{}));
  }

  // ------------------------------------------------------------------ open chat
  void openChat(Chat chat) {
    if (!chat.isReal) return;
    unawaited(Notifier.instance.clear(chat.groupId ?? chat.peerId!));
    chat.unread = 0;
    markRead(chat);
    if (chat.groupId != null) {
      unawaited(_groupChat(chat.groupId!, refresh: true).then((_) => _s.changed()));
      return;
    }
    unawaited(_refresh(chat));
    _presenceTimer?.cancel();
    // Re-subscribe every minute; changes themselves arrive instantly over the socket.
    _presenceTimer = Timer.periodic(const Duration(seconds: 60), (_) => unawaited(_presence(chat)));
  }

  void closeChat(Chat chat) {
    _presenceTimer?.cancel();
  }

  void markRead(Chat chat) {
    if (!_s.readReceipts) return;
    final unread = [for (final m in chat.messages) if (!m.fromMe && !m.readSent && m.kind != MsgKind.system) m];
    if (unread.isEmpty) return;
    for (final m in chat.messages) {
      if (!m.fromMe) m.readSent = true;
    }
    _s.changed();
    if (chat.groupId != null) {
      final bySender = <String, List<String>>{};
      for (final m in unread) {
        if (m.from != null) bySender.putIfAbsent(m.from!, () => []).add(m.id);
      }
      bySender.forEach((to, ids) => unawaited(_receipt(to, ids, 'read', group: chat.groupId)));
    } else {
      unawaited(_receipt(chat.peerId!, [for (final m in unread) m.id], 'read'));
    }
  }

  Future<void> _refresh(Chat chat) async {
    await _presence(chat);
    try {
      final p = await _peer(chat.peerId!, refresh: true);
      chat.about = p.about;
      _s.changed();
    } catch (_) {}
  }

  Future<void> _presence(Chat chat) async {
    try {
      final d = await Api.instance.request('POST', '/v1/users/${chat.peerId}/presence');
      chat.presence = _presenceText(d);
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
