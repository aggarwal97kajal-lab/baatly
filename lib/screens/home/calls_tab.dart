import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../config.dart';

import '../../data/app_state.dart';
import '../../data/calls.dart';
import '../../data/group_calls.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

class CallsTab extends StatelessWidget {
  const CallsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: AppState.instance, builder: (context, _) => _build(context));
  }

  Future<void> _action(BuildContext context, String what) async {
    final s = AppState.instance;
    final people = s.chats.where((c) => c.peerId != null && c.isReal).toList();
    final groups = s.chats.where((c) => c.isRealGroup && !c.left).toList();
    Widget sheet(String title, List<Chat> list, Widget Function(BuildContext, Chat) trailing, {String empty = 'No chats yet'}) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            child: ListView(shrinkWrap: true, children: [
              ListTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
              if (list.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(empty, textAlign: TextAlign.center)),
              for (final c in list)
                Builder(
                  builder: (ctx) => ListTile(
                    leading: Avatar(initials: c.initials, colorIndex: c.colorIndex, photo: c.photo, size: 42),
                    title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: trailing(ctx, c),
                  ),
                ),
            ]),
          ),
        );
    Widget callButtons(BuildContext ctx, Chat c, {bool group = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            onPressed: () {
              Navigator.pop(ctx);
              group ? GroupCallService.instance.start(c, video: false) : CallService.instance.start(c, video: false);
            },
            icon: Icon(Icons.call_outlined, color: context.primary),
          ),
          IconButton(
            onPressed: () {
              Navigator.pop(ctx);
              group ? GroupCallService.instance.start(c, video: true) : CallService.instance.start(c, video: true);
            },
            icon: Icon(Icons.videocam_outlined, color: context.primary),
          ),
        ]);
    switch (what) {
      case 'Call':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => sheet('New call', people, (ctx, c) => callButtons(ctx, c), empty: 'Your BAATLY contacts will show here'),
        );
      case 'Group call':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => sheet('Group call', groups, (ctx, c) => callButtons(ctx, c, group: true), empty: 'Make a group first, then call everyone in it'),
        );
      case 'Link':
        final me = Messenger.instance.myId;
        if (me == null) return;
        final video = await showModalBottomSheet<bool>(
          context: context,
          builder: (sh) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(
                title: Text('Create call link', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                subtitle: Text('Anyone with BAATLY who opens the link will call you.'),
              ),
              ListTile(leading: const Icon(Icons.call_outlined), title: const Text('Voice call link'), onTap: () => Navigator.pop(sh, false)),
              ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Video call link'), onTap: () => Navigator.pop(sh, true)),
            ]),
          ),
        );
        if (video == null) return;
        final link = '$kApiBase/c/$me${video ? '?v=1' : ''}';
        await SharePlus.instance.share(ShareParams(text: 'Join my BAATLY ${video ? 'video' : 'voice'} call: $link'));
      case 'Favourite':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => StatefulBuilder(
            builder: (ctx, set) => sheet('Favourites', people, (c2, c) => Checkbox(
                  value: c.favourite,
                  onChanged: (v) {
                    s.toggle(() => c.favourite = v == true);
                    set(() {});
                  },
                ), empty: 'Your BAATLY contacts will show here'),
          ),
        );
    }
  }

  String _when(CallLog c) {
    final at = c.at;
    if (at == null) return c.when;
    final now = DateTime.now();
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final time = '$h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(at.year, at.month, at.day);
    final day = d == today ? 'Today' : (today.difference(d).inDays == 1 ? 'Yesterday' : '${at.day}/${at.month}');
    final rest = c.when.contains(' · ') ? ' · ${c.when.split(' · ').last}' : '';
    return '${c.kind == CallKind.missed ? 'Missed · ' : ''}$day, $time${c.when.startsWith('Missed') ? '' : rest}';
  }

  Widget _build(BuildContext context) {
    final bc = context.bc;
    final calls = AppState.instance.calls;
    return Scaffold(
      backgroundColor: bc.bg,
      body: SafeArea(
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
            child: Text('Calls', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: bc.text)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final a in [(Icons.call_rounded, 'Call'), (Icons.groups_rounded, 'Group call'), (Icons.link_rounded, 'Link'), (Icons.star_rounded, 'Favourite')])
                  InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: () => _action(context, a.$2),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(children: [
                        CircleAvatar(radius: 26, backgroundColor: bc.raised, child: Icon(a.$1, color: context.primary)),
                        const SizedBox(height: 6),
                        Text(a.$2, style: TextStyle(fontSize: 11.5, color: bc.text)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          if (AppState.instance.chats.any((c) => c.favourite && c.peerId != null)) ...[
            const SectionLabel('Favourites'),
            for (final c in AppState.instance.chats.where((c) => c.favourite && c.peerId != null))
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 22),
                leading: Avatar(initials: c.initials, colorIndex: c.colorIndex, photo: c.photo, size: 44),
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(onPressed: () => CallService.instance.start(c, video: false), icon: Icon(Icons.call_outlined, color: context.primary)),
                  IconButton(onPressed: () => CallService.instance.start(c, video: true), icon: Icon(Icons.videocam_outlined, color: context.primary)),
                ]),
              ),
          ],
          const SectionLabel('Recent'),
          for (final c in calls)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 22),
              leading: Avatar(initials: c.initials, colorIndex: c.colorIndex, size: 46),
              title: Text(c.name, style: TextStyle(fontWeight: FontWeight.w700, color: c.kind == CallKind.missed ? Mitti.error : bc.text)),
              subtitle: Row(children: [
                Icon(
                  c.kind == CallKind.outgoing ? Icons.call_made_rounded : Icons.call_received_rounded,
                  size: 15,
                  color: c.kind == CallKind.missed ? Mitti.error : (c.kind == CallKind.incoming ? Mitti.success : bc.muted),
                ),
                const SizedBox(width: 4),
                Flexible(child: Text(_when(c), overflow: TextOverflow.ellipsis)),
              ]),
              trailing: IconButton(
                icon: Icon(c.video ? Icons.videocam_outlined : Icons.call_outlined, color: context.primary),
                onPressed: () {
                  if (c.peerId != null && c.peerId!.startsWith('g:')) {
                    final g = Messenger.instance.chatById(c.peerId!.substring(2));
                    if (g != null) GroupCallService.instance.start(g, video: c.video);
                    return;
                  }
                  final chat = c.peerId == null ? null : Messenger.instance.chatById(c.peerId!);
                  if (chat != null) {
                    CallService.instance.start(chat, video: c.video);
                  } else if (c.peerId != null) {
                    CallService.instance.start(Messenger.instance.chatWithUser(c.peerId!, c.name, '', null), video: c.video);
                  } else {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallDemoScreen(log: c)));
                  }
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(calls.isEmpty ? 'No calls yet. Start one from any chat.' : 'Calls are encrypted and go directly between phones.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: bc.muted)),
          ),
        ]),
      ),
    );
  }
}

/// Visual-only outgoing/active call screen (no audio yet).
class CallDemoScreen extends StatefulWidget {
  final CallLog log;
  const CallDemoScreen({super.key, required this.log});
  @override
  State<CallDemoScreen> createState() => _CallDemoScreenState();
}

class _CallDemoScreenState extends State<CallDemoScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  Timer? _t;
  int _secs = 0;
  bool _connected = false, _mute = false, _speaker = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secs++;
        if (_secs == 3) _connected = true;
      });
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  String get _label {
    if (!_connected) return 'Ringing…';
    final s = _secs - 3;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const cream = Mitti.nightText;
    Widget btn(IconData i, String l, bool on, VoidCallback f) => Column(children: [
          GestureDetector(
            onTap: f,
            child: AnimatedContainer(
              duration: Mitti.fast,
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: on ? cream : Mitti.nightRaised, shape: BoxShape.circle),
              child: Icon(i, color: on ? Mitti.night : cream),
            ),
          ),
          const SizedBox(height: 8),
          Text(l, style: const TextStyle(color: cream, fontSize: 12)),
        ]);
    return Scaffold(
      backgroundColor: Mitti.night,
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.keyboard_arrow_down_rounded, color: cream, size: 30)),
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Stack(alignment: Alignment.center, children: [
              for (final k in [0.0, 0.5])
                Opacity(
                  opacity: (1 - ((_pulse.value + k) % 1)) * 0.5,
                  child: Container(
                    width: 150 + 110 * ((_pulse.value + k) % 1),
                    height: 150 + 110 * ((_pulse.value + k) % 1),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Mitti.terracotta, width: 2)),
                  ),
                ),
              child!,
            ]),
            child: Avatar(initials: widget.log.initials, colorIndex: widget.log.colorIndex, size: 140),
          ),
          const SizedBox(height: 40),
          Text(widget.log.name, style: const TextStyle(color: cream, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_label, style: const TextStyle(color: Color(0xB3F5ECE3), fontSize: 15)),
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
            decoration: BoxDecoration(color: Mitti.nightSurface, borderRadius: BorderRadius.circular(32)),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                btn(_speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded, 'Speaker', _speaker, () => setState(() => _speaker = !_speaker)),
                btn(Icons.videocam_outlined, 'Video', false, () => showComingSoon(context, 'Video')),
                btn(_mute ? Icons.mic_off_rounded : Icons.mic_none_rounded, 'Mute', _mute, () => setState(() => _mute = !_mute)),
                btn(Icons.bluetooth_rounded, 'Bluetooth', false, () => showComingSoon(context, 'Bluetooth')),
              ]),
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: const BoxDecoration(color: Mitti.error, shape: BoxShape.circle),
                  child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
