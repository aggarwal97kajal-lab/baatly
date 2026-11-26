import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'api.dart';
import 'app_state.dart';
import 'contacts.dart';
import 'messenger.dart';

/// One upcoming birthday.
class BirthdayEntry {
  final String id; // BAATLY user id (or chat id for one I added by hand)
  final String name;
  final DateTime next; // next birthday, local midnight
  final bool manual;
  BirthdayEntry(this.id, this.name, this.next, this.manual);
  bool get today {
    final n = DateTime.now();
    return next.year == n.year && next.month == n.month && next.day == n.day;
  }
}

/// Birthdays: my date of birth (asked once, required), birthdays shared with me,
/// phone-book birthdays and ones I add myself. Reminders are kept by the server,
/// so they arrive at 12:00 am even if BAATLY is closed.
class Birthdays {
  Birthdays._();
  static final Birthdays instance = Birthdays._();

  static const _schedKey = 'bd_sched';  // per account (kept with that account's settings)
  bool _syncing = false;
  DateTime? _lastSync;
  String? _syncedFor;

  /// 'MM-DD' -> next local midnight of that day (today counts).
  static DateTime nextOf(String mmdd) {
    final parts = mmdd.split('-');
    final mo = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 1;
    final d = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
    final now = DateTime.now();
    DateTime on(int y) {
      // 29 Feb in a normal year → 28 Feb.
      final last = DateTime(y, mo + 1, 0).day;
      return DateTime(y, mo, d > last ? last : d);
    }

    final today = DateTime(now.year, now.month, now.day);
    final t = on(now.year);
    return t.isBefore(today) ? on(now.year + 1) : t;
  }

  static String fmt(String mmdd) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final p = mmdd.split('-');
    final mo = (int.tryParse(p.first) ?? 1).clamp(1, 12);
    return '${int.tryParse(p.length > 1 ? p[1] : '') ?? 1} ${months[mo - 1]}';
  }

  String nameOf(String id) {
    final chat = Messenger.instance.chatById(id);
    if (chat != null) return chat.name;
    for (final c in AppState.instance.chats) {
      if (c.peerId == id) return c.name;
    }
    return Messenger.instance.nameFor(id);
  }

  String? chatIdFor(String id) {
    if (Messenger.instance.chatById(id) != null) return id;
    for (final c in AppState.instance.chats) {
      if (c.peerId == id && !c.isGroup) return c.id;
    }
    return null;
  }

  List<BirthdayEntry> upcoming() {
    final s = AppState.instance;
    final me = Messenger.instance.myId;
    final all = <String, (String, bool)>{
      for (final e in s.knownBirthdays.entries) e.key: (e.value, false),
      for (final e in s.manualBirthdays.entries) e.key: (e.value, true),
    };
    all.remove(me);
    final out = [for (final e in all.entries) BirthdayEntry(e.key, nameOf(e.key), nextOf(e.value.$1), e.value.$2)]
      ..sort((a, b) => a.next.compareTo(b.next));
    return out;
  }

  List<BirthdayEntry> today() => upcoming().where((e) => e.today).toList();

  // ------------------------------------------------------------------ my date of birth
  Future<void> loadMine() async {
    if (!kHasBackend || !Api.instance.loggedIn) return;
    final d = await Api.instance.request('GET', '/v1/me/birthday');
    final s = AppState.instance;
    final date = d['date'] as String?;
    s.toggle(() {
      if (date != null && date.isNotEmpty) s.myDob = date;
      final sh = d['share'];
      if (sh is int) s.birthdayShare = sh;
    });
  }

  Future<void> saveMine(String date, {int? share}) async {
    final s = AppState.instance;
    final sh = share ?? s.birthdayShare;
    if (kHasBackend && Api.instance.loggedIn) {
      await Api.instance.request('PUT', '/v1/me/birthday', {'date': date, 'share': sh});
    }
    s.toggle(() {
      s.myDob = date;
      s.birthdayShare = sh;
    });
  }

  // ------------------------------------------------------------------ sync + reminders
  /// Fetches birthdays shared with me, adds phone-book ones, and books the
  /// 12:00 am reminders for the next 30 days. Cheap; runs at most every 6 hours.
  Future<void> sync({bool force = false}) async {
    if (_syncing || !kHasBackend || !Api.instance.loggedIn) return;
    if (!force && _syncedFor == Api.instance.userId && _lastSync != null && DateTime.now().difference(_lastSync!).inHours < 6) return;
    _syncing = true;
    try {
      final s = AppState.instance;
      final next = <String, String>{...ContactBook.instance.userBirthdays};
      try {
        final d = await Api.instance.request('GET', '/v1/birthdays');
        for (final x in (d['items'] as List? ?? [])) {
          final m = (x as Map).cast<String, dynamic>();
          final id = m['id'] as String?;
          final bd = m['bd'] as String?;
          if (id != null && bd != null && RegExp(r'^\d{2}-\d{2}$').hasMatch(bd)) next[id] = bd;
        }
      } catch (_) {}
      if (next.isNotEmpty || s.knownBirthdays.isNotEmpty) {
        s.toggle(() => s.knownBirthdays = next);
      }
      await _schedule();
      _lastSync = DateTime.now();
      _syncedFor = Api.instance.userId;
    } finally {
      _syncing = false;
    }
  }

  Future<void> _schedule() async {
    final p = await SharedPreferences.getInstance();
    Map<String, int> booked;
    try {
      booked = (jsonDecode(p.getString(_schedKey) ?? '{}') as Map).map((k, v) => MapEntry('$k', (v as num).toInt()));
    } catch (_) {
      booked = {};
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    booked.removeWhere((_, at) => at < now);
    final s = AppState.instance;
    final want = <String, (int, String, String?)>{};
    if (s.birthdayReminders) {
      final limit = DateTime.now().add(const Duration(days: 30));
      for (final e in upcoming()) {
        if (e.next.isAfter(limit) || want.length >= 40) break;
        if (e.next.millisecondsSinceEpoch <= now) continue; // today's 12:00 am already passed
        want['bd-${e.id}-${e.next.year}'.replaceAll(RegExp(r'[^\w-]'), '')] = (e.next.millisecondsSinceEpoch, e.id, chatIdFor(e.id));
      }
    }
    for (final id in booked.keys.toList()) {
      if (want.containsKey(id)) continue;
      try {
        await Api.instance.request('DELETE', '/v1/reminders/$id');
      } catch (_) {}
      booked.remove(id);
    }
    for (final e in want.entries) {
      if (booked.containsKey(e.key)) continue;
      try {
        await Api.instance.request('POST', '/v1/reminders', {'id': e.key, 'at': e.value.$1, 'chat': e.value.$3 ?? 'u:${e.value.$2}', 'msgId': 'bday:${e.value.$2}'});
        booked[e.key] = e.value.$1;
      } catch (_) {}
    }
    await p.setString(_schedKey, jsonEncode(booked));
  }

  /// Settings changed (reminders on/off, a birthday added): re-book.
  void changed() => unawaited(sync(force: true));
}
