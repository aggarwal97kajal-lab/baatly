import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/calls.dart';
import '../../data/messenger.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

/// Full-screen voice / video call.
class CallScreen extends StatelessWidget {
  final CallSession session;
  const CallScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final cs = CallService.instance;
    return PopScope(
      canPop: session.state == CallState.ended,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final s = session;
          final showRemote = s.video && s.state == CallState.connected && s.remoteVideo;
          final showLocal = s.video && !s.cameraOff && s.state != CallState.incoming && s.state != CallState.ended;
          Widget btn(IconData i, String label, VoidCallback onTap, {Color? bg, Color fg = Colors.white, bool on = false}) => Column(mainAxisSize: MainAxisSize.min, children: [
                Material(
                  color: bg ?? (on ? Colors.white : Colors.white24),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: Padding(padding: const EdgeInsets.all(16), child: Icon(i, color: on && bg == null ? Colors.black87 : fg, size: 28)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]);
          return Scaffold(
            backgroundColor: const Color(0xFF1B1512),
            body: Stack(children: [
              if (showRemote)
                Positioned.fill(child: RTCVideoView(s.remoteView, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
              else
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A2A22), Color(0xFF15100D)])),
                  ),
                ),
              if (showLocal)
                Positioned(
                  right: 16,
                  top: MediaQuery.of(context).padding.top + 16,
                  width: 110,
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: RTCVideoView(s.localView, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                  ),
                ),
              SafeArea(
                child: Column(children: [
                  const SizedBox(height: 40),
                  if (!showRemote) ...[
                    Avatar(initials: Messenger.initialsOf(s.peerName), colorIndex: s.peerId.length % 7, photo: Messenger.instance.photoOf(s.peerId), size: 112),
                    const SizedBox(height: 18),
                  ],
                  Text(s.peerName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.lock_outline_rounded, size: 14, color: Colors.white60),
                    const SizedBox(width: 4),
                    Text(s.stateText, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  ]),
                  const Spacer(),
                  if (s.state == CallState.incoming)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(40, 0, 40, 50),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        btn(Icons.call_end_rounded, 'Decline', cs.decline, bg: Mitti.error),
                        btn(s.video ? Icons.videocam_rounded : Icons.call_rounded, 'Accept', cs.accept, bg: Mitti.success),
                      ]),
                    )
                  else if (s.state != CallState.ended)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      child: Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          btn(s.speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded, 'Speaker', () => cs.speaker(s, !s.speaker), on: s.speaker),
                          if (s.video) btn(s.cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded, 'Camera', cs.toggleCamera, on: s.cameraOff),
                          if (s.video) btn(Icons.cameraswitch_rounded, 'Flip', cs.switchCamera),
                          btn(s.muted ? Icons.mic_off_rounded : Icons.mic_rounded, 'Mute', cs.toggleMute, on: s.muted),
                        ]),
                        const SizedBox(height: 28),
                        btn(Icons.call_end_rounded, 'End', () => cs.hangUp(reason: 'Call ended'), bg: Mitti.error),
                      ]),
                    )
                  else
                    const SizedBox(height: 120),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}
