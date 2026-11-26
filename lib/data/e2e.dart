import 'dart:typed_data';
import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// End-to-end encryption for BAATLY messages (format v1).
///
/// Every account has an X25519 identity key that is created on the phone and
/// never leaves it; only the public half is sent to the server.
///
/// To send, the phone makes a fresh one-time key and combines
///   DH(one-time, recipient) + DH(my identity, recipient)
/// through HKDF-SHA256 into an AES-256-GCM key. The recipient can rebuild the
/// same key, and the second DH proves the message came from the sender's key.
/// The server only ever stores and forwards the encrypted box.
class E2E {
  E2E._();
  static final E2E instance = E2E._();

  /// Separate instance (tests).
  E2E.detached();

  /// Uses an existing key pair (tests).
  Future<void> useKeyPair(SimpleKeyPair kp) async {
    _identity = kp;
    _myPub = (await kp.extractPublicKey()).bytes;
  }

  static const _storage = FlutterSecureStorage();
  final _x = X25519();
  final _aead = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  SimpleKeyPair? _identity;
  List<int>? _myPub;
  String? _forUser;

  String get publicKey => _b64(_myPub!);

  /// The identity key seed, for an end-to-end encrypted backup.
  Future<String?> exportSeed(String userId) => _storage.read(key: 'e2e_x25519_$userId');

  /// Puts back the identity key from a backup.
  Future<void> importSeed(String userId, String seed) async {
    await _storage.write(key: 'e2e_x25519_$userId', value: seed);
    _forUser = null;
    _identity = null;
    await load(userId);
  }

  /// Loads (or creates) the identity key for [userId].
  Future<void> load(String userId) async {
    if (_forUser == userId && _identity != null) return;
    final k = 'e2e_x25519_$userId';
    final saved = await _storage.read(key: k);
    SimpleKeyPair kp;
    if (saved != null) {
      kp = await _x.newKeyPairFromSeed(base64Decode(saved));
    } else {
      kp = await _x.newKeyPair();
      await _storage.write(key: k, value: base64Encode(await kp.extractPrivateKeyBytes()));
    }
    _identity = kp;
    _myPub = (await kp.extractPublicKey()).bytes;
    _forUser = userId;
  }

  Future<SecretKey> _key(List<int> dh1, List<int> dh2, List<int> eph, List<int> from, List<int> to) {
    return _hkdf.deriveKey(
      secretKey: SecretKey([...dh1, ...dh2]),
      nonce: [...eph, ...from, ...to],
      info: utf8.encode('baatly-msg-v1'),
    );
  }

  Future<List<int>> _dh(KeyPair mine, List<int> theirs) async {
    final s = await _x.sharedSecretKey(keyPair: mine, remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519));
    return s.extractBytes();
  }

  /// Encrypts [plain] for the holder of [recipientKey] (base64url).
  Future<String> seal(Map<String, dynamic> plain, String recipientKey) async {
    final to = _unb64(recipientKey);
    final eph = await _x.newKeyPair();
    final ephPub = (await eph.extractPublicKey()).bytes;
    final key = await _key(await _dh(eph, to), await _dh(_identity!, to), ephPub, _myPub!, to);
    final box = await _aead.encrypt(utf8.encode(jsonEncode(plain)), secretKey: key);
    return jsonEncode({
      'v': 1,
      'e': _b64(ephPub),
      'n': _b64(box.nonce),
      'c': _b64(box.cipherText),
      'm': _b64(box.mac.bytes),
    });
  }

  /// Decrypts a box from the holder of [senderKey]. Throws if it was tampered
  /// with, sent to an old key of ours, or not really from that sender.
  Future<Map<String, dynamic>> open(String body, String senderKey) async {
    final j = jsonDecode(body) as Map<String, dynamic>;
    if (j['v'] != 1) throw const FormatException('unknown version');
    final from = _unb64(senderKey);
    final eph = _unb64(j['e'] as String);
    final key = await _key(await _dh(_identity!, eph), await _dh(_identity!, from), eph, from, _myPub!);
    final clear = await _aead.decrypt(
      SecretBox(_unb64(j['c'] as String), nonce: _unb64(j['n'] as String), mac: Mac(_unb64(j['m'] as String))),
      secretKey: key,
    );
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  /// Encrypts [data] with a fresh random key. Returns (key, nonce+cipher+mac).
  Future<(List<int>, List<int>)> lock(List<int> data) async {
    final key = await _aead.newSecretKey();
    final box = await _aead.encrypt(data, secretKey: key);
    final n = box.nonce, c = box.cipherText, m = box.mac.bytes;
    final out = Uint8List(n.length + c.length + m.length)
      ..setAll(0, n)
      ..setAll(n.length, c)
      ..setAll(n.length + c.length, m);
    return (await key.extractBytes(), out);
  }

  /// Same as [lock] but on a background isolate, so big files don't freeze the app
  /// (and other messages keep sending meanwhile).
  // AES-GCM runs in the phone's own (hardware) crypto via cryptography_flutter: much faster
  // than pure Dart and off the UI thread. A background isolate can't reach that plugin,
  // so these run here.
  static Future<(List<int>, List<int>)> lockInBackground(List<int> data) => E2E.detached().lock(data);

  static Future<List<int>> unlockInBackground(List<int> blob, List<int> key) => E2E.detached().unlock(blob, key);

  Future<List<int>> unlock(List<int> blob, List<int> key) {
    final nonce = blob.sublist(0, 12);
    final mac = Mac(blob.sublist(blob.length - 16));
    final cipher = blob.sublist(12, blob.length - 16);
    return _aead.decrypt(SecretBox(cipher, nonce: nonce, mac: mac), secretKey: SecretKey(key));
  }

  static String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
  static List<int> _unb64(String s) => base64Url.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));
}
