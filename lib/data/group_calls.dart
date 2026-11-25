import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../nav.dart';
import '../screens/call/group_call_screen.dart';
import 'api.dart';
import 'app_state.dart';
import 'calls.dart';
import 'messenger.dart';
import 'models.dart';
import 'notifier.dart';

enum GroupCallState { incoming, joining, waiting, live, ended }

/// One person on the other end of a group call.
class GroupPeer {
  final String id;
  RTCPeerConnection? pc;
  final view = RTCVideoRenderer();
  bool viewReady = false;
  bool hasVideo = false;
  bool connected = false;
  GroupPeer(this.id);
}

/// A group voice/video call. Every phone talks to every other phone directly
/// (WebRTC, DTLS-SRTP encrypted end to end), the server only passes signals.
class GroupCallSession extends ChangeNotifier {
  final String id;
  final String groupId;
  final String groupName;
  final bool outgoing;
  bool video;
  GroupCallState state;
  String endReason = '';
  String? ringFrom;

  MediaStream? local;
  final localView = RTCVideoRenderer();
  final peers = <String, GroupPeer>{};
  bool muted = false, speaker = false, cameraOff = false;
  DateTime? liveAt;
  bool everLive = false;
  Timer? _ringTimer, _tick;
  bool screenOpen = false;

  GroupCallSession({required this.id, required this.groupId, required this.groupName, required this.outgoing, required this.video, required this.state});

  String get stateText => switch (state) {
        GroupCallState.incoming => video ? 'Incoming group video call' : 'Incoming group voice call',
        GroupCallState.joining => 'Connecting…',
        GroupCallState.waiting => 'Ringing…',
        GroupCallState.live => _dur(),
        GroupCallState.ended => endReason.isEmpty ? 'Call ended' : endReason,
      };

  String _dur() {
    final s = liveAt == null ? 0 : DateTime.now().difference(liveAt!).inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void changed() => notifyListeners();
}

class GroupCallService {
  GroupCallService._();
  static final instance = GroupCallService._();

  GroupCallSession? current;
  final _rnd = Random.secure();
  List<dynamic>? _iceCache;

  bool get busy => current != null || CallService.instance.current != null;

  String _newId() => 'grp-${base64Url.encode(List<int>.generate(12, (_) => _rnd.nextInt(256))).replaceAll('=', '')}';

  Future<List<dynamic>> _ice() async {
    if (_iceCache != null) return _iceCache!;
    try {
      final d = await Api.instance.request('GET', '/v1/calls/ice');
      return _iceCache = d['iceServers'] as List? ?? [];
    } catch (_) {
      return [
        {'urls': ['stun:stun.l.google.com:19302']}
      ];
    }
  }

  // ------------------------------------------------------------------ start / join
  Future<void> start(Chat chat, {required bool video}) async {
    final gid = chat.groupId;
    if (gid == null || busy) return;
    final s = GroupCallSession(id: _newId(), groupId: gid, groupName: chat.name, outgoing: true, video: video, state: GroupCallState.joining);
    current = s;
    _open(s);
    try {
      final d = await Api.instance.request('POST', '/v1/gcalls', {'groupId': gid, 'callId': s.id, 'video': video});
      if (current != s) return;
      if (d['existing'] == true) {
        // A call is already running in this group: join that one instead.
        final joined = GroupCallSession(id: d['callId'] as String, groupId: gid, groupName: chat.name, outgoing: false, video: d['video'] == true, state: GroupCallState.joining)
          ..screenOpen = true;
        current = joined;
        s.screenOpen = false;
        _replaceScreen(joined);
        await _join(joined);
      } else {
        await _join(s);
      }
    } catch (e) {
      await leave(reason: e is ApiException ? e.message : "Couldn't start the call", toast: true);
    }
  }

  /// "Add person" on a 1:1 call: turns it into a small call with the chosen people.
  /// [upgrade] is the 1:1 call being replaced; that person's phone joins by itself.
  Future<void> startAdhoc({required List<String> people, required String name, required bool video, String? upgrade, String? upgradePeer}) async {
    final id = _newId();
    try {
      await Api.instance.request('POST', '/v1/gcalls/adhoc', {
        'people': people,
        'callId': id,
        'video': video,
        if (upgrade != null) 'upgrade': upgrade,
        if (upgradePeer != null) 'upgradePeer': upgradePeer,
      });
    } catch (e) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : "Couldn't add people")));
      return;
    }
    if (upgrade != null) await CallService.instance.hangUp(reason: '', silent: true);
    final s = GroupCallSession(id: id, groupId: 'adhoc:$id', groupName: name, outgoing: true, video: video, state: GroupCallState.joining);
    current = s;
    _open(s);
    try {
      await _join(s);
    } catch (e) {
      await leave(reason: e is ApiException ? e.message : "Couldn't start the call", toast: true);
    }
  }

  Future<void> _join(GroupCallSession s) async {
    await s.localView.initialize();
    s.local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': s.video ? {'facingMode': 'user', 'width': 480, 'height': 360} : false,
    });
    s.localView.srcObject = s.local;
    _setSpeaker(s, s.video);
    final d = await Api.instance.request('POST', '/v1/gcalls/${s.id}/join');
    if (current != s) return;
    final people = [for (final p in (d['people'] as List? ?? [])) p as String];
    if (people.isEmpty) {
      s.state = GroupCallState.waiting;
      s._ringTimer = Timer(const Duration(seconds: 50), () {
        if (s.state == GroupCallState.waiting && s.peers.isEmpty) unawaited(leave(reason: 'No answer'));
      });
    } else {
      s.state = GroupCallState.live;
      _goLive(s);
    }
    s.changed();
    // The newcomer calls everyone already in the call (so offers never clash).
    for (final u in people) {
      unawaited(_offerTo(s, u));
    }
  }

  void _goLive(GroupCallSession s) {
    s._ringTimer?.cancel();
    if (s.liveAt == null) {
      s.liveAt = DateTime.now();
      s.everLive = true;
      s._tick?.cancel();
      s._tick = Timer.periodic(const Duration(seconds: 1), (_) => s.changed());
    }
    s.state = GroupCallState.live;
  }

  Future<GroupPeer> _peer(GroupCallSession s, String u) async {
    final existing = s.peers[u];
    if (existing != null && existing.pc != null) {
      try {
        await existing.pc!.close();
      } catch (_) {}
    }
    final p = existing ?? GroupPeer(u);
    s.peers[u] = p;
    if (!p.viewReady) {
      await p.view.initialize();
      p.viewReady = true;
    }
    final pc = await createPeerConnection({'iceServers': await _ice(), 'sdpSemantics': 'unified-plan'});
    p.pc = pc;
    for (final t in s.local?.getTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(t, s.local!);
    }
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        p.view.srcObject = e.streams.first;
        if (e.track.kind == 'video') p.hasVideo = true;
        s.changed();
      }
    };
    pc.onConnectionState = (st) {
      if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        p.connected = true;
        _goLive(s);
        s.changed();
      } else if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed || st == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        p.connected = false;
        s.changed();
      }
    };
    s.changed();
    return p;
  }

  Future<String> _gathered(RTCPeerConnection pc) async {
    final done = Completer<void>();
    pc.onIceGatheringState = (st) {
      if (st == RTCIceGatheringState.RTCIceGatheringStateComplete && !done.isCompleted) done.complete();
    };
    await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    final d = await pc.getLocalDescription();
    return jsonEncode({'sdp': d!.sdp, 'type': d.type});
  }

  Future<void> _signal(GroupCallSession s, String to, String kind, String data) async {
    try {
      await Api.instance.request('POST', '/v1/gcalls/${s.id}/signal', {'to': to, 'kind': kind, 'data': data});
    } catch (_) {}
  }

  Future<void> _offerTo(GroupCallSession s, String u) async {
    try {
      final p = await _peer(s, u);
      final offer = await p.pc!.createOffer();
      await p.pc!.setLocalDescription(offer);
      final sdp = await _gathered(p.pc!);
      if (current != s) return;
      await _signal(s, u, 'offer', sdp);
    } catch (_) {}
  }

  // ------------------------------------------------------------------ events
  void onEvent(Map<String, dynamic> ev) {
    final action = ev['action'] as String?;
    final callId = ev['callId'] as String?;
    final from = ev['from'] as String? ?? '';
    if (action == 'ring') {
      final gid = ev['groupId'] as String? ?? '';
      final chat = Messenger.instance.chatById(gid);
      final name = chat?.name ?? (gid.startsWith('adhoc:') ? '${ev['name'] ?? Messenger.instance.nameFor(from)} + others' : 'Group call');
      final upgrade = ev['upgrade'] as String? ?? '';
      final one = CallService.instance.current;
      if (upgrade.isNotEmpty && one != null && one.id == upgrade && current == null) {
        // The person I'm talking to added someone: move into the new call without ringing.
        unawaited(() async {
          await CallService.instance.hangUp(reason: '', remote: true, silent: true);
          _incoming(callId!, gid, name, ev['video'] == true, from, quiet: true);
          await accept();
        }());
        return;
      }
      if (busy) return;
      _incoming(callId!, gid, name, ev['video'] == true, from);
      return;
    }
    final s = current;
    if (s == null || s.id != callId) return;
    switch (action) {
      case 'joined':
        s.peers.putIfAbsent(from, () => GroupPeer(from));
        s.changed();
      case 'offer':
        unawaited(_answer(s, from, ev['data'] as String));
      case 'answer':
        final d = jsonDecode(ev['data'] as String) as Map<String, dynamic>;
        unawaited(s.peers[from]?.pc?.setRemoteDescription(RTCSessionDescription(d['sdp'] as String, d['type'] as String)));
      case 'left':
        unawaited(_drop(s, from));
      case 'ended':
        if (s.state == GroupCallState.incoming) {
          unawaited(leave(reason: 'Missed group call', remote: true));
        } else {
          unawaited(leave(reason: 'Call ended', remote: true));
        }
    }
  }

  Future<void> _answer(GroupCallSession s, String from, String data) async {
    if (s.state == GroupCallState.incoming || s.state == GroupCallState.ended) return;
    try {
      final p = await _peer(s, from);
      final o = jsonDecode(data) as Map<String, dynamic>;
      await p.pc!.setRemoteDescription(RTCSessionDescription(o['sdp'] as String, o['type'] as String));
      final ans = await p.pc!.createAnswer();
      await p.pc!.setLocalDescription(ans);
      await _signal(s, from, 'answer', await _gathered(p.pc!));
    } catch (_) {}
  }

  Future<void> _drop(GroupCallSession s, String u) async {
    final p = s.peers.remove(u);
    s.changed();
    try {
      await p?.pc?.close();
      p?.view.srcObject = null;
      if (p?.viewReady == true) await p!.view.dispose();
    } catch (_) {}
    if (s.peers.isEmpty && s.everLive) unawaited(leave(reason: 'Everyone left'));
  }

  /// Opened from the incoming-call notification.
  Future<void> openIncoming(String callId) async {
    if (busy) return;
    try {
      final d = await Api.instance.request('GET', '/v1/gcalls/$callId');
      final c = (d['call'] as Map).cast<String, dynamic>();
      if (c['ended'] == true || (c['people'] as List? ?? []).isEmpty) return;
      final gid = c['groupId'] as String;
      final chat = Messenger.instance.chatById(gid);
      _incoming(callId, gid, chat?.name ?? 'Group call', c['video'] == true, c['creator'] as String?);
    } catch (_) {}
  }

  void _incoming(String id, String gid, String name, bool video, String? from, {bool quiet = false}) {
    final s = GroupCallSession(id: id, groupId: gid, groupName: name, outgoing: false, video: video, state: GroupCallState.incoming)..ringFrom = from;
    current = s;
    if (!quiet) unawaited(Notifier.instance.ring(id, name, video));
    s._ringTimer = Timer(const Duration(seconds: 45), () {
      if (s.state == GroupCallState.incoming) unawaited(leave(reason: 'Missed group call', remote: true));
    });
    _open(s);
  }

  Future<void> accept() async {
    final s = current;
    if (s == null || s.state != GroupCallState.incoming) return;
    unawaited(Notifier.instance.stopRing());
    s._ringTimer?.cancel();
    s.state = GroupCallState.joining;
    s.changed();
    try {
      await _join(s);
    } catch (e) {
      await leave(reason: e is ApiException ? e.message : "Couldn't join the call");
    }
  }

  Future<void> decline() => leave(reason: 'Declined', remote: true);

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

  void toggleSpeaker() {
    final s = current;
    if (s != null) _setSpeaker(s, !s.speaker);
  }

  void _setSpeaker(GroupCallSession s, bool on) {
    s.speaker = on;
    try {
      Helper.setSpeakerphoneOn(on);
    } catch (_) {}
    s.changed();
  }

  void toggleCamera() {
    final s = current;
    if (s == null) return;
    s.cameraOff = !s.cameraOff;
    for (final t in s.local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !s.cameraOff;
    }
    s.changed();
  }

  Future<void> switchCamera() async {
    final t = current?.local?.getVideoTracks();
    if (t == null || t.isEmpty) return;
    try {
      await Helper.switchCamera(t.first);
    } catch (_) {}
  }

  /// Leaves the call (the call goes on for the others).
  /// [remote]: we never joined (declined / missed), so there is nothing to tell the server.
  Future<void> leave({String reason = '', bool remote = false, bool toast = false}) async {
    final s = current;
    if (s == null || s.state == GroupCallState.ended) return;
    final wasIncoming = s.state == GroupCallState.incoming;
    final dur = s.liveAt == null ? 0 : DateTime.now().difference(s.liveAt!).inSeconds;
    s.state = GroupCallState.ended;
    s.endReason = reason;
    s.changed();
    unawaited(Notifier.instance.stopRing());
    s._ringTimer?.cancel();
    s._tick?.cancel();
    if (!remote) {
      unawaited(Api.instance.request('POST', '/v1/gcalls/${s.id}/leave').then((_) {}, onError: (_) {}));
    }
    try {
      for (final t in s.local?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await s.local?.dispose();
      for (final p in s.peers.values) {
        await p.pc?.close();
        p.view.srcObject = null;
      }
      s.localView.srcObject = null;
    } catch (_) {}
    try {
      Helper.setSpeakerphoneOn(false);
    } catch (_) {}
    _log(s, missed: wasIncoming && reason != 'Declined', seconds: dur);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (current == s) current = null;
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop() && s.screenOpen) nav.pop();
    s.screenOpen = false;
    try {
      await s.localView.dispose();
      for (final p in s.peers.values) {
        if (p.viewReady) await p.view.dispose();
      }
    } catch (_) {}
    if (toast && reason.isNotEmpty && navigatorKey.currentContext != null) {
      ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(SnackBar(content: Text(reason)));
    }
  }

  void _open(GroupCallSession s) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    s.screenOpen = true;
    nav.push(MaterialPageRoute(builder: (_) => GroupCallScreen(session: s)));
  }

  void _replaceScreen(GroupCallSession s) {
    navigatorKey.currentState?.pushReplacement(MaterialPageRoute(builder: (_) => GroupCallScreen(session: s)));
  }

  void _log(GroupCallSession c, {required bool missed, required int seconds}) {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final time = '$h:${now.minute.toString().padLeft(2, '0')} ${now.hour < 12 ? 'AM' : 'PM'}';
    final dur = seconds > 0 ? ' · ${seconds ~/ 60 > 0 ? '${seconds ~/ 60} min' : '$seconds sec'}' : '';
    final entry = CallLog(
      c.groupName,
      Messenger.initialsOf(c.groupName),
      c.groupId.codeUnits.fold<int>(0, (a, b) => a + b) % 7,
      missed ? CallKind.missed : (c.outgoing ? CallKind.outgoing : CallKind.incoming),
      c.video,
      '${missed ? 'Missed · ' : ''}Group · Today, $time$dur',
      peerId: 'g:${c.groupId}',
      at: now,
    );
    final s = AppState.instance;
    s.calls.insert(0, entry);
    s.changed();
    final uid = Api.instance.userId;
    if (uid == null) return;
    unawaited(SharedPreferences.getInstance().then((p) => p.setStringList('calls_$uid', [for (final e in s.calls.take(100)) jsonEncode(e.toJson())])));
  }
}
