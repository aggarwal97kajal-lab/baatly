import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:share_plus/share_plus.dart';

import '../../config.dart';
import '../../data/app_state.dart';
import '../../data/calls.dart';
import '../../data/messenger.dart';
import '../../nav.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';
import 'add_to_call.dart';

/// Full-screen voice / video call, laid out like WhatsApp.
class CallScreen extends StatefulWidget {
  final CallSession session;
  const CallScreen({super.key, required this.session});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _controls = true;
  Offset? _selfPos;
  bool _swap = false;
  bool _encNote = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _encNote = false);
    });
  }

  CallSession get s => widget.session;
  CallService get cs => CallService.instance;

  String get _status {
    if (s.state == CallState.calling && _encNote) return 'End-to-end encrypted';
    return s.stateText;
  }

  Future<void> _share() async {
    final me = Messenger.instance.myId;
    if (me == null) return;
    final link = '$kApiBase/c/$me${s.video ? '?v=1' : ''}';
    await SharePlus.instance.share(ShareParams(text: 'Join my BAATLY ${s.video ? 'video' : 'voice'} call: $link'));
  }

  Future<void> _message() async {
    final chat = await Messenger.instance.chatForUser(s.peerId);
    if (chat == null) return;
    cs.minimise();
    AppState.instance.openChat(chat);
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
  }

  Future<void> _more() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF221C19),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sh) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          if (s.video && s.local?.getVideoTracks().isNotEmpty == true)
            _sheetItem(sh, Icons.cameraswitch_rounded, 'Flip camera', cs.switchCamera),
          _sheetItem(sh, s.speaker ? Icons.phone_in_talk_rounded : Icons.volume_up_rounded, s.speaker ? 'Use phone earpiece' : 'Use speaker',
              () => cs.speaker(s, !s.speaker)),
          _sheetItem(sh, Icons.chat_bubble_outline_rounded, 'Message', _message),
          _sheetItem(sh, Icons.link_rounded, 'Share call link', _share),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _sheetItem(BuildContext sh, IconData i, String t, VoidCallback f) => ListTile(
        leading: Icon(i, color: Colors.white70),
        title: Text(t, style: const TextStyle(color: Colors.white)),
        onTap: () {
          Navigator.pop(sh);
          f();
        },
      );

  Widget _round(IconData i, String? label, VoidCallback? onTap, {bool on = false, Color? bg, double size = 58}) {
    final b = Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: bg ?? (on ? Colors.white : Colors.white.withOpacity(0.14)),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Icon(i, color: on && bg == null ? Colors.black87 : Colors.white, size: size * 0.45)),
        ),
      ),
      if (label != null) ...[
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
      ],
    ]);
    return b;
  }

  Widget _topBar({required bool overVideo}) {
    final top = Row(children: [
      IconButton(
        tooltip: 'Minimise',
        icon: const Icon(Icons.close_fullscreen_rounded, color: Colors.white),
        onPressed: s.state == CallState.incoming || s.state == CallState.ended ? null : cs.minimise,
      ),
      Expanded(
        child: Column(children: [
          Text(s.peerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: overVideo ? 19 : 22, fontWeight: FontWeight.w700, shadows: const [Shadow(blurRadius: 6, color: Colors.black54)])),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (s.state == CallState.connected || _status == 'End-to-end encrypted') ...[
              const Icon(Icons.lock_outline_rounded, size: 13, color: Colors.white70),
              const SizedBox(width: 4),
            ],
            Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 14, shadows: [Shadow(blurRadius: 6, color: Colors.black54)])),
          ]),
        ]),
      ),
      IconButton(
        tooltip: 'Add person',
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        onPressed: s.state == CallState.connected ? () => addPersonToCall(context, s) : null,
      ),
    ]);
    return top;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: s.state == CallState.ended,
      onPopInvokedWithResult: (did, _) {
        if (!did) cs.minimise();
      },
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final hasLocalVideo = s.local?.getVideoTracks().isNotEmpty == true && !s.cameraOff;
          final videoLayout = (s.video || s.remoteVideo) && s.state != CallState.incoming && s.state != CallState.ended;
          return Scaffold(
            backgroundColor: const Color(0xFF1B1512),
            body: videoLayout ? _video(hasLocalVideo) : _voice(),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ voice layout
  Widget _voice() {
    final incoming = s.state == CallState.incoming;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A2A22), Color(0xFF15100D)]),
      ),
      child: SafeArea(
        child: Column(children: [
          const SizedBox(height: 8),
          _topBar(overVideo: false),
          const Spacer(),
          Avatar(initials: Messenger.initialsOf(s.peerName), colorIndex: s.peerId.length % 7, photo: Messenger.instance.photoOf(s.peerId), size: 132),
          const Spacer(),
          if (incoming)
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 50),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _round(Icons.call_end_rounded, 'Decline', cs.decline, bg: Mitti.error, size: 66),
                _round(s.video ? Icons.videocam_rounded : Icons.call_rounded, 'Accept', cs.accept, bg: Mitti.success, size: 66),
              ]),
            )
          else if (s.state != CallState.ended)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
              padding: const EdgeInsets.fromLTRB(10, 20, 10, 16),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), borderRadius: BorderRadius.circular(30)),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _round(Icons.volume_up_rounded, 'Speaker', () => cs.speaker(s, !s.speaker), on: s.speaker),
                  _round(Icons.videocam_rounded, 'Video', cs.toggleVideo),
                  _round(s.muted ? Icons.mic_off_rounded : Icons.mic_rounded, 'Mute', cs.toggleMute, on: s.muted),
                ]),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _round(Icons.more_horiz_rounded, 'More', _more),
                  _round(Icons.ios_share_rounded, 'Share', _share),
                  _round(Icons.call_end_rounded, 'End', () => cs.hangUp(reason: 'Call ended'), bg: Mitti.error),
                ]),
              ]),
            )
          else
            const SizedBox(height: 150),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------ video layout
  Widget _video(bool hasLocalVideo) {
    final size = MediaQuery.of(context).size;
    final pad = MediaQuery.of(context).padding;
    final showRemote = s.remoteVideo && s.state == CallState.connected;
    final big = _swap && hasLocalVideo && showRemote
        ? RTCVideoView(s.localView, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
        : showRemote
            ? RTCVideoView(s.remoteView, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            : hasLocalVideo
                ? RTCVideoView(s.localView, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : Center(child: Avatar(initials: Messenger.initialsOf(s.peerName), colorIndex: s.peerId.length % 7, photo: Messenger.instance.photoOf(s.peerId), size: 120));
    final small = showRemote && hasLocalVideo
        ? (_swap
            ? RTCVideoView(s.remoteView, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            : RTCVideoView(s.localView, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
        : null;
    const w = 112.0, h = 160.0;
    final pos = _selfPos ?? Offset(size.width - w - 14, pad.top + 76);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _controls = !_controls),
      child: Stack(children: [
        Positioned.fill(child: ColoredBox(color: const Color(0xFF22252A), child: big)),
        if (small != null)
          Positioned(
            left: pos.dx,
            top: pos.dy,
            width: w,
            height: h,
            child: GestureDetector(
              onTap: () => setState(() => _swap = !_swap),
              onPanUpdate: (d) => setState(() {
                final n = pos + d.delta;
                _selfPos = Offset(n.dx.clamp(8, size.width - w - 8), n.dy.clamp(pad.top + 8, size.height - h - 120));
              }),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(14)),
                  child: small,
                ),
              ),
            ),
          ),
        AnimatedOpacity(
          opacity: _controls ? 1 : 0,
          duration: Mitti.fast,
          child: IgnorePointer(
            ignoring: !_controls,
            child: Stack(children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(top: pad.top + 6, bottom: 18),
                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent])),
                  child: Column(children: [
                    _topBar(overVideo: true),
                    if (hasLocalVideo)
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(tooltip: 'Flip camera', icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white), onPressed: cs.switchCamera),
                      ),
                  ]),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: pad.bottom + 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(40)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _round(Icons.more_horiz_rounded, null, _more, size: 50),
                    _round(Icons.volume_up_rounded, null, () => cs.speaker(s, !s.speaker), on: s.speaker, size: 50),
                    _round(s.cameraOff || !hasLocalVideo ? Icons.videocam_off_rounded : Icons.videocam_rounded, null, cs.toggleVideo, on: s.cameraOff || !hasLocalVideo, size: 50),
                    _round(s.muted ? Icons.mic_off_rounded : Icons.mic_rounded, null, cs.toggleMute, on: s.muted, size: 50),
                    _round(Icons.call_end_rounded, null, () => cs.hangUp(reason: 'Call ended'), bg: Mitti.error, size: 50),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Green bar at the top of the app while a minimised call is going on.
class ActiveCallBar extends StatelessWidget {
  const ActiveCallBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallSession?>(
      valueListenable: CallService.instance.active,
      builder: (context, s, _) {
        if (s == null) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            if (!s.minimised || s.state == CallState.ended) return const SizedBox.shrink();
            final top = MediaQuery.of(context).padding.top;
            return Material(
              color: Mitti.callGreen,
              child: InkWell(
                onTap: CallService.instance.restore,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, top + 6, 16, 8),
                  child: Row(children: [
                    Icon(s.video ? Icons.videocam_rounded : Icons.call_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${s.peerName} · ${s.stateText}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
                    ),
                    const Text('Tap to return', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                  ]),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Puts [ActiveCallBar] above the whole app while a call is minimised.
/// The tree shape never changes, so the app's navigator keeps its state.
class CallBarHost extends StatelessWidget {
  final Widget child;
  const CallBarHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallSession?>(
      valueListenable: CallService.instance.active,
      builder: (context, s, _) => ListenableBuilder(
        listenable: s ?? CallService.instance.active,
        builder: (context, _) {
          final show = s != null && s.minimised && s.state != CallState.ended;
          return Column(children: [
            if (show) const ActiveCallBar() else const SizedBox.shrink(),
            Expanded(child: MediaQuery.removePadding(context: context, removeTop: show, child: child)),
          ]);
        },
      ),
    );
  }
}
