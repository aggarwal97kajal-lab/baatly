import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/io.dart';

import '../config.dart';
import 'notifier.dart';

/// Two numbers on one phone, like WhatsApp: while BAATLY is open, the other
/// (parked) account keeps its own live connection, so its messages arrive
/// instantly (notification + double tick) instead of waiting for a push.
/// Nothing is acknowledged here: the account still gets everything when you
/// switch to it.
class SideLinks {
  SideLinks._();
  static final instance = SideLinks._();

  final Map<String, _Link> _links = {};
  bool _on = false;

  Future<void> start() async {
    _on = true;
    final slots = await _slots();
    for (final uid in _links.keys.toList()) {
      if (!slots.containsKey(uid)) _links.remove(uid)?.close();
    }
    slots.forEach((uid, token) {
      _links.putIfAbsent(uid, () => _Link(uid, token))..token = token..open();
    });
  }

  void stop() {
    _on = false;
    for (final l in _links.values) {
      l.close();
    }
    _links.clear();
  }

  bool get on => _on;

  static Future<Map<String, String>> _slots() async {
    try {
      final raw = await const FlutterSecureStorage().read(key: 'acct_slots');
      if (raw == null) return {};
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return {
        for (final e in m.entries)
          if ((e.value as Map?)?['token'] is String) e.key: (e.value as Map)['token'] as String,
      };
    } catch (_) {
      return {};
    }
  }
}

class _Link {
  final String uid;
  String token;
  IOWebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping, _retry;
  DateTime _heard = DateTime(0);
  int _backoff = 1;
  bool _closed = false;
  final Set<String> _seen = {};

  _Link(this.uid, this.token);

  void open() {
    _closed = false;
    if (_ch != null) return;
    _retry?.cancel();
    final uri = Uri.parse('${kApiBase.replaceFirst(RegExp(r'^http'), 'ws')}/v1/ws');
    final ch = IOWebSocketChannel.connect(uri, headers: {HttpHeaders.authorizationHeader: 'Bearer $token'});
    _ch = ch;
    _heard = DateTime.now();
    _sub = ch.stream.listen(
      (d) {
        _heard = DateTime.now();
        _backoff = 1;
        if (d is! String || d == 'pong') return;
        try {
          unawaited(_onEvent((jsonDecode(d) as Map).cast<String, dynamic>()));
        } catch (_) {}
      },
      onDone: _drop,
      onError: (_) => _drop(),
      cancelOnError: true,
    );
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 15), (_) {
      if (DateTime.now().difference(_heard) > const Duration(seconds: 35)) {
        _drop();
        return;
      }
      try {
        _ch?.sink.add('ping');
      } catch (_) {}
    });
  }

  Future<void> _onEvent(Map<String, dynamic> ev) async {
    if (ev['type'] != 'msg' || ev['silent'] == true) return;
    final msgId = ev['msgId'] as String? ?? '';
    if (msgId.isEmpty || !_seen.add(msgId)) return;
    final from = ev['from'] as String? ?? '';
    final group = ev['group'] as String?;
    await Notifier.instance.showFromPush({
      'type': 'msg',
      'acct': uid,
      'chat': group ?? from,
      'from': from,
      if (group != null) 'group': group,
      'msgId': msgId,
      'body': ev['body'] ?? '',
      'title': 'BAATLY',
      'live': '1',
    });
  }

  void _drop() {
    _ping?.cancel();
    _sub?.cancel();
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    if (_closed || !SideLinks.instance.on) return;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _backoff), open);
    _backoff = min(_backoff * 2, 10);
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    _drop();
  }
}
