import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'e2e.dart';

/// Runs when a push arrives while BAATLY is closed or in the background.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await Notifier.instance.showFromPush(message.data);
}

/// Reply / mark-as-read tapped on a notification while the app is closed.
@pragma('vm:entry-point')
Future<void> notificationActionBackground(NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  await Notifier.instance.handleAction(r);
}

/// Shows message notifications with the real text (decrypted on this phone),
/// plus Reply and Mark as read buttons.
class Notifier {
  Notifier._();
  static final Notifier instance = Notifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _init = false;

  /// Set when the user taps a notification; HomeShell opens that chat.
  String? pendingChat;
  void Function(String chatId)? onOpenChat;

  static const _channel = AndroidNotificationChannel(
    'messages',
    'Messages',
    description: 'New messages',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_init) return;
    _init = true;
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: handleAction,
      onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
    );
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(_channel);
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final p = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && p != null) {
        final j = jsonDecode(p) as Map;
        pendingChat = j['chat'] as String?;
        pendingCall = j['call'] as String?;
      }
    } catch (_) {}
  }

  static int _idFor(String chat) => chat.hashCode & 0x7fffffff;

  Future<Map<String, dynamic>> _localData(String uid) async {
    try {
      final f = File('${(await getApplicationDocumentsDirectory()).path}/chats_$uid.json');
      if (await f.exists()) return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {}
    return {};
  }

  static String _pretty(String e164) =>
      e164.startsWith('+91') && e164.length == 13 ? '+91 ${e164.substring(3, 8)} ${e164.substring(8)}' : e164;

  static String _preview(Map<String, dynamic> plain) {
    final md = (plain['md'] as Map?)?.cast<String, dynamic>();
    final t = (plain['t'] as String? ?? '').trim();
    switch (md?['type']) {
      case 'image':
        if (md?['stk'] == true) return '🙂 Sticker';
        if (md?['gif'] == true) return 'GIF';
        return md?['once'] == true ? '① Photo' : '📷 ${t.isEmpty ? 'Photo' : t}';
      case 'voice':
        return '🎤 Voice message';
      case 'doc':
        return '📄 ${md?['name'] ?? 'Document'}';
      case 'video':
        return '🎥 ${t.isEmpty ? 'Video' : t}';
      case 'poll':
        return '📊 ${md?['q'] ?? 'Poll'}';
      case 'location':
        return '📍 Location';
      case 'contact':
        return '👤 ${md?['name'] ?? 'Contact'}';
      case 'event':
        return '📅 ${md?['title'] ?? 'Event'}';
    }
    return t;
  }

  String? pendingCall;
  void Function(String callId)? onOpenCall;

  static const _callChannel = AndroidNotificationChannel(
    'calls',
    'Calls',
    description: 'Incoming calls',
    importance: Importance.max,
  );

  /// Rings (looping) for an incoming call while the app is open.
  Future<void> ring(String callId, String name, bool video) =>
      _showCall({'callId': callId, 'title': name, 'video': video ? '1' : '0'}, knownName: true);

  Future<void> stopRing() async {
    try {
      await _plugin.cancel(_idFor('call'));
    } catch (_) {}
  }

  Future<void> _showCall(Map<String, dynamic> data, {bool knownName = false}) async {
    await init();
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(_callChannel);
    var name = data['title'] as String? ?? 'BAATLY';
    try {
      await Api.instance.load();
      final uid = Api.instance.userId;
      if (uid != null && !knownName) {
        final peers = ((await _localData(uid))['peers'] as Map?)?.cast<String, dynamic>() ?? {};
        final n = (peers[data['from']] as Map?)?['name'] as String?;
        if (n != null && n.isNotEmpty) name = n;
      }
    } catch (_) {}
    final video = data['video'] == '1';
    await _plugin.show(
      _idFor('call'),
      name,
      video ? 'Incoming video call' : 'Incoming voice call',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _callChannel.id,
          _callChannel.name,
          channelDescription: _callChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: true,
          timeoutAfter: 45000,
          // FLAG_INSISTENT: keep ringing until answered/declined.
          additionalFlags: Int32List.fromList(const [4]),
          actions: const [
            AndroidNotificationAction('decline_call', 'Decline', showsUserInterface: false),
            AndroidNotificationAction('answer_call', 'Answer', showsUserInterface: true),
          ],
        ),
      ),
      payload: jsonEncode({'call': data['callId']}),
    );
  }

  /// Decrypts the pushed message on this phone and shows it.
  Future<void> showFromPush(Map<String, dynamic> data) async {
    if (data['type'] == 'call') {
      await _showCall(data);
      return;
    }
    if (data['type'] != 'msg') return;
    final chat = data['chat'] as String? ?? '';
    final from = data['from'] as String? ?? '';
    final group = data['group'] as String?;
    var title = data['title'] as String? ?? 'BAATLY';
    var text = data['preview'] as String? ?? 'New message';
    try {
      await Api.instance.load();
      final uid = Api.instance.userId;
      final body = data['body'] as String? ?? '';
      if (uid != null && body.isNotEmpty) {
        await E2E.instance.load(uid);
        final local = await _localData(uid);
        for (final c in (local['chats'] as List? ?? [])) {
          final m = (c as Map).cast<String, dynamic>();
          if ((m['peer'] == chat || m['gid'] == chat) && m['lk'] == true) {
            await _show(chat, 'BAATLY', 'New message', {'chat': chat, 'from': from, if (group != null) 'group': group, 'msgId': data['msgId'] ?? ''});
            return;
          }
        }
        final peers = (local['peers'] as Map?)?.cast<String, dynamic>() ?? {};
        final peer = (peers[from] as Map?)?.cast<String, dynamic>();
        var key = peer?['key'] as String?;
        if (key == null) {
          final d = await Api.instance.request('GET', '/v1/users/$from');
          key = (d['user'] as Map)['x25519'] as String?;
        }
        if (key != null) {
          final plain = await E2E.instance.open(body, key);
          // Delete / view-once / poll votes: nothing to show.
          if (const ['del', 'opened', 'vote', 'pin', 'unpin', 'live'].any(plain.containsKey)) return;
          text = _preview(plain);
        }
        final name = (peer?['name'] as String?)?.isNotEmpty == true
            ? peer!['name'] as String
            : (data['sender'] as String? ?? title);
        if (group != null) {
          text = '$name: $text';
        } else {
          title = name.isNotEmpty ? name : _pretty(data['phone'] as String? ?? '');
        }
      }
    } catch (_) {
      // Couldn't decrypt here (e.g. new phone): fall back to "New message".
    }
    await _show(chat, title, text, {'chat': chat, 'from': from, if (group != null) 'group': group, 'msgId': data['msgId'] ?? ''});
  }

  Future<void> _show(String chat, String title, String line, Map<String, dynamic> payload) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final key = 'notif_lines_$chat';
    final lines = <String>[...(prefs.getStringList(key) ?? const <String>[]), line];
    while (lines.length > 6) {
      lines.removeAt(0);
    }
    await prefs.setStringList(key, lines);
    final ids = <String>[...(prefs.getStringList('notif_ids_$chat') ?? const <String>[]), payload['msgId'] as String? ?? ''];
    await prefs.setStringList('notif_ids_$chat', ids.where((x) => x.isNotEmpty).toList());
    payload['msgIds'] = ids;
    final details = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      styleInformation: InboxStyleInformation(lines, contentTitle: title, summaryText: lines.length > 1 ? '${lines.length} new messages' : null),
      actions: const [
        AndroidNotificationAction('reply', 'Reply', inputs: [AndroidNotificationActionInput(label: 'Message')], showsUserInterface: false, cancelNotification: false),
        AndroidNotificationAction('read', 'Mark as read', showsUserInterface: false),
      ],
    );
    await _plugin.show(_idFor(chat), title, line, NotificationDetails(android: details), payload: jsonEncode(payload));
  }

  /// Opening a chat clears its notification.
  Future<void> clear(String chat) async {
    try {
      await _plugin.cancel(_idFor(chat));
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('notif_lines_$chat');
      await prefs.remove('notif_ids_$chat');
    } catch (_) {}
  }

  Future<void> handleAction(NotificationResponse r) async {
    final p = r.payload == null ? <String, dynamic>{} : (jsonDecode(r.payload!) as Map).cast<String, dynamic>();
    final chat = p['chat'] as String? ?? '';
    final call = p['call'] as String?;
    if (call != null) {
      await _plugin.cancel(_idFor('call'));
      if (r.actionId == 'decline_call') {
        try {
          await Api.instance.load();
          await Api.instance.request('POST', '/v1/calls/$call/signal', {'action': 'reject'});
        } catch (_) {}
        return;
      }
      pendingCall = call;
      onOpenCall?.call(call);
      return;
    }
    if (r.actionId == 'reply') {
      final text = (r.input ?? '').trim();
      if (text.isNotEmpty) await _reply(p, text);
      return;
    }
    if (r.actionId == 'read') {
      await _markRead(p);
      await clear(chat);
      return;
    }
    // Plain tap: open the chat.
    pendingChat = chat;
    onOpenChat?.call(chat);
  }

  Future<void> _markRead(Map<String, dynamic> p) async {
    try {
      await Api.instance.load();
      final ids = [for (final x in (p['msgIds'] as List? ?? [])) x.toString()].where((x) => x.isNotEmpty).toList();
      if (ids.isEmpty) return;
      await Api.instance.request('POST', '/v1/receipts', {'to': p['from'], 'msgIds': ids, 'status': 'read', if (p['group'] != null) 'group': p['group']});
    } catch (_) {}
  }

  /// Sends a reply straight from the notification (encrypted like any message).
  Future<void> _reply(Map<String, dynamic> p, String text) async {
    final chat = p['chat'] as String? ?? '';
    try {
      await Api.instance.load();
      final uid = Api.instance.userId;
      if (uid == null) return;
      await E2E.instance.load(uid);
      final now = DateTime.now().millisecondsSinceEpoch;
      final rnd = Random.secure();
      final msgId = base64Url.encode(List<int>.generate(12, (_) => rnd.nextInt(256))).replaceAll('=', '');
      final payload = {'t': text, 'ts': now};
      final group = p['group'] as String?;
      if (group != null) {
        final g = await Api.instance.request('GET', '/v1/groups/$group');
        final bodies = <String, String>{};
        for (final m in ((g['group'] as Map)['members'] as List)) {
          final mm = (m as Map).cast<String, dynamic>();
          if (mm['id'] == uid || mm['x25519'] == null) continue;
          bodies[mm['id'] as String] = await E2E.instance.seal(payload, mm['x25519'] as String);
        }
        await Api.instance.request('POST', '/v1/groups/$group/messages', {'msgId': msgId, 'bodies': bodies});
      } else {
        final d = await Api.instance.request('GET', '/v1/users/${p['from']}');
        final key = (d['user'] as Map)['x25519'] as String?;
        if (key == null) return;
        await Api.instance.request('POST', '/v1/messages', {'to': p['from'], 'msgId': msgId, 'body': await E2E.instance.seal(payload, key)});
      }
      await _markRead(p);
      // Remember it so the chat shows it next time the app opens.
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final out = <String>[...(prefs.getStringList('notif_outbox') ?? const <String>[]), jsonEncode({'chat': chat, 'id': msgId, 't': text, 'ts': now})];
      await prefs.setStringList('notif_outbox', out);
      await clear(chat);
    } catch (_) {}
  }
}
