import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'messenger.dart';

/// Chat backup to the user's own Google Drive (hidden app folder, only
/// BAATLY can see it). Optional password = end-to-end encrypted backup.
class BackupService extends ChangeNotifier {
  BackupService._();
  static final instance = BackupService._();

  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _magic = 'BKP1';
  final _secure = const FlutterSecureStorage();

  // Settings (persisted)
  String? email;
  int auto = 0; // 0 off (only when I tap "Back up"), 1 daily, 2 weekly, 3 monthly
  bool overMobile = false;
  bool includeVideos = false;
  bool encrypted = false;
  DateTime? lastAt;
  int lastSize = 0;

  // Live state
  bool busy = false;
  double? progress;
  String? stage;
  String? error;

  bool _inited = false;
  GoogleSignInAccount? _account;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    email = p.getString('bk_email');
    auto = p.getInt('bk_auto') ?? 0;
    overMobile = p.getBool('bk_cell') ?? false;
    includeVideos = p.getBool('bk_videos') ?? false;
    encrypted = p.getBool('bk_e2e') ?? false;
    final l = p.getInt('bk_last');
    lastAt = l == null ? null : DateTime.fromMillisecondsSinceEpoch(l);
    lastSize = p.getInt('bk_size') ?? 0;
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    if (email == null) {
      await p.remove('bk_email');
    } else {
      await p.setString('bk_email', email!);
    }
    await p.setInt('bk_auto', auto);
    await p.setBool('bk_cell', overMobile);
    await p.setBool('bk_videos', includeVideos);
    await p.setBool('bk_e2e', encrypted);
    if (lastAt != null) await p.setInt('bk_last', lastAt!.millisecondsSinceEpoch);
    await p.setInt('bk_size', lastSize);
  }

  void set(void Function() f) {
    f();
    notifyListeners();
    unawaited(_persist());
  }

  // ------------------------------------------------------------------ Google account
  Future<void> _init() async {
    if (_inited) return;
    // Web client id from google-services.json (public, not a secret).
    await GoogleSignIn.instance.initialize(serverClientId: '69592152328-i817576ud5aqhbnnidsrhis5qqb4f813.apps.googleusercontent.com');
    _inited = true;
  }

  /// Lets the user pick which Google account the backup goes to.
  Future<bool> chooseAccount() async {
    try {
      await _init();
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
      _account = await GoogleSignIn.instance.authenticate(scopeHint: const [_scope]);
      await _account!.authorizationClient.authorizeScopes(const [_scope]);
      set(() => email = _account!.email);
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        error = "Couldn't connect Google account (${e.code.name}). Google Drive backup needs one-time setup.";
        notifyListeners();
      }
      return false;
    } catch (e) {
      error = "Couldn't connect Google account. Google Drive backup needs one-time setup.";
      notifyListeners();
      return false;
    }
  }

  Future<String?> _token({required bool interactive}) async {
    await _init();
    _account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (_account == null) {
      if (!interactive) return null;
      if (!await chooseAccount()) return null;
    }
    var a = await _account!.authorizationClient.authorizationForScopes(const [_scope]);
    if (a == null && interactive) a = await _account!.authorizationClient.authorizeScopes(const [_scope]);
    return a?.accessToken;
  }

  // ------------------------------------------------------------------ Drive REST
  Future<Map<String, dynamic>?> _find(String token) async {
    final uid = Api.instance.userId;
    final q = Uri.encodeQueryComponent("name='baatly_$uid.bkp'");
    final r = await http.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=$q&fields=files(id,size,modifiedTime,appProperties)'),
      headers: {'authorization': 'Bearer $token'},
    );
    if (r.statusCode != 200) throw Exception('drive ${r.statusCode}');
    final files = (jsonDecode(r.body)['files'] as List?) ?? [];
    return files.isEmpty ? null : (files.first as Map).cast<String, dynamic>();
  }

  /// Info about the backup on Drive (for "Restore").
  Future<({DateTime at, int size, bool encrypted})?> remoteInfo({bool interactive = false}) async {
    final t = await _token(interactive: interactive);
    if (t == null) return null;
    final f = await _find(t);
    if (f == null) return null;
    return (
      at: DateTime.tryParse(f['modifiedTime'] as String? ?? '') ?? DateTime.now(),
      size: int.tryParse('${f['size']}') ?? 0,
      encrypted: (f['appProperties'] as Map?)?['e2e'] == '1',
    );
  }

  // ------------------------------------------------------------------ back up
  Future<bool> backup({String? password, bool interactive = true}) async {
    if (busy) return false;
    final uid = Api.instance.userId;
    if (uid == null) return false;
    busy = true;
    error = null;
    progress = null;
    stage = 'Preparing backup…';
    notifyListeners();
    File? plain, enc;
    try {
      final token = await _token(interactive: interactive);
      if (token == null) throw _Msg('Choose a Google account first.');
      if (encrypted) {
        password ??= await _secure.read(key: 'bk_pw');
        if (password == null) throw _Msg('Set your backup password again.');
      }
      await Messenger.instance.flushLocal();
      final docs = await getApplicationDocumentsDirectory();
      final tmp = await getTemporaryDirectory();
      plain = File('${tmp.path}/bk_plain');
      final out = plain.openWrite();
      Future<void> add(String name, File f) async {
        final n = utf8.encode(name);
        final len = await f.length();
        out.add(_u32(n.length));
        out.add(n);
        out.add(_u64(len));
        await out.addStream(f.openRead());
      }

      final chats = File('${docs.path}/chats_$uid.json');
      if (await chats.exists()) await add('chats.json', chats);
      final media = Directory('${docs.path}/media');
      if (await media.exists()) {
        await for (final e in media.list(recursive: true, followLinks: false)) {
          if (e is! File) continue;
          final ext = e.path.split('.').last.toLowerCase();
          if (!includeVideos && const {'mp4', 'mov', '3gp', 'mkv', 'webm'}.contains(ext)) continue;
          await add('media/${e.path.substring(media.path.length + 1)}', e);
        }
      }
      for (final sub in const ['stickers/mine', 'photos']) {
        final d = Directory('${docs.path}/$sub');
        if (!await d.exists()) continue;
        await for (final e in d.list(followLinks: false)) {
          if (e is File) await add('$sub/${e.path.substring(d.path.length + 1)}', e);
        }
      }
      await out.close();

      var upload = plain;
      if (encrypted) {
        stage = 'Encrypting…';
        notifyListeners();
        enc = File('${tmp.path}/bk_enc');
        await _encrypt(plain, enc, password!);
        upload = enc;
      } else {
        enc = File('${tmp.path}/bk_enc');
        final w = enc.openWrite();
        w.add(utf8.encode(_magic));
        w.add([0]);
        await w.addStream(plain.openRead());
        await w.close();
        upload = enc;
      }

      stage = 'Uploading…';
      notifyListeners();
      final size = await upload.length();
      final existing = await _find(token);
      final meta = {
        'name': 'baatly_$uid.bkp',
        if (existing == null) 'parents': ['appDataFolder'],
        'appProperties': {'e2e': encrypted ? '1' : '0', 'v': '1'},
      };
      final start = http.Request(
        existing == null ? 'POST' : 'PATCH',
        Uri.parse(existing == null
            ? 'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable'
            : 'https://www.googleapis.com/upload/drive/v3/files/${existing['id']}?uploadType=resumable'),
      )
        ..headers.addAll({
          'authorization': 'Bearer $token',
          'content-type': 'application/json; charset=UTF-8',
          'x-upload-content-type': 'application/octet-stream',
          'x-upload-content-length': '$size',
        })
        ..body = jsonEncode(meta);
      final sr = await http.Response.fromStream(await start.send());
      final loc = sr.headers['location'];
      if (sr.statusCode >= 300 || loc == null) throw Exception('start ${sr.statusCode} ${sr.body}');
      final hc = HttpClient();
      try {
        final put = await hc.putUrl(Uri.parse(loc));
        put.headers.set('content-type', 'application/octet-stream');
        put.contentLength = size;
        var sent = 0;
        await for (final chunk in upload.openRead()) {
          put.add(chunk);
          sent += chunk.length;
          if (sent % (1 << 20) < chunk.length || sent == size) {
            await put.flush();
            progress = sent / size;
            notifyListeners();
          }
        }
        final res = await put.close();
        await res.drain<void>();
        if (res.statusCode >= 300) throw Exception('upload ${res.statusCode}');
      } finally {
        hc.close();
      }
      lastAt = DateTime.now();
      lastSize = size;
      await _persist();
      return true;
    } on _Msg catch (e) {
      error = e.m;
      return false;
    } catch (e) {
      error = "Couldn't back up. Check your internet and try again.";
      return false;
    } finally {
      try {
        await plain?.delete();
        await enc?.delete();
      } catch (_) {}
      busy = false;
      progress = null;
      stage = null;
      notifyListeners();
    }
  }

  /// Call on app start / resume: backs up when the chosen schedule is due.
  Future<void> maybeAuto() async {
    if (auto == 0 || busy || email == null) return;
    final every = switch (auto) { 1 => const Duration(days: 1), 2 => const Duration(days: 7), _ => const Duration(days: 30) };
    if (lastAt != null && DateTime.now().difference(lastAt!) < every) return;
    try {
      final c = await Connectivity().checkConnectivity();
      final wifi = c.contains(ConnectivityResult.wifi) || c.contains(ConnectivityResult.ethernet);
      if (!wifi && !overMobile) return;
      if (c.contains(ConnectivityResult.none)) return;
    } catch (_) {
      return;
    }
    await backup(interactive: false);
  }

  Future<void> setPassword(String? pw) async {
    if (pw == null) {
      await _secure.delete(key: 'bk_pw');
      set(() => encrypted = false);
    } else {
      await _secure.write(key: 'bk_pw', value: pw);
      set(() => encrypted = true);
    }
  }

  // ------------------------------------------------------------------ restore
  /// Downloads the backup and puts chats + media back on this phone.
  Future<bool> restore({String? password}) async {
    if (busy) return false;
    final uid = Api.instance.userId;
    if (uid == null) return false;
    busy = true;
    error = null;
    stage = 'Downloading backup…';
    progress = null;
    notifyListeners();
    File? f, plain;
    try {
      final token = await _token(interactive: true);
      if (token == null) throw _Msg('Choose a Google account first.');
      final meta = await _find(token);
      if (meta == null) throw _Msg('No backup found in this Google account.');
      final tmp = await getTemporaryDirectory();
      f = File('${tmp.path}/bk_dl');
      final req = http.Request('GET', Uri.parse('https://www.googleapis.com/drive/v3/files/${meta['id']}?alt=media'))
        ..headers['authorization'] = 'Bearer $token';
      final res = await http.Client().send(req);
      if (res.statusCode != 200) throw Exception('download ${res.statusCode}');
      final total = res.contentLength ?? int.tryParse('${meta['size']}') ?? 0;
      final sink = f.openWrite();
      var got = 0;
      await for (final c in res.stream) {
        sink.add(c);
        got += c.length;
        if (total > 0) {
          progress = got / total;
          notifyListeners();
        }
      }
      await sink.close();

      final raf = await f.open();
      final head = await raf.read(5);
      await raf.close();
      if (utf8.decode(head.sublist(0, 4), allowMalformed: true) != _magic) throw _Msg('This backup is damaged.');
      plain = File('${tmp.path}/bk_plain_r');
      if (head[4] == 1) {
        if (password == null) throw _Msg('This backup is protected with a password.');
        stage = 'Decrypting…';
        notifyListeners();
        await _decrypt(f, plain, password);
      } else {
        await plain.writeAsBytes(<int>[]);
        final w = plain.openWrite();
        await w.addStream(f.openRead(5));
        await w.close();
      }

      stage = 'Restoring…';
      progress = null;
      notifyListeners();
      final docs = await getApplicationDocumentsDirectory();
      final r = await plain.open();
      final len = await r.length();
      var pos = 0;
      while (pos < len) {
        final nl = _readU32(await r.read(4));
        final name = utf8.decode(await r.read(nl));
        final dl = _readU64(await r.read(8));
        pos += 4 + nl + 8;
        if (name.contains('..')) throw _Msg('This backup is damaged.');
        final dest = File(name == 'chats.json' ? '${docs.path}/chats_$uid.json' : '${docs.path}/$name');
        await dest.parent.create(recursive: true);
        final w = dest.openWrite();
        var left = dl;
        while (left > 0) {
          final b = await r.read(left > (1 << 20) ? (1 << 20) : left);
          if (b.isEmpty) throw _Msg('This backup is damaged.');
          w.add(b);
          left -= b.length;
        }
        await w.close();
        pos += dl;
      }
      await r.close();
      await Messenger.instance.reloadLocal();
      return true;
    } on _Msg catch (e) {
      error = e.m;
      return false;
    } on SecretBoxAuthenticationError {
      error = 'Wrong password.';
      return false;
    } catch (e) {
      error = "Couldn't restore. Check your internet and try again.";
      return false;
    } finally {
      try {
        await f?.delete();
        await plain?.delete();
      } catch (_) {}
      busy = false;
      progress = null;
      stage = null;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ crypto
  static final _aes = AesGcm.with256bits();

  static Future<SecretKey> _key(String pw, List<int> salt) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 150000, bits: 256).deriveKeyFromPassword(password: pw, nonce: salt);

  static Future<void> _encrypt(File src, File dst, String pw) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final key = await _key(pw, salt);
    final w = dst.openWrite();
    w.add(utf8.encode(_magic));
    w.add([1]);
    w.add(salt);
    final r = await src.open();
    while (true) {
      final chunk = await r.read(1 << 20);
      if (chunk.isEmpty) break;
      final box = await _aes.encrypt(chunk, secretKey: key);
      final body = box.concatenation();
      w.add(_u32(body.length));
      w.add(body);
    }
    await r.close();
    await w.close();
  }

  static Future<void> _decrypt(File src, File dst, String pw) async {
    final r = await src.open();
    await r.setPosition(5);
    final salt = await r.read(16);
    final key = await _key(pw, salt);
    final w = dst.openWrite();
    final len = await r.length();
    while (await r.position() < len) {
      final n = _readU32(await r.read(4));
      final body = await r.read(n);
      final box = SecretBox.fromConcatenation(body, nonceLength: 12, macLength: 16);
      w.add(await _aes.decrypt(box, secretKey: key));
    }
    await r.close();
    await w.close();
  }

  static Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);
  static Uint8List _u64(int v) => Uint8List(8)..buffer.asByteData().setUint64(0, v);
  static int _readU32(List<int> b) => ByteData.sublistView(Uint8List.fromList(b)).getUint32(0);
  static int _readU64(List<int> b) => ByteData.sublistView(Uint8List.fromList(b)).getUint64(0);
}

class _Msg implements Exception {
  final String m;
  _Msg(this.m);
}
