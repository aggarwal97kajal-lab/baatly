import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'messenger.dart';
import 'status_service.dart';
import 'models.dart';

enum Wallpaper { mittiDots, desi, baatcheet, mausam, raat, plain }

extension WallpaperInfo on Wallpaper {
  String get label => switch (this) {
        Wallpaper.mittiDots => 'Mitti Dots',
        Wallpaper.desi => 'Desi',
        Wallpaper.baatcheet => 'Baatcheet',
        Wallpaper.mausam => 'Mausam',
        Wallpaper.raat => 'Raat',
        Wallpaper.plain => 'Plain',
      };

  String? get asset => switch (this) {
        Wallpaper.desi => 'assets/wallpapers/desi.jpg',
        Wallpaper.baatcheet => 'assets/wallpapers/baatcheet.jpg',
        Wallpaper.mausam => 'assets/wallpapers/mausam.jpg',
        Wallpaper.raat => 'assets/wallpapers/raat.jpg',
        _ => null,
      };
}

/// Simple in-memory app state for the UI demo build (Milestone 1).
/// No backend yet: messages live only on this phone and are lost on restart.
class AppState extends ChangeNotifier {
  AppState._() {
    _seed();
  }
  static final AppState instance = AppState._();

  ThemeMode themeMode = ThemeMode.system;
  Wallpaper wallpaper = Wallpaper.desi;
  bool reduceMotion = false;
  bool readReceipts = true;
  bool appLock = false;

  String name = '';
  String about = 'Let\'s talk!';
  String username = '';
  String phone = '';
  bool onboarded = false;
  /// Last number that logged in on this phone (kept after logout, for passkey login).
  String lastPhone = '';
  bool hasPasskey = false;

  // Status privacy (who can see my status).
  int statusAudience = 0; // 0 my contacts, 1 except…, 2 only share with…, 3 close friends
  Set<String> statusExcept = {};
  Set<String> statusOnly = {};
  Set<String> closeFriends = {};
  bool statusAllowSharing = true;

  // Privacy (enforced by the server). Rule: m 0 everyone, 1 my contacts,
  // 2 my contacts except x, 3 nobody.
  PrivacyRule lastSeenRule = PrivacyRule(0);
  int onlineRule = 0; // 0 everyone, 1 same as last seen
  PrivacyRule photoRule = PrivacyRule(0);
  PrivacyRule aboutRule = PrivacyRule(0);
  /// Disappearing messages for new chats, in seconds (0 = off).
  int defaultTimer = 0;
  /// My profile photo on this phone.
  String? myPhoto;
  /// People whose statuses I've hidden (user ids).
  Set<String> hiddenStatus = {};

  Map<String, dynamic> privacyJson() => {
        'lastSeen': lastSeenRule.toJson(),
        'online': onlineRule,
        'photo': photoRule.toJson(),
        'about': aboutRule.toJson(),
      };

  void applyPrivacyJson(Map<String, dynamic> j) {
    lastSeenRule = PrivacyRule.fromJson(j['lastSeen']);
    onlineRule = j['online'] == 1 ? 1 : 0;
    photoRule = PrivacyRule.fromJson(j['photo']);
    aboutRule = PrivacyRule.fromJson(j['about']);
    _save();
    notifyListeners();
  }

  final List<Chat> chats = [];
  /// True once real (server) chats replaced the demo chats.
  bool realChats = false;

  void useRealChats(List<Chat> list) {
    chats
      ..clear()
      ..addAll(list);
    realChats = true;
    notifyListeners();
  }

  bool realStatuses = false;

  void useRealStatuses(List<StatusItem> others, List<StatusSlide> mine) {
    statuses
      ..clear()
      ..addAll(others);
    myStatuses
      ..clear()
      ..addAll(mine);
    realStatuses = true;
    notifyListeners();
  }

  /// Lets the messenger refresh the UI.
  void changed() => notifyListeners();
  final List<CallLog> calls = [];
  final List<StatusItem> statuses = [];
  final List<StatusSlide> myStatuses = [];

  final _rnd = Random();

  // ------------------------------------------------------------- persistence
  // Profile + settings survive app restarts, so onboarding and the splash
  // animation only run once. Chats are still demo data (no backend yet).
  SharedPreferences? _prefs;

  Future<void> load() async {
    try {
      final p = _prefs = await SharedPreferences.getInstance();
      onboarded = p.getBool('onboarded') ?? false;
      name = p.getString('name') ?? '';
      username = p.getString('username') ?? '';
      about = p.getString('about') ?? about;
      phone = p.getString('phone') ?? '';
      lastPhone = p.getString('lastPhone') ?? '';
      hasPasskey = p.getBool('hasPasskey') ?? false;
      themeMode = ThemeMode.values[(p.getInt('theme') ?? ThemeMode.system.index).clamp(0, ThemeMode.values.length - 1)];
      wallpaper = Wallpaper.values[(p.getInt('wallpaper') ?? Wallpaper.desi.index).clamp(0, Wallpaper.values.length - 1)];
      reduceMotion = p.getBool('reduceMotion') ?? false;
      readReceipts = p.getBool('readReceipts') ?? true;
      appLock = p.getBool('appLock') ?? false;
      statusAudience = (p.getInt('statusAudience') ?? 0).clamp(0, 3);
      statusExcept = (p.getStringList('statusExcept') ?? []).toSet();
      statusOnly = (p.getStringList('statusOnly') ?? []).toSet();
      closeFriends = (p.getStringList('closeFriends') ?? []).toSet();
      statusAllowSharing = p.getBool('statusAllowSharing') ?? true;
      try {
        final pj = p.getString('privacy');
        if (pj != null) {
          final j = jsonDecode(pj) as Map<String, dynamic>;
          lastSeenRule = PrivacyRule.fromJson(j['lastSeen']);
          onlineRule = j['online'] == 1 ? 1 : 0;
          photoRule = PrivacyRule.fromJson(j['photo']);
          aboutRule = PrivacyRule.fromJson(j['about']);
        }
      } catch (_) {}
      defaultTimer = p.getInt('defaultTimer') ?? 0;
      myPhoto = p.getString('myPhoto');
      hiddenStatus = (p.getStringList('hiddenStatus') ?? []).toSet();
    } catch (_) {
      // Storage unavailable (e.g. tests): fall back to defaults.
    }
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setBool('onboarded', onboarded);
    p.setString('name', name);
    p.setString('username', username);
    p.setString('about', about);
    p.setString('phone', phone);
    if (phone.isNotEmpty) lastPhone = phone;
    p.setString('lastPhone', lastPhone);
    p.setBool('hasPasskey', hasPasskey);
    p.setInt('theme', themeMode.index);
    p.setInt('wallpaper', wallpaper.index);
    p.setBool('reduceMotion', reduceMotion);
    p.setBool('readReceipts', readReceipts);
    p.setBool('appLock', appLock);
    p.setInt('statusAudience', statusAudience);
    p.setStringList('statusExcept', statusExcept.toList());
    p.setStringList('statusOnly', statusOnly.toList());
    p.setStringList('closeFriends', closeFriends.toList());
    p.setBool('statusAllowSharing', statusAllowSharing);
    p.setString('privacy', jsonEncode(privacyJson()));
    p.setInt('defaultTimer', defaultTimer);
    p.setStringList('hiddenStatus', hiddenStatus.toList());
    if (myPhoto == null) {
      p.remove('myPhoto');
    } else {
      p.setString('myPhoto', myPhoto!);
    }
  }

  /// Demo helper: forget the profile and show onboarding again.
  Future<void> resetDemo() async {
    await Messenger.instance.stop();
    final keepPhone = lastPhone.isNotEmpty ? lastPhone : phone;
    final keepPasskey = hasPasskey;
    await _prefs?.clear();
    lastPhone = keepPhone;
    hasPasskey = keepPasskey;
    await _prefs?.setString('lastPhone', lastPhone);
    await _prefs?.setBool('hasPasskey', hasPasskey);
    onboarded = false;
    name = '';
    username = '';
    phone = '';
    notifyListeners();
  }

  void setPasskey(bool v) {
    hasPasskey = v;
    _save();
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _save();
    notifyListeners();
  }

  void setWallpaper(Wallpaper w) {
    wallpaper = w;
    _save();
    notifyListeners();
  }

  void toggle(void Function() f) {
    f();
    _save();
    notifyListeners();
  }

  void finishOnboarding({required String name, required String username, required String about}) {
    this.name = name.trim().isEmpty ? 'You' : name.trim();
    this.username = username.trim();
    this.about = about.trim().isEmpty ? 'Let\'s talk!' : about.trim();
    onboarded = true;
    _save();
    notifyListeners();
  }

  /// Chat currently on screen, so incoming messages there don't count as unread.
  String? activeChatId;

  void openChat(Chat c) {
    c.unread = 0;
    notifyListeners();
  }

  void _receive(Chat chat, String text) {
    chat.typing = false;
    chat.messages.add(Message(
      id: '${DateTime.now().microsecondsSinceEpoch}r',
      text: text,
      fromMe: false,
      time: DateTime.now(),
    ));
    if (activeChatId != chat.id) chat.unread++;
    notifyListeners();
  }

  bool _demoStarted = false;

  /// Demo only: a contact starts typing a few seconds after the app opens,
  /// so the "typing…" state can be seen from the chat list too.
  void startDemoActivity() {
    if (_demoStarted || realChats) return;
    _demoStarted = true;
    final riya = chats.firstWhere((c) => c.id == 'riya', orElse: () => chats.first);
    Timer(const Duration(seconds: 5), () {
      riya.typing = true;
      notifyListeners();
    });
    Timer(const Duration(seconds: 9), () => _receive(riya, 'Aur haan, cake bhi le aana 🎂'));
  }

  /// Sends a message locally and simulates delivery/read and a reply,
  /// so the UI flow can be felt before the real backend exists.
  void send(Chat chat, String text) {
    if (chat.isReal) {
      Messenger.instance.send(chat, text);
      return;
    }
    final m = Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text,
      fromMe: true,
      time: DateTime.now(),
      status: MsgStatus.sending,
    );
    chat.messages.add(m);
    notifyListeners();
    Timer(const Duration(milliseconds: 400), () {
      m.status = MsgStatus.sent;
      notifyListeners();
    });
    Timer(const Duration(milliseconds: 900), () {
      m.status = MsgStatus.delivered;
      notifyListeners();
    });
    if (chat.isGroup) return;
    Timer(const Duration(milliseconds: 1600), () {
      m.status = MsgStatus.read;
      chat.typing = true;
      notifyListeners();
    });
    Timer(const Duration(milliseconds: 3600), () {
      const replies = [
        'Haan bilkul 😊',
        'Theek hai, milte hain!',
        'Haha sahi hai',
        'Ek min, call karti hoon',
        'Done 👍',
        'Achha idea hai!',
      ];
      _receive(chat, replies[_rnd.nextInt(replies.length)]);
    });
  }

  void react(Message m, String emoji) {
    m.reaction = m.reaction == emoji ? null : emoji;
    notifyListeners();
  }

  /// Removes a chat (and its messages) from this phone.
  void deleteChat(Chat c) {
    chats.remove(c);
    notifyListeners();
  }

  void deleteMessage(Chat c, Message m) {
    c.messages.remove(m);
    notifyListeners();
  }

  void addMyStatus(StatusSlide s) {
    myStatuses.add(s);
    notifyListeners();
    if (Messenger.instance.active) StatusService.instance.post(s);
  }

  void deleteMyStatus(StatusSlide s) {
    myStatuses.remove(s);
    notifyListeners();
    if (s.remoteId != null) StatusService.instance.delete(s);
  }

  /// [until] null = unmute.
  void muteChat(Chat c, DateTime? until) {
    c.mutedUntil = until;
    notifyListeners();
    if (c.isReal) Messenger.instance.syncMute(c);
  }

  void toggleStar(Message m) {
    m.starred = !m.starred;
    notifyListeners();
  }

  void setStatusHidden(String userId, bool hidden) {
    hidden ? hiddenStatus.add(userId) : hiddenStatus.remove(userId);
    _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- seed data
  void _seed() {
    final now = DateTime.now();
    DateTime ago(int mins) => now.subtract(Duration(minutes: mins));

    chats.addAll([
      Chat(id: 'riya', name: 'Riya Sharma', initials: 'RS', colorIndex: 0, online: true, pinned: true, unread: 2, about: 'Chai > coffee', messages: [
        Message(id: 'r1', text: 'Hey! Kal ka plan final?', fromMe: false, time: ago(70)),
        Message(id: 'r2', text: 'Haan bilkul. 7 baje Cafe Mocha?', fromMe: true, time: ago(69)),
        Message(id: 'r3', text: 'Perfect\nMain table book kar deti hoon', fromMe: false, time: ago(66), reaction: '❤️'),
        Message(id: 'r4', text: '', fromMe: true, time: ago(64), kind: MsgKind.voice, voiceSeconds: 42),
        Message(id: 'r5', text: 'Done! Table for 2\nWindow wali seat mili 😄', fromMe: false, time: ago(3)),
        Message(id: 'r6', text: 'Kal 7 baje pakka? Table book ho gayi', fromMe: false, time: ago(2)),
      ]),
      Chat(id: 'ghar', name: 'Ghar Wale', initials: 'GW', colorIndex: 1, isGroup: true, pinned: true, unread: 5, about: 'Papa, Mummy, Riya, Aap', messages: [
        Message(id: 'g1', text: 'Papa: Sunday ko sab aa rahe ho?', fromMe: false, time: ago(30)),
        Message(id: 'g2', text: 'Haan Papa, 11 baje tak!', fromMe: true, time: ago(26)),
        Message(id: 'g3', text: 'Mummy: Lunch mein chole bhature 😋', fromMe: false, time: ago(25)),
      ]),
      Chat(id: 'aman', name: 'Aman Verma', initials: 'AV', colorIndex: 2, about: 'Busy hoon, baad mein call karta', messages: [
        Message(id: 'a1', text: 'Bhai Goa trip ka kya hua?', fromMe: true, time: ago(200)),
        Message(id: 'a2', text: '', fromMe: false, time: ago(195), kind: MsgKind.voice, voiceSeconds: 42),
      ]),
      Chat(id: 'office', name: 'Office — Finance', initials: 'OF', colorIndex: 3, isGroup: true, muted: true, about: 'Neha, Rohit, Aap', messages: [
        Message(id: 'o1', text: 'Neha: Invoice sheet update kar di hai', fromMe: false, time: ago(60 * 20)),
      ]),
      Chat(id: 'kabir', name: 'Kabir', initials: 'K', colorIndex: 4, about: 'Jo hoga dekha jayega', messages: [
        Message(id: 'k1', text: 'Kal milte hain?', fromMe: false, time: ago(60 * 22)),
        Message(id: 'k2', text: 'Haha theek hai bhai, kal milte', fromMe: true, time: ago(60 * 21)),
      ]),
      Chat(id: 'priya', name: 'Priya Nair', initials: 'PN', colorIndex: 5, about: 'Let\'s talk!', messages: [
        Message(id: 'p1', text: '📷 Photo', fromMe: false, time: ago(60 * 48)),
      ]),
      Chat(id: 'old', name: 'Loan Offers', initials: 'LO', colorIndex: 6, archived: true, messages: [
        Message(id: 'l1', text: 'Pre-approved loan ₹5,00,000!', fromMe: false, time: ago(60 * 72)),
      ]),
    ]);

    calls.addAll([
      CallLog('Riya Sharma', 'RS', 0, CallKind.incoming, true, 'Today, 9:20 · 12 min'),
      CallLog('Ghar Wale', 'GW', 1, CallKind.incoming, true, 'Today, 8:02 · Group'),
      CallLog('Aman Verma', 'AV', 2, CallKind.missed, false, 'Missed · Today, 7:41 (2)'),
      CallLog('Kabir', 'K', 4, CallKind.outgoing, false, 'Yesterday, 10:15 PM · 3 min'),
      CallLog('Office — Finance', 'OF', 3, CallKind.outgoing, true, 'Yesterday, 4:30 PM · 41 min'),
      CallLog('Priya Nair', 'PN', 5, CallKind.missed, false, 'Missed · Mon, 6:12 PM'),
    ]);

    statuses.addAll([
      StatusItem('Riya', 'RS', 0, '42 min ago', [StatusSlide.text('Aaj ki chai, purane dost ke saath ☕', 0xFFC8553D), StatusSlide.text('Cafe Mocha vibes', 0xFFB5651D)]),
      StatusItem('Ghar Wale', 'GW', 1, '1 hour ago', [StatusSlide.text('Sunday lunch 🍛', 0xFF2E3A59)]),
      StatusItem('Aman', 'AV', 2, '3 hours ago', [StatusSlide.text('Goa cancel 😭', 0xFF7A5BA6), StatusSlide.text('Next time pakka', 0xFF3E7C5A)]),
      StatusItem('Kabir', 'K', 4, 'Yesterday', [StatusSlide.text('Match day 🏏', 0xFF3E7C5A)]),
      StatusItem('Priya Nair', 'PN', 5, 'Today, 7:12 AM', [StatusSlide.text('Good morning ☀️', 0xFFB5651D)], seen: true),
    ]);
  }
}

String hhmm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String chatTime(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inHours < 24 && now.day == t.day) return hhmm(t);
  if (diff.inDays < 2) return 'Yesterday';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return days[t.weekday - 1];
}


/// Who can see something: m 0 everyone, 1 my contacts, 2 my contacts except [x], 3 nobody.
class PrivacyRule {
  final int m;
  final Set<String> x;
  PrivacyRule(this.m, [Set<String>? x]) : x = x ?? {};
  Map<String, dynamic> toJson() => {'m': m, 'x': x.toList()};
  factory PrivacyRule.fromJson(dynamic j) {
    if (j is! Map) return PrivacyRule(0);
    final m = (j['m'] as num?)?.toInt() ?? 0;
    return PrivacyRule(m.clamp(0, 3), {for (final e in (j['x'] as List? ?? [])) e.toString()});
  }
  String label() => switch (m) {
        1 => 'My contacts',
        2 => x.isEmpty ? 'My contacts except…' : '${x.length} contact${x.length == 1 ? '' : 's'} excluded',
        3 => 'Nobody',
        _ => 'Everyone',
      };
}
