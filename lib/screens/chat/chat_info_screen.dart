import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chat_dialogs.dart';
import '../../widgets/common.dart';
import '../../widgets/photo_viewer.dart';
import 'starred_screen.dart';
import 'chat_tools.dart';
import 'safety_screens.dart';
import '../settings/privacy_screen.dart';
import '../../data/messenger.dart';
import '../../data/calls.dart';
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
        appBar: AppBar(backgroundColor: bc.bg),
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
                onTap: () {
                  s.toggle(() => chat.messages.clear());
                  Navigator.pop(context);
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
