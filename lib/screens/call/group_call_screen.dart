import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/group_calls.dart';
import '../../data/messenger.dart';
import '../../theme/tokens.dart';

/// Full-screen group call: one tile per person (up to 4).
class GroupCallScreen extends StatelessWidget {
  final GroupCallSession session;
  const GroupCallScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final gs = GroupCallService.instance;
    return PopScope(
      canPop: session.state == GroupCallState.ended,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final s = session;
          Widget btn(IconData i, String label, VoidCallback onTap, {Color? bg, bool on = false}) => Column(mainAxisSize: MainAxisSize.min, children: [
                Material(
                  color: bg ?? (on ? Colors.white : Colors.white24),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: Padding(padding: const EdgeInsets.all(15), child: Icon(i, color: on && bg == null ? Colors.black87 : Colors.white, size: 26)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]);

          final tiles = <Widget>[
            _Tile(
              name: 'You',
              id: 'me',
              renderer: s.video && !s.cameraOff ? s.localView : null,
              mirror: true,
              muted: s.muted,
            ),
            for (final p in s.peers.values)
              _Tile(
                name: Messenger.instance.nameFor(p.id),
                id: p.id,
                renderer: s.video && p.hasVideo && p.connected ? p.view : null,
                audio: p.viewReady ? p.view : null,
                connecting: !p.connected,
              ),
          ];

          Widget body;
          if (s.state == GroupCallState.incoming || (s.peers.isEmpty && s.state != GroupCallState.live)) {
            final who = s.ringFrom == null ? null : Messenger.instance.nameFor(s.ringFrom!);
            body = Column(children: [
              const SizedBox(height: 60),
              CircleAvatar(
                radius: 54,
                backgroundColor: Mitti.avatarColors[s.groupId.length % Mitti.avatarColors.length],
                child: const Icon(Icons.groups_rounded, size: 56, color: Colors.white),
              ),
              const SizedBox(height: 18),
              Text(s.groupName, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(s.stateText, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              if (who != null && s.state == GroupCallState.incoming) ...[
                const SizedBox(height: 4),
                Text('$who is calling', style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ]);
          } else {
            body = Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(children: [
                  Text(s.groupName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(s.stateText, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: LayoutBuilder(builder: (context, box) {
                    final n = tiles.length;
                    final cols = n <= 2 ? 1 : 2;
                    final rows = (n / cols).ceil();
                    final w = box.maxWidth / cols;
                    final h = box.maxHeight / rows;
                    return Wrap(children: [for (final t in tiles) SizedBox(width: w, height: h, child: Padding(padding: const EdgeInsets.all(4), child: t))]);
                  }),
                ),
              ),
            ]);
          }

          return Scaffold(
            backgroundColor: const Color(0xFF1B1512),
            body: SafeArea(
              child: Column(children: [
                Expanded(child: body),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  child: s.state == GroupCallState.incoming
                      ? Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          btn(Icons.call_end_rounded, 'Decline', gs.decline, bg: const Color(0xFFD32F2F)),
                          btn(s.video ? Icons.videocam_rounded : Icons.call_rounded, 'Join', gs.accept, bg: const Color(0xFF2E7D32)),
                        ])
                      : Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          btn(s.speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded, 'Speaker', gs.toggleSpeaker, on: s.speaker),
                          if (s.video) btn(s.cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded, 'Camera', gs.toggleCamera, on: s.cameraOff),
                          if (s.video) btn(Icons.cameraswitch_rounded, 'Flip', gs.switchCamera),
                          btn(s.muted ? Icons.mic_off_rounded : Icons.mic_rounded, 'Mute', gs.toggleMute, on: s.muted),
                          btn(Icons.call_end_rounded, 'Leave', () => gs.leave(), bg: const Color(0xFFD32F2F)),
                        ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String name, id;
  final RTCVideoRenderer? renderer;
  /// Audio-only people still need their stream attached to play sound.
  final RTCVideoRenderer? audio;
  final bool mirror, muted, connecting;
  const _Tile({required this.name, required this.id, this.renderer, this.audio, this.mirror = false, this.muted = false, this.connecting = false});

  @override
  Widget build(BuildContext context) {
    final color = Mitti.avatarColors[id.length % Mitti.avatarColors.length];
    final initials = Messenger.initialsOf(name);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(fit: StackFit.expand, children: [
        Container(color: const Color(0xFF2A211C)),
        if (renderer != null)
          RTCVideoView(renderer!, mirror: mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
        else ...[
          if (audio != null) Opacity(opacity: 0, child: RTCVideoView(audio!)),
          Center(
            child: CircleAvatar(
              radius: 38,
              backgroundColor: color,
              child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        Positioned(
          left: 10,
          bottom: 10,
          right: 10,
          child: Row(children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                child: Text(connecting ? '$name · connecting…' : name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              ),
            ),
            if (muted) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.mic_off_rounded, color: Colors.white, size: 18)),
          ]),
        ),
      ]),
    );
  }
}
