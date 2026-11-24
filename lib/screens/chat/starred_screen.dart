import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'chat_screen.dart';

/// All starred messages (or just one chat's).
class StarredScreen extends StatelessWidget {
  final Chat? only;
  const StarredScreen({super.key, this.only});

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final items = <(Chat, Message)>[
          for (final c in only == null ? s.chats : [only!])
            for (final m in c.messages)
              if (m.starred) (c, m),
        ]..sort((a, b) => b.$2.time.compareTo(a.$2.time));
        return Scaffold(
          appBar: AppBar(title: const Text('Starred messages')),
          body: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.star_outline_rounded, size: 64, color: context.primary),
                      const SizedBox(height: 12),
                      Text('Tap and hold on any message to star it, so you can easily find it later.',
                          textAlign: TextAlign.center, style: TextStyle(color: bc.muted, height: 1.4)),
                    ]),
                  ),
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: bc.line),
                  itemBuilder: (context, i) {
                    final (c, m) = items[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: Avatar(initials: c.initials, colorIndex: c.colorIndex, photo: c.photo, size: 40),
                      title: Text(m.fromMe ? 'You ▸ ${c.name}' : '${c.name} ▸ You',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(m.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: bc.text)),
                      ),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(chatTime(m.time), style: TextStyle(fontSize: 11.5, color: bc.muted)),
                        const SizedBox(height: 4),
                        Icon(Icons.star_rounded, size: 16, color: context.primary),
                      ]),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: c))),
                      onLongPress: () => s.toggleStar(m),
                    );
                  },
                ),
        );
      },
    );
  }
}
