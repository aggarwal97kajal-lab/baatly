import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../config.dart';
import 'api.dart';

/// Push notifications (Firebase Cloud Messaging).
///
/// The server only sends "New message from <name>" - never the text,
/// because messages are end-to-end encrypted. Android shows it while the
/// app is closed; when the app is open the live connection is used instead.
class Push {
  Push._();
  static final Push instance = Push._();

  bool _ready = false;
  String? _sentToken;

  Future<void> start() async {
    if (!kPushEnabled || !Api.instance.loggedIn) return;
    try {
      if (!_ready) {
        await Firebase.initializeApp();
        _ready = true;
        FirebaseMessaging.instance.onTokenRefresh.listen(_upload);
      }
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, badge: true, sound: true);
      final t = await fm.getToken();
      if (t != null) await _upload(t);
    } catch (_) {
      // Push is best-effort; chats still work while the app is open.
    }
  }

  Future<void> _upload(String token) async {
    if (!Api.instance.loggedIn || token == _sentToken) return;
    try {
      await Api.instance.request('PUT', '/v1/push/token', {'token': token});
      _sentToken = token;
    } catch (_) {}
  }

  /// On logout the server drops this phone's token together with the session.
  void forget() => _sentToken = null;
}
