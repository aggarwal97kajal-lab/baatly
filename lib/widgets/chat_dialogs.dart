import 'dart:io';

import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../screens/chat/chat_info_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'photo_viewer.dart';
import '../data/calls.dart';

String muteLabel(Chat c) {
  if (!c.muted) return 'Off';
  if (c.mutedForever) return 'Always';
  final u = c.mutedUntil!;
  final now = DateTime.now();
  final sameDay = u.year == now.year && u.month == now.month && u.day == now.day;
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final time = '${hhmm(u)} ${u.hour < 12 ? 'AM' : 'PM'}';
  return sameDay ? 'Until $time' : 'Until ${u.day} ${m[u.month - 1]}, $time';
}

/// Mute with a duration: 8 hours, 1 week or always. Unmutes directly if already muted.
Future<void> showMuteDialog(BuildContext context, Chat chat) async {
  final s = AppState.instance;
  if (chat.muted) {
    s.muteChat(chat, null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text('${chat.name} unmuted')));
    return;
  }
  const options = [('8 hours', Duration(hours: 8)), ('1 week', Duration(days: 7)), ('Always', null)];
  var choice = 2;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Mute notifications'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            "${chat.isGroup ? 'Other members' : chat.name} won't know you muted this chat. "
            '${chat.isGroup ? "You'll still be notified if someone mentions you." : ''}',
            style: TextStyle(fontSize: 13.5, color: ctx.bc.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          RadioGroup<int>(
            groupValue: choice,
            onChanged: (v) => setD(() => choice = v ?? choice),
            child: Column(children: [
              for (var i = 0; i < options.length; i++)
                RadioListTile<int>(
                  value: i,
                  contentPadding: EdgeInsets.zero,
                  title: Text(options[i].$1),
                ),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final d = options[choice].$2;
  s.muteChat(chat, d == null ? DateTime(9999) : DateTime.now().add(d));
}

/// Tapping a chat's avatar in the list: large photo with quick actions.
void showProfilePeek(BuildContext context, Chat chat) {
  final c = Mitti.avatarColors[chat.colorIndex % Mitti.avatarColors.length];
  showDialog<void>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 48),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(fit: StackFit.expand, children: [
            if (chat.photo != null)
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  PhotoViewerScreen.open(context, chat.photo, chat.name);
                },
                child: Image.file(File(chat.photo!), fit: BoxFit.cover, filterQuality: FilterQuality.high),
              )
            else
              Container(
                color: c,
                alignment: Alignment.center,
                child: Text(chat.initials,
                    style: const TextStyle(fontSize: 96, color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x80000000), Color(0x00000000)]),
                ),
                child: Text(chat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        Container(
          color: ctx.bc.surface,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            IconButton(
              tooltip: 'Message',
              icon: Icon(Icons.chat_bubble_outline_rounded, color: ctx.primary),
              onPressed: () {
                Navigator.pop(ctx);
                AppState.instance.openChat(chat);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
              },
            ),
            IconButton(
              tooltip: 'Audio call',
              icon: Icon(Icons.call_outlined, color: ctx.primary),
              onPressed: () {
                if (chat.peerId == null) return showComingSoon(ctx, 'Audio call');
                Navigator.pop(ctx);
                CallService.instance.start(chat, video: false);
              },
            ),
            IconButton(
              tooltip: 'Video call',
              icon: Icon(Icons.videocam_outlined, color: ctx.primary),
              onPressed: () {
                if (chat.peerId == null) return showComingSoon(ctx, 'Video call');
                Navigator.pop(ctx);
                CallService.instance.start(chat, video: true);
              },
            ),
            IconButton(
              tooltip: 'Info',
              icon: Icon(Icons.info_outline_rounded, color: ctx.primary),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatInfoScreen(chat: chat)));
              },
            ),
          ]),
        ),
      ]),
    ),
  );
}
