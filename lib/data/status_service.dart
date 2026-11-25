import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'app_state.dart';
import 'contacts.dart';
import 'e2e.dart';
import 'messenger.dart';
import 'models.dart';

/// Real status updates, end-to-end encrypted.
///
/// Each update is encrypted once with a random key. That key is then sealed
/// separately for every person allowed by Status privacy (and for me), so
/// the server stores only ciphertext and only those people can open it.
/// Updates disappear after 24 hours.
class StatusService {
  StatusService._();
  static final StatusService instance = StatusService._();

  AppState get _s => AppState.instance;
  bool _loading = false;
  Set<String> _seen = {};
  bool _seenLoaded = false;
  String? lastError;

  // ------------------------------------------------------------------ posting
  /// Who may see my status, from the phone book + Status privacy.
  Future<Map<String, String>> _audience() async {
    final r = await ContactBook.instance.load();
    if (!r.permission) {
      throw ApiException(-1, 'NO_CONTACTS', 'Allow contacts so your contacts can see your status.');
    }
    final withKey = {for (final c in r.onBaatly) if (c.key != null) c.userId: c.key!};
    final Set<String> allowed = switch (_s.statusAudience) {
      1 => withKey.keys.where((id) => !_s.statusExcept.contains(id)).toSet(),
      2 => withKey.keys.where(_s.statusOnly.contains).toSet(),
      3 => withKey.keys.where(_s.closeFriends.contains).toSet(),
      _ => withKey.keys.toSet(),
    };
    return {for (final id in allowed) id: withKey[id]!};
  }

  Future<Map<String, dynamic>> _payload(StatusSlide st) async {
    if (st.isPhoto) {
      final bytes = await File(st.imagePath!).readAsBytes();
      return {'type': 'photo', 'caption': st.caption ?? '', 'img': base64Encode(bytes)};
    }
    return {'type': 'text', 'text': st.text ?? '', 'bg': st.bg};
  }

  Future<void> post(StatusSlide st) async {
    st.uploading = true;
    st.failed = false;
    _s.changed();
    try {
      final me = Api.instance.userId!;
      final audience = await _audience();
      final payload = await _payload(st);
      if (st.audioPath != null && st.audio != null) {
        // The song goes to media storage (encrypted with its own key); the status carries the key.
        final (ak, ablob) = await E2E.instance.lock(await File(st.audioPath!).readAsBytes());
        final id = await Api.instance.upload(ablob);
        st.audio!['id'] = id;
        st.audio!['k'] = base64Encode(ak);
        payload['audio'] = {'id': id, 'k': base64Encode(ak), 'start': st.audio!['start'], 'dur': st.audio!['dur'], 'name': st.audio!['name']};
      }
      final (key, blob) = await E2E.instance.lock(utf8.encode(jsonEncode(payload)));
      final keys = <String, String>{};
      final k = {'k': base64Encode(key)};
      keys[me] = await E2E.instance.seal(k, E2E.instance.publicKey);
      for (final e in audience.entries) {
        keys[e.key] = await E2E.instance.seal(k, e.value);
      }
      final d = await Api.instance.request('POST', '/v1/status', {
        'body': base64Encode(blob),
        'keys': keys,
        'allowShare': _s.statusAllowSharing,
      });
      st.remoteId = d['id'] as String;
      lastError = null;
    } on ApiException catch (e) {
      st.failed = true;
      lastError = e.message;
    } catch (e) {
      st.failed = true;
      lastError = "Couldn't post your status. ($e)";
    } finally {
      st.uploading = false;
      _s.changed();
    }
  }

  Future<void> delete(StatusSlide st) async {
    final id = st.remoteId;
    if (id == null) return;
    try {
      await Api.instance.request('DELETE', '/v1/status/$id');
    } catch (_) {}
  }

  // ------------------------------------------------------------------ reading
  Future<File> _file(String id) async => File('${(await getTemporaryDirectory()).path}/status_$id.jpg');

  /// Downloads and decrypts one update.
  Future<StatusSlide?> _open(String id, String sealed, String ownerKey, DateTime at) async {
    try {
      final k = await E2E.instance.open(sealed, ownerKey);
      final key = base64Decode(k['k'] as String);
      final d = await Api.instance.request('GET', '/v1/status/$id/body');
      final clear = await E2E.instance.unlock(base64Decode(d['body'] as String), key);
      final p = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      final StatusSlide slide;
      if (p['type'] == 'photo') {
        final f = await _file(id);
        if (!await f.exists()) await f.writeAsBytes(base64Decode(p['img'] as String), flush: true);
        slide = StatusSlide.photo(f.path, caption: p['caption'] as String?, at: at, remoteId: id);
      } else {
        slide = StatusSlide.text(p['text'] as String? ?? '', (p['bg'] as int?) ?? 0xFFC8553D, at: at, remoteId: id);
      }
      slide.audio = (p['audio'] as Map?)?.cast<String, dynamic>();
      return slide;
    } catch (_) {
      return null; // expired, deleted, or not decryptable on this phone
    }
  }

  Future<void> _loadSeen() async {
    if (_seenLoaded) return;
    final p = await SharedPreferences.getInstance();
    _seen = (p.getStringList('status_seen') ?? []).toSet();
    _seenLoaded = true;
  }

  Future<void> _saveSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('status_seen', _seen.toList());
  }

  /// Fetches my updates and everyone else's.
  Future<void> refresh() async {
    if (_loading || !Messenger.instance.active) return;
    _loading = true;
    try {
      await _loadSeen();
      final me = Api.instance.userId!;
      // Mine
      final mine = await Api.instance.request('GET', '/v1/status/mine');
      final myKey = E2E.instance.publicKey;
      final keep = _s.myStatuses.where((x) => x.remoteId == null && (x.uploading || x.failed)).toList();
      final known = {for (final x in _s.myStatuses) if (x.remoteId != null) x.remoteId!: x};
      final myList = <StatusSlide>[];
      for (final r in (mine['statuses'] as List? ?? [])) {
        final m = r as Map<String, dynamic>;
        final id = m['id'] as String;
        final at = DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int);
        final st = known[id] ?? await _open(id, m['sealed'] as String, myKey, at);
        if (st == null) continue;
        final v = (m['views'] as int?) ?? 0;
        if (v > st.views) st.views = v;
        myList.add(st);
      }
      // Others
      final feed = await Api.instance.request('GET', '/v1/status/feed');
      final oldSlides = {for (final it in _s.statuses) for (final sl in it.slides) if (sl.remoteId != null) sl.remoteId!: sl};
      final byOwner = <String, List<StatusSlide>>{};
      final owners = <String, Map<String, dynamic>>{};
      for (final r in (feed['statuses'] as List? ?? [])) {
        final m = r as Map<String, dynamic>;
        final id = m['id'] as String;
        final owner = m['owner_id'] as String;
        final ownerKey = m['x25519'] as String?;
        if (owner == me || ownerKey == null) continue;
        final at = DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int);
        final st = oldSlides[id] ?? await _open(id, m['sealed'] as String, ownerKey, at);
        if (st == null) continue;
        st.seen = _seen.contains(id) || m['viewed'] == 1;
        byOwner.putIfAbsent(owner, () => []).add(st);
        owners[owner] = m;
      }
      final items = <StatusItem>[];
      byOwner.forEach((owner, slides) {
        slides.sort((a, b) => a.at.compareTo(b.at));
        final m = owners[owner]!;
        final name = Messenger.instance.nameFor(owner, phone: m['phone'] as String?, profileName: m['name'] as String?);
        items.add(StatusItem(
          name,
          Messenger.initialsOf(name),
          owner.codeUnits.fold<int>(0, (a, b) => a + b) % 7,
          _ago(slides.last.at),
          slides,
          seen: slides.every((x) => x.seen),
          ownerId: owner,
        ));
      });
      items.sort((a, b) => b.slides.last.at.compareTo(a.slides.last.at));
      _s.useRealStatuses(items, [...myList, ...keep]);
      for (final owner in byOwner.keys) {
        unawaited(Messenger.instance.ensurePeer(owner));
      }
      lastError = null;
    } on ApiException catch (e) {
      lastError = e.message;
    } catch (_) {
    } finally {
      _loading = false;
    }
  }

  /// Downloads + decrypts a status song (cached).
  Future<String?> audioFile(StatusSlide st) async {
    if (st.audioPath != null && File(st.audioPath!).existsSync()) return st.audioPath;
    final a = st.audio;
    if (a == null || a['id'] == null) return null;
    try {
      final f = File('${(await getTemporaryDirectory()).path}/status_audio_${a['id']}');
      if (!await f.exists()) {
        final blob = await Api.instance.download(a['id'] as String);
        await f.writeAsBytes(await E2E.instance.unlock(blob, base64Decode(a['k'] as String)), flush: true);
      }
      st.audioPath = f.path;
      return f.path;
    } catch (_) {
      return null;
    }
  }

  /// Marks an update as seen (tells the owner once).
  void viewed(StatusItem item, StatusSlide st) {
    final id = st.remoteId;
    if (id == null || st.seen) return;
    st.seen = true;
    _seen.add(id);
    unawaited(_saveSeen());
    unawaited(Api.instance.request('POST', '/v1/status/$id/view').catchError((_) => <String, dynamic>{}));
  }

  Timer? _soon;

  /// New status from someone (pushed live): refresh shortly.
  void refreshSoon() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 600), () => unawaited(refresh()));
  }

  /// Someone just viewed one of my updates (pushed live).
  void onView(String statusId, String viewer, int at) {
    for (final st in _s.myStatuses) {
      if (st.remoteId == statusId) {
        st.viewerAt[viewer] = at;
        _s.changed();
      }
    }
  }

  /// Loads who saw one of my updates into [StatusSlide.viewerAt].
  Future<void> loadViewers(StatusSlide st) async {
    final id = st.remoteId;
    if (id == null) return;
    try {
      final d = await Api.instance.request('GET', '/v1/status/$id/views');
      for (final v in (d['views'] as List? ?? [])) {
        final m = v as Map<String, dynamic>;
        st.viewerAt[m['viewer_id'] as String] = m['at'] as int;
      }
      if (st.viewerAt.length > st.views) st.views = st.viewerAt.length;
      _s.changed();
    } catch (_) {}
  }

  /// Viewers of an update, newest first, with display names.
  List<(String, String?, DateTime)> viewerList(StatusSlide st) {
    final l = st.viewerAt.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in l)
        (Messenger.instance.nameFor(e.key), Messenger.instance.photoOf(e.key), DateTime.fromMillisecondsSinceEpoch(e.value)),
    ];
  }

  /// Reply to someone's status = a normal (encrypted) chat message to them.
  void reply(StatusItem item, StatusSlide st, String text) {
    final owner = item.ownerId;
    if (owner == null) return;
    final chat = Messenger.instance.chatWithUser(owner, item.name, '', null);
    final what = st.isPhoto ? '📷 ${(st.caption ?? '').isEmpty ? 'Photo' : st.caption}' : (st.text ?? '');
    Messenger.instance.send(chat, '↪ Status: ${what.split('\n').first}\n$text');
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final time = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    return DateTime.now().day == t.day ? 'Today, $time' : 'Yesterday, $time';
  }
}
