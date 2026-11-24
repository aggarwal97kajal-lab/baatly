import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'models.dart';

enum Wallpaper { mittiDots, desi, baatcheet, mausam, raat, plain }

extension WallpaperInfo on Wallpaper {
  String get label => switch (this) {
        Wallpaper.mittiDots => 'Mitti Dots',
        Wallpaper.desi => 'Desi',
        Wallpaper.baatcheet => 'Baatcheet',
        Wallpaper.mausam => 'Mausam',
        Wallpaper.raat => 'Raat',
        Wallpaper.plain => 'Saada',
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
  String about = 'Baat karte hain!';
  String username = '';
  String phone = '';
  bool onboarded = false;

  final List<Chat> chats = [];
  final List<CallLog> calls = [];
  final List<StatusItem> statuses = [];
  final List<String> myStatuses = [];

  final _rnd = Random();

  void setTheme(ThemeMode m) {
    themeMode = m;
    notifyListeners();
  }

  void setWallpaper(Wallpaper w) {
    wallpaper = w;
    notifyListeners();
  }

  void toggle(void Function() f) {
    f();
    notifyListeners();
  }

  void finishOnboarding({required String name, required String username, required String about}) {
    this.name = name.trim().isEmpty ? 'Aap' : name.trim();
    this.username = username.trim();
    this.about = about.trim().isEmpty ? 'Baat karte hain!' : about.trim();
    onboarded = true;
    notifyListeners();
  }

  void openChat(Chat c) {
    c.unread = 0;
    notifyListeners();
  }

  /// Sends a message locally and simulates delivery/read and a reply,
  /// so the UI flow can be felt before the real backend exists.
  void send(Chat chat, String text, {void Function()? onTyping, void Function()? onReply}) {
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
      onTyping?.call();
      notifyListeners();
    });
    Timer(const Duration(milliseconds: 3200), () {
      const replies = [
        'Haan bilkul 😊',
        'Theek hai, milte hain!',
        'Haha sahi hai',
        'Ek min, call karti hoon',
        'Done 👍',
        'Achha idea hai!',
      ];
      chat.messages.add(Message(
        id: '${DateTime.now().microsecondsSinceEpoch}r',
        text: replies[_rnd.nextInt(replies.length)],
        fromMe: false,
        time: DateTime.now(),
      ));
      onReply?.call();
      notifyListeners();
    });
  }

  void react(Message m, String emoji) {
    m.reaction = m.reaction == emoji ? null : emoji;
    notifyListeners();
  }

  void deleteMessage(Chat c, Message m) {
    c.messages.remove(m);
    notifyListeners();
  }

  void addMyStatus(String text) {
    myStatuses.add(text);
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
      Chat(id: 'priya', name: 'Priya Nair', initials: 'PN', colorIndex: 5, about: 'Baat karte hain!', messages: [
        Message(id: 'p1', text: '📷 Photo', fromMe: false, time: ago(60 * 48)),
      ]),
      Chat(id: 'old', name: 'Loan Offers', initials: 'LO', colorIndex: 6, archived: true, messages: [
        Message(id: 'l1', text: 'Pre-approved loan ₹5,00,000!', fromMe: false, time: ago(60 * 72)),
      ]),
    ]);

    calls.addAll([
      CallLog('Riya Sharma', 'RS', 0, CallKind.incoming, true, 'Aaj, 9:20 · 12 min'),
      CallLog('Ghar Wale', 'GW', 1, CallKind.incoming, true, 'Aaj, 8:02 · Group'),
      CallLog('Aman Verma', 'AV', 2, CallKind.missed, false, 'Missed · Aaj, 7:41 (2)'),
      CallLog('Kabir', 'K', 4, CallKind.outgoing, false, 'Kal, 10:15 PM · 3 min'),
      CallLog('Office — Finance', 'OF', 3, CallKind.outgoing, true, 'Kal, 4:30 PM · 41 min'),
      CallLog('Priya Nair', 'PN', 5, CallKind.missed, false, 'Missed · Mon, 6:12 PM'),
    ]);

    statuses.addAll([
      StatusItem('Riya', 'RS', 0, '42 min pehle', ['Aaj ki chai, purane dost ke saath ☕', 'Cafe Mocha vibes'], [0xFFC8553D, 0xFFB5651D]),
      StatusItem('Ghar Wale', 'GW', 1, '1 ghanta pehle', ['Sunday lunch 🍛'], [0xFF2E3A59]),
      StatusItem('Aman', 'AV', 2, '3 ghante pehle', ['Goa cancel 😭', 'Next time pakka'], [0xFF7A5BA6, 0xFF3E7C5A]),
      StatusItem('Kabir', 'K', 4, 'Kal', ['Match day 🏏'], [0xFF3E7C5A]),
      StatusItem('Priya Nair', 'PN', 5, 'Aaj, 7:12 AM', ['Good morning ☀️'], [0xFFB5651D], seen: true),
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
  if (diff.inDays < 2) return 'Kal';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return days[t.weekday - 1];
}
