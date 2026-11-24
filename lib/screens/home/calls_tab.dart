import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

class CallsTab extends StatelessWidget {
  const CallsTab({super.key});

  @override
  Widget build(BuildContext context) {
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
                    onTap: () => showComingSoon(context, a.$2),
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
                Flexible(child: Text(c.when, overflow: TextOverflow.ellipsis)),
              ]),
              trailing: IconButton(
                icon: Icon(c.video ? Icons.videocam_outlined : Icons.call_outlined, color: context.primary),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallDemoScreen(log: c))),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Demo build: call screen only. Real audio/video comes in Milestone 5.',
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
