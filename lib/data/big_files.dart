import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
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

  static Future<List<int>> _enc(Uint8List plain, List<int> key, int i) => Isolate.run(() async {
        final box = await AesGcm.with256bits().encrypt(plain, secretKey: SecretKey(key), nonce: _nonce(i));
        return [...box.cipherText, ...box.mac.bytes];
      });

  static Future<List<int>> _dec(List<int> blob, List<int> key, int i) => Isolate.run(() async {
        final cipher = blob.sublist(0, blob.length - _tag);
        final mac = Mac(blob.sublist(blob.length - _tag));
        return AesGcm.with256bits().decrypt(SecretBox(cipher, nonce: _nonce(i), mac: mac), secretKey: SecretKey(key));
      });

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
    final raf = await file.open();
    try {
      final parts = <Map<String, dynamic>>[];
      for (var i = 0; i < pieces; i++) {
        await raf.setPosition(i * chunk);
        final plain = await raf.read(min(chunk, size - i * chunk));
        final enc = await _enc(plain, key, i);
        final etag = await _retry(() => Api.instance.putPart(id, upload, i + 1, enc));
        parts.add({'n': i + 1, 'etag': etag});
        onProgress?.call((i + 1) / pieces);
      }
      await _retry(() => Api.instance.request('POST', '/v1/media/big/$id/done', {'upload': upload, 'parts': parts}));
      return {'id': id, 'k': _b64(key), 'cv': 2, 'cs': chunk, 'size': size};
    } catch (e) {
      try {
        await Api.instance.request('DELETE', '/v1/media/big/$id?u=${Uri.encodeQueryComponent(upload)}');
      } catch (_) {}
      rethrow;
    } finally {
      await raf.close();
    }
  }

  /// Downloads + decrypts a big file into [out], piece by piece.
  static Future<void> download(Map<String, dynamic> md, File out, {void Function(double)? onProgress}) async {
    final id = md['id'] as String;
    final key = _unb64(md['k'] as String);
    final size = (md['size'] as num).toInt();
    final cs = (md['cs'] as num?)?.toInt() ?? chunk;
    final pieces = (size + cs - 1) ~/ cs;
    final tmp = File('${out.path}.part');
    final sink = await tmp.open(mode: FileMode.write);
    try {
      for (var i = 0; i < pieces; i++) {
        final plainLen = min(cs, size - i * cs);
        final blob = await _retry(() => Api.instance.getRange(id, i * (cs + _tag), plainLen + _tag));
        final clear = await _dec(blob, key, i);
        await sink.writeFrom(clear);
        onProgress?.call((i + 1) / pieces);
      }
    } finally {
      await sink.close();
    }
    if (await out.exists()) await out.delete();
    await tmp.rename(out.path);
  }

  static String _b64(List<int> b) => base64Encode(b);
  static List<int> _unb64(String s) => base64Decode(s);
}
