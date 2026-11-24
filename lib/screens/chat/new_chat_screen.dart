import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'chat_screen.dart';

class NewChatScreen extends StatelessWidget {
  const NewChatScreen({super.key});

  static final _contacts = [
    ('Ananya Gupta', 'AG', 1, 'Mumbai · Designer'),
    ('Neha (Office)', 'NO', 3, 'Finance team'),
    ('Somesh', 'S', 6, 'Building things'),
    ('Deepak Bhaiya', 'DB', 0, 'Chill, whatever happens'),
  ];

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final s = AppState.instance;
    final existing = s.chats.where((c) => !c.isGroup && !c.archived).toList();
    Widget action(IconData i, String t) => ListTile(
          leading: CircleAvatar(backgroundColor: context.primary, child: Icon(i, color: Colors.white)),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () => showComingSoon(context, t),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: ListView(children: [
        action(Icons.group_add_rounded, 'New group'),
        action(Icons.groups_rounded, 'New community'),
        action(Icons.person_add_alt_1_rounded, 'New contact'),
        const SectionLabel('Contacts on BAATLY'),
        for (final c in existing)
          ListTile(
            leading: Avatar(initials: c.initials, colorIndex: c.colorIndex, size: 44),
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(c.about, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chat: c))),
          ),
        for (final c in _contacts)
          ListTile(
            leading: Avatar(initials: c.$2, colorIndex: c.$3, size: 44),
            title: Text(c.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(c.$4),
            onTap: () {
              final chat = Chat(id: c.$1, name: c.$1, initials: c.$2, colorIndex: c.$3, about: c.$4);
              s.toggle(() => s.chats.add(chat));
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
            },
          ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Demo build: these are sample contacts. Real contact sync comes later.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: bc.muted)),
        ),
      ]),
    );
  }
}
