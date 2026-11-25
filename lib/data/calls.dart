import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../nav.dart';
import '../screens/call/call_screen.dart';
import 'api.dart';
import 'group_calls.dart';
import 'app_state.dart';
import 'messenger.dart';
import 'models.dart';
import 'notifier.dart';

enum CallState { calling, ringing, incoming, connecting, connected, ended }

/// One voice/video call. Media goes phone-to-phone (WebRTC, DTLS-SRTP).
class CallSession extends ChangeNotifier {
  final String id;
  final String peerId;
  final String peerName;
  final bool outgoing;
  bool video;
  CallState state;
  String endReason = '';
  String? remoteOffer;

  RTCPeerConnection? pc;
  MediaStream? local;
  final localView = RTCVideoRenderer();
  final remoteView = RTCVideoRenderer();
  bool muted = false;
  bool speaker = false;
  bool cameraOff = false;
  bool remoteVideo = false;
  DateTime? connectedAt;
  Timer? _ringTimer, _tick;
  bool screenOpen = false;
  final DateTime started = DateTime.now();
  /// Minimised to a bar (call keeps going while you use the app).
  bool minimised = false;

  CallSession({required this.id, required this.peerId, required this.peerName, required this.outgoing, required this.video, required this.state});

  String get stateText => switch (state) {
        CallState.calling => 'Calling…',
        CallState.ringing => 'Ringing…',
        CallState.incoming => video ? 'Incoming video call' : 'Incoming voice call',
        CallState.connecting => 'Connecting…',
        CallState.connected => _dur(),
        CallState.ended => endReason.isEmpty ? 'Call ended' : endReason,
      };

  String _dur() {
    final s = connectedAt == null ? 0 : DateTime.now().difference(connectedAt!).inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void changed() => notifyListeners();
}

class CallService {
  CallService._();
  static final CallService instance = CallService._();

  CallSession? _current;
  CallSession? get current => _current;
  set current(CallSession? s) {
    _current = s;
    active.value = s;
  }

  /// The call in progress (for the "tap to return to call" bar).
  final active = ValueNotifier<CallSession?>(null);
  final _rnd = Random.secure();

  String _newId() => base64Url.encode(List<int>.generate(12, (_) => _rnd.nextInt(256))).replaceAll('=', '');

  Future<List<dynamic>> _ice() async {
    try {
      final d = await Api.instance.request('GET', '/v1/calls/ice');
      return d['iceServers'] as List? ?? [];
    } catch (_) {
      return [
        {'urls': ['stun:stun.l.google.com:19302']}
      ];
    }
  }

  Future<void> _setupMedia(CallSession s) async {
    await s.localView.initialize();
    await s.remoteView.initialize();
    s.local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': s.video ? {'facingMode': 'user', 'width': 640, 'height': 480} : false,
    });
    s.localView.srcObject = s.local;
    s.pc = await createPeerConnection({'iceServers': await _ice(), 'sdpSemantics': 'unified-plan'});
    for (final t in s.local!.getTracks()) {
      await s.pc!.addTrack(t, s.local!);
    }
    s.pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        s.remoteView.srcObject = e.streams.first;
        if (e.track.kind == 'video') s.remoteVideo = true;
        s.changed();
      }
    };
    s.pc!.onConnectionState = (st) {
      if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected && s.state != CallState.connected) {
        s.state = CallState.connected;
        s.connectedAt = DateTime.now();
        s._tick?.cancel();
        s._tick = Timer.periodic(const Duration(seconds: 1), (_) => s.changed());
        s.changed();
      } else if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(hangUp(reason: "Couldn't connect"));
      }
    };
    speaker(s, s.video);
  }

  /// Waits for ICE candidates so one offer/answer is enough (no trickle).
  Future<String> _gathered(RTCPeerConnection pc) async {
    final done = Completer<void>();
    pc.onIceGatheringState = (st) {
      if (st == RTCIceGatheringState.RTCIceGatheringStateComplete && !done.isCompleted) done.complete();
    };
    await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    final d = await pc.getLocalDescription();
    return jsonEncode({'sdp': d!.sdp, 'type': d.type});
  }

  Future<void> _signal(CallSession s, String action, [String? data]) async {
    try {
      await Api.instance.request('POST', '/v1/calls/${s.id}/signal', {'action': action, if (data != null) 'data': data});
    } catch (_) {}
  }

  // ------------------------------------------------------------------ outgoing
  Future<void> start(Chat chat, {required bool video}) async {
    final peer = chat.peerId;
    if (peer == null || current != null || GroupCallService.instance.current != null) return;
    final s = CallSession(id: _newId(), peerId: peer, peerName: chat.name, outgoing: true, video: video, state: CallState.calling);
    current = s;
    _open(s);
    try {
      await _setupMedia(s);
      final offer = await s.pc!.createOffer();
      await s.pc!.setLocalDescription(offer);
      final sdp = await _gathered(s.pc!);
      if (current != s) return;
      await Api.instance.request('POST', '/v1/calls', {'to': peer, 'callId': s.id, 'video': video, 'offer': sdp});
      s._ringTimer = Timer(const Duration(seconds: 45), () {
        if (s.state == CallState.calling || s.state == CallState.ringing) unawaited(hangUp(reason: 'No answer'));
      });
    } catch (e) {
      await hangUp(reason: e is ApiException ? e.message : "Couldn't start the call", silent: true);
    }
  }

  // ------------------------------------------------------------------ incoming
  /// Live events from the server (via the messenger socket).
  void onEvent(Map<String, dynamic> ev) {
    final action = ev['action'] as String?;
    final callId = ev['callId'] as String?;
    if (action == 'offer') {
      if (current != null || GroupCallService.instance.current != null) {
        unawaited(Api.instance.request('POST', '/v1/calls/$callId/signal', {'action': 'busy'}).then((_) {}, onError: (_) {}));
        return;
      }
      _incoming(callId!, ev['from'] as String, ev['video'] == true, ev['offer'] as String);
      return;
    }
    final s = current;
    if (s == null || s.id != callId) return;
    switch (action) {
      case 'ringing':
        if (s.state == CallState.calling) s.state = CallState.ringing;
        s.changed();
      case 'answer':
        s._ringTimer?.cancel();
        s.state = CallState.connecting;
        s.changed();
        final d = jsonDecode(ev['data'] as String) as Map<String, dynamic>;
        unawaited(s.pc?.setRemoteDescription(RTCSessionDescription(d['sdp'] as String, d['type'] as String)));
      case 'reoffer':
        unawaited(_onReoffer(s, ev['data'] as String));
      case 'reanswer':
        final d = jsonDecode(ev['data'] as String) as Map<String, dynamic>;
        unawaited(s.pc?.setRemoteDescription(RTCSessionDescription(d['sdp'] as String, d['type'] as String)));
      case 'cam':
        s.remoteVideo = ev['data'] == 'on';
        if (s.remoteVideo) s.video = true;
        s.changed();
      case 'reject':
        unawaited(hangUp(reason: 'Declined', remote: true));
      case 'busy':
        unawaited(hangUp(reason: 'On another call', remote: true));
      case 'end':
        unawaited(hangUp(reason: s.state == CallState.incoming ? 'Missed call' : 'Call ended', remote: true));
    }
  }

  /// Opened from the incoming-call notification.
  Future<void> openIncoming(String callId) async {
    if (callId.startsWith('grp-')) return GroupCallService.instance.openIncoming(callId);
    if (current != null) return;
    try {
      final d = await Api.instance.request('GET', '/v1/calls/$callId');
      final c = (d['call'] as Map).cast<String, dynamic>();
      if (c['status'] != 'ringing' || c['offer'] == null) return;
      _incoming(callId, c['caller'] as String, c['video'] == true, c['offer'] as String);
    } catch (_) {}
  }

  void _incoming(String id, String from, bool video, String offer) {
    final name = Messenger.instance.nameFor(from);
    final s = CallSession(id: id, peerId: from, peerName: name, outgoing: false, video: video, state: CallState.incoming)..remoteOffer = offer;
    current = s;
    unawaited(_signal(s, 'ringing'));
    unawaited(Notifier.instance.ring(id, name, video));
    s._ringTimer = Timer(const Duration(seconds: 45), () {
      if (s.state == CallState.incoming) unawaited(hangUp(reason: 'Missed call', silent: true));
    });
    _open(s);
  }

  Future<void> accept() async {
    final s = current;
    if (s == null || s.state != CallState.incoming) return;
    _stopRing();
    s._ringTimer?.cancel();
    s.state = CallState.connecting;
    s.changed();
    try {
      await _setupMedia(s);
      final o = jsonDecode(s.remoteOffer!) as Map<String, dynamic>;
      await s.pc!.setRemoteDescription(RTCSessionDescription(o['sdp'] as String, o['type'] as String));
      final answer = await s.pc!.createAnswer();
      await s.pc!.setLocalDescription(answer);
      await _signal(s, 'answer', await _gathered(s.pc!));
    } catch (_) {
      await hangUp(reason: "Couldn't connect");
    }
  }

  Future<void> decline() async {
    final s = current;
    if (s == null) return;
    await _signal(s, 'reject');
    await hangUp(reason: 'Declined', remote: true);
  }

  // ------------------------------------------------------------------ controls
  void toggleMute() {
    final s = current;
    if (s == null) return;
    s.muted = !s.muted;
    for (final t in s.local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !s.muted;
    }
    s.changed();
  }

  void speaker(CallSession s, bool on) {
    s.speaker = on;
    try {
      Helper.setSpeakerphoneOn(on);
    } catch (_) {}
    s.changed();
  }

  void toggleCamera() => unawaited(toggleVideo());

  /// Video button: turn my camera on (adds video to a voice call) or off.
  Future<void> toggleVideo() async {
    final s = current;
    if (s == null || s.pc == null || s.local == null) return;
    final tracks = s.local!.getVideoTracks();
    if (tracks.isNotEmpty) {
      s.cameraOff = !s.cameraOff;
      for (final t in tracks) {
        t.enabled = !s.cameraOff;
      }
      s.changed();
      unawaited(_signal(s, 'cam', s.cameraOff ? 'off' : 'on'));
      return;
    }
    try {
      final cam = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'facingMode': 'user', 'width': 640, 'height': 480},
      });
      final t = cam.getVideoTracks().first;
      await s.local!.addTrack(t);
      await s.pc!.addTrack(t, s.local!);
      s.localView.srcObject = s.local;
      s.video = true;
      s.cameraOff = false;
      if (!s.speaker) speaker(s, true);
      s.changed();
      final offer = await s.pc!.createOffer();
      await s.pc!.setLocalDescription(offer);
      await _signal(s, 'reoffer', await _gathered(s.pc!));
      unawaited(_signal(s, 'cam', 'on'));
    } catch (_) {}
  }

  Future<void> _onReoffer(CallSession s, String data) async {
    try {
      final o = jsonDecode(data) as Map<String, dynamic>;
      await s.pc!.setRemoteDescription(RTCSessionDescription(o['sdp'] as String, o['type'] as String));
      final answer = await s.pc!.createAnswer();
      await s.pc!.setLocalDescription(answer);
      await _signal(s, 'reanswer', await _gathered(s.pc!));
    } catch (_) {}
  }

  /// Minimise: keep talking while using the rest of the app.
  void minimise() {
    final s = current;
    if (s == null || !s.screenOpen) return;
    s.screenOpen = false;
    s.minimised = true;
    navigatorKey.currentState?.pop();
    s.changed();
  }

  void restore() {
    final s = current;
    if (s == null || s.screenOpen) return;
    s.minimised = false;
    _open(s);
  }

  Future<void> switchCamera() async {
    final t = current?.local?.getVideoTracks();
    if (t == null || t.isEmpty) return;
    try {
      await Helper.switchCamera(t.first);
    } catch (_) {}
  }

  void _stopRing() {
    unawaited(Notifier.instance.stopRing());
  }

  /// Ends the call (tells the other side unless they ended it).
  Future<void> hangUp({String reason = '', bool remote = false, bool silent = false}) async {
    final s = current;
    if (s == null || s.state == CallState.ended) return;
    final wasConnected = s.state == CallState.connected;
    final wasIncoming = s.state == CallState.incoming;
    final dur = s.connectedAt == null ? 0 : DateTime.now().difference(s.connectedAt!).inSeconds;
    s.state = CallState.ended;
    s.endReason = reason;
    s.changed();
    _stopRing();
    s._ringTimer?.cancel();
    s._tick?.cancel();
    if (!remote) unawaited(_signal(s, 'end'));
    try {
      for (final t in s.local?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await s.local?.dispose();
      await s.pc?.close();
      s.localView.srcObject = null;
      s.remoteView.srcObject = null;
    } catch (_) {}
    try {
      Helper.setSpeakerphoneOn(false);
    } catch (_) {}
    final missedIn = !s.outgoing && !wasConnected && (wasIncoming || reason == 'Missed call') && reason != 'Declined';
    _log(s, missed: missedIn, seconds: dur);
    unawaited(Messenger.instance.addCallRecord(s.peerId, s.id,
        video: s.video, outgoing: s.outgoing, missed: s.outgoing ? !wasConnected : (missedIn || !wasConnected), seconds: dur, at: s.started));
    if (missedIn) unawaited(Notifier.instance.showMissedCall(s.id, s.peerId, s.peerName, s.video));
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (current == s) current = null;
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop() && s.screenOpen) nav.pop();
    s.screenOpen = false;
    try {
      await s.localView.dispose();
      await s.remoteView.dispose();
    } catch (_) {}
    if (silent && reason.isNotEmpty && navigatorKey.currentContext != null) {
      ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(SnackBar(content: Text(reason)));
    }
  }

  void _open(CallSession s) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    s.screenOpen = true;
    nav.push(MaterialPageRoute(builder: (_) => CallScreen(session: s)));
  }

  // ------------------------------------------------------------------ call log
  Future<void> loadLog() async {
    final uid = Api.instance.userId;
    if (uid == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      final list = [for (final e in (p.getStringList('calls_$uid') ?? const <String>[])) CallLog.fromJson(jsonDecode(e) as Map<String, dynamic>)];
      final s = AppState.instance;
      s.calls
        ..clear()
        ..addAll(list);
      s.changed();
    } catch (_) {}
  }

  static String _whenText(DateTime at, bool missed, int seconds) {
    final now = DateTime.now();
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final time = '$h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final d = day == today ? 'Today' : (day == today.subtract(const Duration(days: 1)) ? 'Yesterday' : '${at.day} ${months[at.month - 1]}');
    final dur = seconds > 0 ? ' · ${seconds ~/ 60 > 0 ? '${seconds ~/ 60} min' : '$seconds sec'}' : '';
    return '${missed ? 'Missed · ' : ''}$d, $time$dur';
  }

  void _log(CallSession c, {required bool missed, required int seconds}) =>
      _addLog(c.peerId, c.peerName, c.id, video: c.video, outgoing: c.outgoing, missed: missed, seconds: seconds, at: c.started);

  void _addLog(String peerId, String name, String callId,
      {required bool video, required bool outgoing, required bool missed, required int seconds, required DateTime at}) {
    final s = AppState.instance;
    if (s.calls.any((e) => e.callId == callId)) return;
    final entry = CallLog(
      name,
      Messenger.initialsOf(name),
      peerId.codeUnits.fold<int>(0, (a, b) => a + b) % 7,
      missed ? CallKind.missed : (outgoing ? CallKind.outgoing : CallKind.incoming),
      video,
      _whenText(at, missed, seconds),
      peerId: peerId,
      at: at,
      callId: callId,
    );
    var i = 0;
    while (i < s.calls.length && (s.calls[i].at ?? DateTime(2000)).isAfter(at)) {
      i++;
    }
    s.calls.insert(i, entry);
    s.changed();
    final uid = Api.instance.userId;
    if (uid == null) return;
    unawaited(SharedPreferences.getInstance().then((p) => p.setStringList('calls_$uid', [for (final e in s.calls.take(100)) jsonEncode(e.toJson())])));
  }

  /// Calls that happened while this phone was off / app closed: fill the call log,
  /// chat history and show missed-call notifications.
  bool _syncing = false;
  Future<void> syncRecent() async {
    final uid = Api.instance.userId;
    if (uid == null || _syncing) return;
    _syncing = true;
    try {
      final p = await SharedPreferences.getInstance();
      final key = 'calls_sync_$uid';
      final last = p.getInt(key) ?? DateTime.now().subtract(const Duration(minutes: 10)).millisecondsSinceEpoch;
      final d = await Api.instance.request('GET', '/v1/calls/recent?since=${last - 120000}');
      var newest = last;
      for (final raw in (d['calls'] as List? ?? []).reversed) {
        final c = (raw as Map).cast<String, dynamic>();
        final id = c['id'] as String;
        if (current?.id == id) continue;
        final created = (c['created_at'] as num).toInt();
        if (created > newest) newest = created;
        final outgoing = c['caller'] == uid;
        final peer = (outgoing ? c['callee'] : c['caller']) as String;
        final status = c['status'] as String? ?? '';
        final video = c['video'] == true;
        final ans = (c['answered_at'] as num?)?.toInt();
        final end = (c['ended_at'] as num?)?.toInt();
        final seconds = status == 'ended' && ans != null && end != null ? ((end - ans) ~/ 1000) : 0;
        final missed = status != 'ended';
        final at = DateTime.fromMillisecondsSinceEpoch(created);
        final name = Messenger.instance.nameFor(peer);
        final alreadyLogged = AppState.instance.calls.any((e) => e.callId == id);
        _addLog(peer, name, id, video: video, outgoing: outgoing, missed: !outgoing && status == 'missed', seconds: seconds, at: at);
        await Messenger.instance.addCallRecord(peer, id, video: video, outgoing: outgoing, missed: missed, seconds: seconds, at: at);
        if (!alreadyLogged && !outgoing && status == 'missed') {
          await Notifier.instance.showMissedCall(id, peer, name, video);
        }
      }
      await p.setInt(key, newest);
    } catch (_) {
    } finally {
      _syncing = false;
    }
  }
}
