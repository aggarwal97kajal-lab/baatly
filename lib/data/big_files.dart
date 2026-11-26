import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'api.dart';

/// Files bigger than [threshold] (up to 2 GB) go in 8 MB pieces: each piece is
/// encrypted on its own (AES-256-GCM, a fresh key per file, the piece number
/// as nonce) and uploaded as one part. The whole file is never in memory, and
/// a failed piece is simply sent again.
class BigFiles {
  BigFiles._();

  static const chunk = 8 * 1024 * 1024;
  static const threshold = 16 * 1024 * 1024;
  static const maxSize = 2 * 1024 * 1024 * 1024;
  static const _tag = 16;

  static List<int> _nonce(int i) {
    final n = Uint8List(12);
    ByteData.view(n.buffer).setUint32(8, i);
    return n;
  }

  // Phone's own AES (cryptography_flutter): fast and off the UI thread.
  static final _aes = AesGcm.with256bits();

  static Future<List<int>> _enc(List<int> plain, List<int> key, int i) async {
    final box = await _aes.encrypt(plain, secretKey: SecretKey(key), nonce: _nonce(i));
    final ct = box.cipherText;
    final out = Uint8List(ct.length + _tag)
      ..setAll(0, ct)
      ..setAll(ct.length, box.mac.bytes);
    return out;
  }

  static Future<List<int>> _dec(List<int> blob, List<int> key, int i) {
    final cipher = blob.sublist(0, blob.length - _tag);
    final mac = Mac(blob.sublist(blob.length - _tag));
    return _aes.decrypt(SecretBox(cipher, nonce: _nonce(i), mac: mac), secretKey: SecretKey(key));
  }

  /// Pieces in flight at once (upload and download).
  static const _lanes = 3;

  static Future<T> _retry<T>(Future<T> Function() f) async {
    Object? last;
    for (var a = 0; a < 5; a++) {
      try {
        return await f();
      } on ApiException catch (e) {
        last = e;
        if (e.status >= 400 && e.status < 500 && e.status != 408 && e.status != 429) rethrow;
      } catch (e) {
        last = e;
      }
      await Future<void>.delayed(Duration(seconds: 2 << a));
    }
    throw last ?? ApiException(0, 'NETWORK', "Couldn't send. Check your internet.");
  }

  /// Encrypts and uploads [path]. Returns the media fields for the message.
  static Future<Map<String, dynamic>> upload(String path, {void Function(double)? onProgress}) async {
    final file = File(path);
    final size = await file.length();
    if (size > maxSize) throw ApiException(413, 'FILE_TOO_LARGE', 'Files up to 2 GB can be sent.');
    final rnd = Random.secure();
    final key = List<int>.generate(32, (_) => rnd.nextInt(256));
    final pieces = (size + chunk - 1) ~/ chunk;
    final start = await Api.instance.request('POST', '/v1/media/big', {'size': size + pieces * _tag});
    final id = start['id'] as String;
    final upload = start['upload'] as String;
    final total = size + pieces * _tag;
    final sent = List<int>.filled(pieces, 0);
    void report() => onProgress?.call(sent.fold<int>(0, (a, b) => a + b) / total);
    final etags = List<String?>.filled(pieces, null);
    var next = 0;
    try {
      Future<void> lane() async {
        final raf = await file.open();
        try {
          while (true) {
            final i = next++;
            if (i >= pieces) return;
            await raf.setPosition(i * chunk);
            final plain = await raf.read(min(chunk, size - i * chunk));
            final enc = await _enc(plain, key, i);
            etags[i] = await _retry(() => Api.instance.putPartStreamed(id, upload, i + 1, enc, (b) {
                  sent[i] = b;
                  report();
                }));
            sent[i] = enc.length;
            report();
          }
        } finally {
          await raf.close();
        }
      }

      await Future.wait([for (var l = 0; l < min(_lanes, pieces); l++) lane()], eagerError: true);
      final parts = [for (var i = 0; i < pieces; i++) {'n': i + 1, 'etag': etags[i]}];
      await _retry(() => Api.instance.request('POST', '/v1/media/big/$id/done', {'upload': upload, 'parts': parts}));
      return {'id': id, 'k': _b64(key), 'cv': 2, 'cs': chunk, 'size': size};
    } catch (e) {
      try {
        await Api.instance.request('DELETE', '/v1/media/big/$id?u=${Uri.encodeQueryComponent(upload)}');
      } catch (_) {}
      rethrow;
    }
  }

  /// Downloads + decrypts a big file into [out], piece by piece.
  static Future<void> download(Map<String, dynamic> md, File out, {void Function(double)? onProgress}) async {
    final id = md['id'] as String;
    final key = _unb64(md['k'] as String);
    final size = (md['size'] as num).toInt();
    final cs = (md['cs'] as num?)?.toInt() ?? chunk;
    final pieces = (size + cs - 1) ~/ cs;
    final total = size + pieces * _tag;
    final got = List<int>.filled(pieces, 0);
    void report() => onProgress?.call(got.fold<int>(0, (a, b) => a + b) / total);
    final tmp = File('${out.path}.part');
    final sink = await tmp.open(mode: FileMode.write);
    // Pieces come down 3 at a time but are written in order.
    final ready = <int, List<int>>{};
    final waiters = <int, Completer<void>>{};
    var next = 0;
    var written = 0;
    Object? failure;
    Future<void> lane() async {
      while (failure == null) {
        final i = next++;
        if (i >= pieces) return;
        // Don't run far ahead of the writer (keeps memory to a few pieces).
        while (i - written >= _lanes * 2 && failure == null) {
          final c = waiters.putIfAbsent(written, () => Completer<void>());
          await c.future;
        }
        final plainLen = min(cs, size - i * cs);
        final blob = await _retry(() => Api.instance.getRangeStreamed(id, i * (cs + _tag), plainLen + _tag, (b) {
              got[i] = b;
              report();
            }));
        ready[i] = await _dec(blob, key, i);
        while (ready.containsKey(written)) {
          final w = written;
          await sink.writeFrom(ready.remove(w)!);
          written = w + 1;
          waiters.remove(w)?.complete();
        }
      }
    }

    try {
      await Future.wait([for (var l = 0; l < min(_lanes, pieces); l++) lane()], eagerError: true);
    } catch (e) {
      failure = e;
      for (final c in waiters.values) {
        if (!c.isCompleted) c.complete();
      }
      rethrow;
    } finally {
      await sink.close();
    }
    if (written != pieces) throw ApiException(0, 'NETWORK', "Couldn't download. Check your internet.");
    if (await out.exists()) await out.delete();
    await tmp.rename(out.path);
  }

  static String _b64(List<int> b) => base64Encode(b);
  static List<int> _unb64(String s) => base64Decode(s);
}
