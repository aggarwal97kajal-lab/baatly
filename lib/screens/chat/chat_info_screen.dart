import 'package:flutter/material.dart';
import '../../data/birthdays.dart';
import '../settings/birthdays_screen.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chat_dialogs.dart';
import '../../widgets/common.dart';
import '../../widgets/photo_viewer.dart';
import 'starred_screen.dart';
import 'chat_tools.dart';
import 'safety_screens.dart';
import 'contact_actions.dart';
import 'group_screens.dart';
import 'chat_screen.dart';
import '../../data/contacts.dart';
import '../settings/privacy_screen.dart';
import '../../data/messenger.dart';
import '../../data/calls.dart';
import '../../data/group_calls.dart';
import '../settings/wallpaper_screen.dart';

class ChatInfoScreen extends StatelessWidget {
  final Chat chat;
  const ChatInfoScreen({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final s = AppState.instance;
    Widget action(IconData i, String l, String what) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              if (chat.peerId != null && (what == 'Audio call' || what == 'Video call')) {
                CallService.instance.start(chat, video: what == 'Video call');
              } else if (chat.isRealGroup && (what == 'Audio call' || what == 'Video call')) {
                GroupCallService.instance.start(chat, video: what == 'Video call');
              } else {
                showComingSoon(context, what);
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: bc.surface, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                Icon(i, color: context.primary),
                const SizedBox(height: 4),
                Text(l, style: TextStyle(fontSize: 12, color: bc.text)),
              ]),
            ),
          ),
        );
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        backgroundColor: bc.bg,
        appBar: AppBar(
          backgroundColor: bc.bg,
          actions: [
            if (chat.peerId != null && chat.phone != null)
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'share':
                      shareContactCard(context, chat);
                    case 'edit':
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditContactScreen(chat: chat)));
                    case 'book':
                      viewInAddressBook(context, chat);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'share', child: Text('Share')),
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'book', child: Text('View in address book')),
                ],
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            Center(
              child: GestureDetector(
                onTap: () => PhotoViewerScreen.open(context, chat.photo, chat.name),
                child: Hero(tag: 'av-${chat.id}', child: Avatar(initials: chat.initials, colorIndex: chat.colorIndex, photo: chat.photo, size: 104)),
              ),
            ),
            const SizedBox(height: 12),
            Text(chat.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: bc.text)),
            if (!chat.isGroup && chat.phone != null)
              Text(ContactBook.pretty(chat.phone!), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: bc.muted)),
            Text(chat.isGroup ? 'Group · ${chat.about}' : chat.about,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: bc.muted)),
            const SizedBox(height: 16),
            Row(children: [
              action(Icons.call_outlined, 'Audio', 'Audio call'),
              action(Icons.videocam_outlined, 'Video', 'Video call'),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatSearchScreen(chat: chat))),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: bc.surface, borderRadius: BorderRadius.circular(18)),
                    child: Column(children: [
                      Icon(Icons.search_rounded, color: context.primary),
                      const SizedBox(height: 4),
                      Text('Search', style: TextStyle(fontSize: 12, color: bc.text)),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            _Card(children: [
              if (!chat.isGroup && chat.peerId != null)
                ListTile(
                  leading: Icon(Icons.cake_outlined, color: context.primary),
                  title: const Text('Birthday'),
                  subtitle: Text(s.birthdayOf(chat.peerId!) == null
                      ? 'Add their birthday to get a reminder'
                      : '${Birthdays.fmt(s.birthdayOf(chat.peerId!)!)}${s.manualBirthdays.containsKey(chat.peerId) ? ' · added by you' : ''}'),
                  trailing: s.knownBirthdays.containsKey(chat.peerId) && !s.manualBirthdays.containsKey(chat.peerId)
                      ? null
                      : Icon(Icons.edit_outlined, color: bc.muted, size: 20),
                  onTap: s.knownBirthdays.containsKey(chat.peerId) && !s.manualBirthdays.containsKey(chat.peerId)
                      ? null
                      : () => editManualBirthday(context, chat.peerId!, chat.name),
                ),
              ListTile(
                leading: Icon(Icons.perm_media_outlined, color: context.primary),
                title: const Text('Media, links and docs'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatMediaScreen(chat: chat))),
              ),
              ListTile(
                leading: Icon(Icons.star_outline_rounded, color: context.primary),
                title: const Text('Starred messages'),
                trailing: Text('${chat.messages.where((m) => m.starred).length}', style: TextStyle(color: bc.muted)),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StarredScreen(only: chat))),
              ),
              ListTile(
                leading: Icon(Icons.notifications_off_outlined, color: context.primary),
                title: const Text('Mute notifications'),
                subtitle: Text(muteLabel(chat)),
                trailing: Switch(value: chat.muted, onChanged: (_) => showMuteDialog(context, chat)),
                onTap: () => showMuteDialog(context, chat),
              ),
              SwitchListTile(
                secondary: Icon(Icons.push_pin_outlined, color: context.primary),
                title: const Text('Pin chat'),
                value: chat.pinned,
                onChanged: (v) => s.toggle(() => chat.pinned = v),
              ),
              ListTile(
                leading: Icon(Icons.wallpaper_rounded, color: context.primary),
                title: const Text('Wallpaper'),
                trailing: Text(s.wallpaper.label, style: TextStyle(color: bc.muted)),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WallpaperScreen())),
              ),
              ListTile(
                leading: Icon(Icons.timer_outlined, color: context.primary),
                title: const Text('Disappearing messages'),
                trailing: Text(PrivacyScreen.timerLabel(chat.disappear), style: TextStyle(color: bc.muted)),
                onTap: () async {
                  var v = chat.disappear;
                  final r = await showDialog<int>(
                    context: context,
                    builder: (d) => StatefulBuilder(
                      builder: (d, setD) => AlertDialog(
                        title: const Text('Disappearing messages'),
                        content: RadioGroup<int>(
                          groupValue: v,
                          onChanged: (x) => setD(() => v = x ?? 0),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            for (final o in const [86400, 604800, 7776000, 0])
                              RadioListTile<int>(value: o, contentPadding: EdgeInsets.zero, title: Text(PrivacyScreen.timerLabel(o))),
                          ]),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(d, v), child: const Text('OK')),
                        ],
                      ),
                    ),
                  );
                  if (r != null) s.toggle(() => chat.disappear = r);
                },
              ),
              ListTile(
                leading: Icon(Icons.lock_outline_rounded, color: context.primary),
                title: const Text('Encryption'),
                subtitle: Text(chat.isReal ? 'Messages and calls are end-to-end encrypted. Tap to verify.' : 'Demo chat'),
                onTap: chat.peerId == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SafetyNumberScreen(chat: chat))),
              ),
            ]),
            if (chat.peerId != null) ...[
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final common = [
                  for (final g in s.chats)
                    if (g.isRealGroup && !g.left && g.members.contains(chat.peerId)) g
                ];
                return _Card(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(common.isEmpty ? 'No groups in common' : '${common.length} group${common.length == 1 ? '' : 's'} in common',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: bc.muted)),
                    ),
                  ),
                  ListTile(
                    leading: CircleAvatar(backgroundColor: context.primary, child: const Icon(Icons.group_add_rounded, color: Colors.white)),
                    title: Text('Create group with ${chat.name.split(' ').first}'),
                    onTap: () => startNewGroup(context, preselected: {chat.peerId!}),
                  ),
                  for (final g in common)
                    ListTile(
                      leading: Avatar(initials: g.initials, colorIndex: g.colorIndex, photo: g.photo, size: 40),
                      title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        g.members.map((u) => u == Messenger.instance.myId ? 'You' : Messenger.instance.nameFor(u)).take(6).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: g))),
                    ),
                ]);
              }),
            ],
            const SizedBox(height: 12),
            _Card(children: [
              ListTile(
                leading: const Icon(Icons.block_rounded, color: Color(0xFFB3261E)),
                title: Text('${Messenger.instance.isBlocked(chat.peerId) ? 'Unblock' : 'Block'} ${chat.name}', style: const TextStyle(color: Color(0xFFB3261E))),
                onTap: chat.peerId == null ? () => showComingSoon(context, 'Block') : () => confirmBlock(context, chat),
              ),
              if (chat.peerId != null)
                ListTile(
                  leading: const Icon(Icons.thumb_down_alt_outlined, color: Color(0xFFB3261E)),
                  title: Text('Report ${chat.name}', style: const TextStyle(color: Color(0xFFB3261E))),
                  onTap: () => showReportDialog(context, chat),
                ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFB3261E)),
                title: const Text('Clear chat', style: TextStyle(color: Color(0xFFB3261E))),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Clear this chat?'),
                      content: const Text('All messages in this chat will be deleted from this phone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Clear chat')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  s.toggle(() => chat.messages.clear());
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ]),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: context.bc.surface, borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}
