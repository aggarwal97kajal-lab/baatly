import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../nav.dart';
import '../screens/home/home_shell.dart';
import '../screens/onboarding/phone_screen.dart';
import '../screens/onboarding/splash_screen.dart';
import 'api.dart';
import 'app_state.dart';
import 'messenger.dart';
import 'secure_screen.dart';

/// A BAATLY account kept on this phone but not open right now.
class SavedAccount {
  final String uid;
  final String name;
  final String phone;
  final String? photo;
  final int unread;
  SavedAccount(this.uid, this.name, this.phone, this.photo, this.unread);

  /// "Suraj · ••0654"
  String get label {
    final p = phone.replaceAll(RegExp(r'\D'), '');
    final tail = p.length >= 4 ? p.substring(p.length - 4) : p;
    return tail.isEmpty ? name : '$name · ••$tail';
  }
}

/// Two numbers in one app. Each account keeps its own session, chats
/// (chats_<id>.json), encryption key and settings. Only the open account is
/// connected; the other still gets notifications (decrypted on this phone)
/// and switching takes a second.
class Accounts {
  Accounts._();
  static final Accounts instance = Accounts._();

  static const max = 2;
  static const _store = FlutterSecureStorage();
  static const _key = 'acct_slots';
  /// Device-wide settings that stay the same whichever account is open.
  static const _global = {'appLock', 'app_pin', 'app_pin_salt', 'net_sent', 'net_recv', 'theme', 'palette', 'reduceMotion'};
  static bool _isGlobal(String k) => _global.contains(k) || k.startsWith('acct_unread_') || k.startsWith('notif_');

  /// Set while "Add account" is in progress (so the phone screen can offer Cancel).
  bool adding = false;

  /// The other account(s), for the switcher (refresh() keeps it current).
  final others = ValueNotifier<List<SavedAccount>>(const []);
  Future<void> refresh() async {
    try {
      others.value = await saved();
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _slots() async {
    try {
      final raw = await _store.read(key: _key);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveSlots(Map<String, dynamic> s) => _store.write(key: _key, value: jsonEncode(s));

  /// The other account(s) saved on this phone.
  Future<List<SavedAccount>> saved() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final s = await _slots();
    return [
      for (final e in s.entries)
        SavedAccount(
          e.key,
          ((e.value as Map)['name'] as String?) ?? 'BAATLY',
          ((e.value as Map)['phone'] as String?) ?? '',
          (e.value as Map)['photo'] as String?,
          p.getInt('acct_unread_${e.key}') ?? 0,
        ),
    ];
  }

  /// Label for an account id (background notifications), or null if not a saved one.
  static Future<String?> labelFor(String uid) async {
    try {
      final raw = await _store.read(key: _key);
      if (raw == null) return null;
      final m = ((jsonDecode(raw) as Map)[uid] as Map?)?.cast<String, dynamic>();
      if (m == null) return null;
      return SavedAccount(uid, m['name'] as String? ?? 'BAATLY', m['phone'] as String? ?? '', null, 0).label;
    } catch (_) {
      return null;
    }
  }

  /// Notification on the other account: count it for the switcher badge.
  static Future<void> bumpUnread(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      await p.setInt('acct_unread_$uid', (p.getInt('acct_unread_$uid') ?? 0) + 1);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _snapshotPrefs() async {
    final p = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    for (final k in p.getKeys()) {
      if (_isGlobal(k)) continue;
      final v = p.get(k);
      if (v is bool) {
        out[k] = ['b', v];
      } else if (v is int) {
        out[k] = ['i', v];
      } else if (v is double) {
        out[k] = ['d', v];
      } else if (v is String) {
        out[k] = ['s', v];
      } else if (v is List) {
        out[k] = ['l', v.map((e) => '$e').toList()];
      }
    }
    return out;
  }

  Future<void> _clearAccountPrefs() async {
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().toList()) {
      if (!_isGlobal(k)) await p.remove(k);
    }
  }

  Future<void> _restorePrefs(Map<String, dynamic> snap) async {
    final p = await SharedPreferences.getInstance();
    for (final e in snap.entries) {
      final t = (e.value as List)[0] as String;
      final v = (e.value as List)[1];
      switch (t) {
        case 'b':
          await p.setBool(e.key, v as bool);
        case 'i':
          await p.setInt(e.key, (v as num).toInt());
        case 'd':
          await p.setDouble(e.key, (v as num).toDouble());
        case 's':
          await p.setString(e.key, v as String);
        case 'l':
          await p.setStringList(e.key, [for (final x in v as List) '$x']);
      }
    }
  }

  /// Puts the open account into a slot (session stays logged in on the server).
  Future<bool> _parkActive() async {
    final uid = Api.instance.userId;
    final token = Api.instance.token;
    if (uid == null || token == null) return false;
    await Messenger.instance.stop();
    final s = AppState.instance;
    final slots = await _slots();
    slots[uid] = {'token': token, 'name': s.name, 'phone': s.phone, 'photo': s.myPhoto, 'prefs': await _snapshotPrefs()};
    await _saveSlots(slots);
    return true;
  }

  Future<void> _go(Widget w) async {
    await refresh();
    await AppState.instance.load();
    await Api.instance.load();
    SecureScreen.refresh();
    AppState.instance.changed();
    navigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => w), (_) => false);
  }

  /// Switch to a saved account.
  Future<void> switchTo(String uid) async {
    final slots = await _slots();
    final target = (slots[uid] as Map?)?.cast<String, dynamic>();
    if (target == null || uid == Api.instance.userId) return;
    await _parkActive();
    final fresh = await _slots();
    fresh.remove(uid);
    await _saveSlots(fresh);
    await _clearAccountPrefs();
    await _restorePrefs(((target['prefs'] as Map?) ?? {}).cast<String, dynamic>());
    await Api.instance.adoptSession(target['token'] as String, uid);
    final p = await SharedPreferences.getInstance();
    await p.remove('acct_unread_$uid');
    adding = false;
    await _go(const HomeShell());
  }

  /// "Add account": park this one and log in with another number.
  Future<void> beginAdd() async {
    if ((await _slots()).length >= max - 1) return;
    if (!await _parkActive()) return;
    await _clearAccountPrefs();
    await Api.instance.dropLocalSession();
    adding = true;
    await _go(const PhoneScreen());
  }

  /// Back out of "Add account": reopen the account we came from.
  Future<void> cancelAdd() async {
    final slots = await _slots();
    adding = false;
    if (slots.isEmpty) return;
    final uid = slots.keys.first;
    final target = (slots[uid] as Map).cast<String, dynamic>();
    slots.remove(uid);
    await _saveSlots(slots);
    await _clearAccountPrefs();
    await _restorePrefs(((target['prefs'] as Map?) ?? {}).cast<String, dynamic>());
    await Api.instance.adoptSession(target['token'] as String, uid);
    await _go(const HomeShell());
  }

  /// After logging out (or deleting) the open account: open the other one if there is one.
  Future<bool> afterLogout() async {
    final slots = await _slots();
    if (slots.isEmpty) return false;
    final uid = slots.keys.first;
    final target = (slots[uid] as Map).cast<String, dynamic>();
    slots.remove(uid);
    await _saveSlots(slots);
    await _clearAccountPrefs();
    await _restorePrefs(((target['prefs'] as Map?) ?? {}).cast<String, dynamic>());
    await Api.instance.adoptSession(target['token'] as String, uid);
    await _go(const HomeShell());
    return true;
  }

  /// The saved session was rejected by the server (logged out elsewhere): forget it.
  Future<void> forget(String uid) async {
    final slots = await _slots();
    slots.remove(uid);
    await _saveSlots(slots);
  }

  /// For the logout flow when there's no other account.
  static Widget get splash => const SplashScreen();
}
