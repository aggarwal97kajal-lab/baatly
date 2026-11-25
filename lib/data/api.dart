import 'dart:convert';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:http/http.dart' as http;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import '../config.dart';

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  ApiException(this.status, this.code, this.message);
  @override
  String toString() => message;
}

class ApiUser {
  final String id, phone, name, about;
  final String? username;
  ApiUser.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        phone = j['phone'] as String,
        name = (j['name'] as String?) ?? '',
        about = (j['about'] as String?) ?? '',
        username = j['username'] as String?;
}

class AuthResult {
  final ApiUser user;
  final bool isNew;
  final bool hasPasskey;
  AuthResult(this.user, this.isNew, this.hasPasskey);
}

class OtpRequest {
  final String requestId;
  final String phone;
  final bool demo;
  OtpRequest(this.requestId, this.phone, this.demo);
}

/// Talks to the BAATLY Cloudflare backend. The session token lives only in
/// Android Keystore-backed secure storage, never in plain preferences.
class Api {
  Api._();
  static final Api instance = Api._();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'session_token';
  static const _device = 'Android · BAATLY app';

  String? _token;
  String? _userId;
  static const _userIdKey = 'user_id';

  /// BAATLY id of the logged-in user (null when logged out).
  String? get userId => _token == null ? null : _userId;
  String? get token => _token;

  Future<void> rememberUserId(String id) async {
    _userId = id;
    try {
      await _storage.write(key: _userIdKey, value: id);
    } catch (_) {}
  }

  /// Uploads encrypted bytes (with progress 0..1); returns the media id.
  Future<String> upload(List<int> bytes, {void Function(double)? onProgress}) async {
    final req = http.StreamedRequest('POST', Uri.parse('$kApiBase/v1/media'))
      ..headers['content-type'] = 'application/octet-stream'
      ..contentLength = bytes.length;
    if (_token != null) req.headers['authorization'] = 'Bearer $_token';
    final send = http.Client().send(req);
    const chunk = 64 * 1024;
    for (var i = 0; i < bytes.length; i += chunk) {
      final end = i + chunk > bytes.length ? bytes.length : i + chunk;
      req.sink.add(bytes.sublist(i, end));
      onProgress?.call(end / bytes.length * 0.95);
      await Future<void>.delayed(Duration.zero);
    }
    await req.sink.close();
    http.Response r;
    try {
      r = await http.Response.fromStream(await send.timeout(const Duration(minutes: 5)));
    } catch (_) {
      throw ApiException(0, 'NETWORK', "Couldn't upload. Check your internet.");
    }
    Map<String, dynamic> d = {};
    try {
      d = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    if (r.statusCode >= 400) throw ApiException(r.statusCode, (d['error'] as String?) ?? 'ERROR', _friendly(d));
    onProgress?.call(1);
    return d['id'] as String;
  }

  /// Downloads encrypted media bytes (with progress 0..1).
  Future<List<int>> download(String id, {void Function(double)? onProgress}) async {
    final req = http.Request('GET', Uri.parse('$kApiBase/v1/media/$id'));
    if (_token != null) req.headers['authorization'] = 'Bearer $_token';
    http.StreamedResponse r;
    try {
      r = await http.Client().send(req).timeout(const Duration(minutes: 1));
    } catch (_) {
      throw ApiException(0, 'NETWORK', "Couldn't download. Check your internet.");
    }
    if (r.statusCode >= 400) {
      final body = await r.stream.bytesToString();
      Map<String, dynamic> d = {};
      try {
        d = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {}
      throw ApiException(r.statusCode, (d['error'] as String?) ?? 'ERROR', _friendly(d));
    }
    final total = r.contentLength ?? 0;
    final out = <int>[];
    try {
      await for (final c in r.stream.timeout(const Duration(minutes: 2))) {
        out.addAll(c);
        if (total > 0) onProgress?.call(out.length / total);
      }
    } catch (_) {
      throw ApiException(0, 'NETWORK', "Couldn't download. Check your internet.");
    }
    return out;
  }

  /// Authenticated JSON call, used by the messenger.
  Future<Map<String, dynamic>> request(String method, String path, [Object? body]) => _call(method, path, body);
  final _auth = PasskeyAuthenticator();

  static const _dkIdKey = 'device_key_id';
  static const _dkSeedKey = 'device_key_seed';
  String? _deviceKeyId;
  final _localAuth = LocalAuthentication();

  Future<void> load() async {
    try {
      _token = await _storage.read(key: _tokenKey);
      _userId = await _storage.read(key: _userIdKey);
      _deviceKeyId = await _storage.read(key: _dkIdKey);
    } catch (_) {
      _token = null;
    }
  }

  /// True when fingerprint login is set up on this phone.
  bool get hasFingerprint => _deviceKeyId != null;

  bool get loggedIn => _token != null;

  Future<void> _setToken(String? t) async {
    _token = t;
    if (t == null) {
      await _storage.delete(key: _tokenKey);
    } else {
      await _storage.write(key: _tokenKey, value: t);
    }
  }

  Future<Map<String, dynamic>> _call(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$kApiBase$path');
    final headers = {
      'content-type': 'application/json',
      if (_token != null) 'authorization': 'Bearer $_token',
    };
    http.Response r;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 20)));
    } catch (_) {
      throw ApiException(0, 'NETWORK', 'Can\'t reach the server. Check your internet and try again.');
    }
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    if (r.statusCode >= 400) {
      if (r.statusCode == 401) await _setToken(null);
      throw ApiException(r.statusCode, (data['error'] as String?) ?? 'ERROR', _friendly(data));
    }
    return data;
  }

  String _friendly(Map<String, dynamic> d) {
    final code = d['error'] as String? ?? '';
    final msg = d['message'] as String? ?? '';
    if (msg.isNotEmpty && msg != code) return msg;
    return switch (code) {
      'INVALID_PHONE' => 'Enter a valid mobile number',
      'TOO_MANY_OTP' || 'OTP_LIMIT_REACHED' => 'Too many codes requested. Please try again later.',
      'OTP_ALREADY_SENT' => 'A code was already sent. Please check your SMS.',
      'WRONG_OTP' => 'Incorrect code',
      'OTP_EXPIRED' => 'Code expired. Request a new one.',
      'USERNAME_TAKEN' => 'This username is already taken',
      'OTP_NOT_CONFIGURED' => 'OTP service is not set up yet',
      'OTP_PROVIDER_AUTH_FAILED' || 'OTP_SEND_FAILED' || 'OTP_CHECK_FAILED' =>
        "We couldn't send the SMS right now. Please try again in a few minutes. ($code)",
      'SERVER_ERROR' => 'Something went wrong on our side. Please try again. ($code)',
      _ => 'Something went wrong. Please try again.',
    };
  }

  // ------------------------------------------------------------ OTP
  Future<OtpRequest> sendOtp(String countryCode, String number) async {
    final d = await _call('POST', '/v1/auth/otp/send', {'countryCode': countryCode.replaceAll('+', ''), 'number': number});
    return OtpRequest(d['requestId'] as String, d['phone'] as String, d['demo'] == true);
  }

  Future<AuthResult> verifyOtp(String requestId, String code) async {
    final d = await _call('POST', '/v1/auth/otp/verify', {'requestId': requestId, 'code': code, 'device': _device});
    return _session(d);
  }

  Future<AuthResult> _session(Map<String, dynamic> d) async {
    await _setToken(d['token'] as String);
    final user = ApiUser.fromJson(d['user'] as Map<String, dynamic>);
    _userId = user.id;
    try {
      await _storage.write(key: _userIdKey, value: user.id);
    } catch (_) {}
    return AuthResult(user, d['isNew'] == true, d['hasPasskey'] == true);
  }

  // ------------------------------------------------------------ profile
  Future<ApiUser> updateProfile({required String name, required String username, required String about}) async {
    final d = await _call('PATCH', '/v1/me', {'name': name, 'username': username, 'about': about});
    return ApiUser.fromJson(d['user'] as Map<String, dynamic>);
  }

  Future<bool> usernameAvailable(String u) async {
    final d = await _call('GET', '/v1/username/available?u=${Uri.encodeQueryComponent(u)}');
    return d['available'] == true;
  }

  Future<void> logout() async {
    try {
      if (_token != null) await _call('POST', '/v1/auth/logout');
    } catch (_) {}
    await _setToken(null);
  }

  /// Removes this account's passkeys from the server so a fresh one can be created.
  Future<void> resetPasskeys() async {
    await _call('DELETE', '/v1/me/passkeys');
  }

  Future<void> deleteAccount() async {
    await _call('DELETE', '/v1/me');
    await _setToken(null);
    await _clearDeviceKey();
  }

  // ------------------------------------------------------------ fingerprint (device key)
  // A private key is created on this phone and stays in Android Keystore-backed
  // storage. The server only keeps the public key. Logging in = fingerprint /
  // screen lock check, then signing a one-time challenge from the server.

  Future<void> _askFingerprint(String reason) async {
    bool ok;
    try {
      if (!await _localAuth.isDeviceSupported()) {
        throw ApiException(-1, 'NO_LOCK', 'Set a fingerprint or screen lock on this phone first (phone Settings → Security).');
      }
      ok = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
    } on PlatformException catch (e) {
      throw ApiException(-1, 'FINGERPRINT', "Fingerprint didn't work. [${e.code}] ${e.message ?? ''}".trim());
    }
    if (!ok) throw ApiException(-1, 'CANCELLED', 'Cancelled');
  }

  /// Turns on fingerprint login for the logged-in user on this phone.
  Future<void> enableFingerprint() async {
    await _askFingerprint('Confirm to turn on fingerprint login');
    final algo = crypto.Ed25519();
    final kp = await algo.newKeyPair();
    final seed = await kp.extractPrivateKeyBytes();
    final pub = (await kp.extractPublicKey()).bytes;
    final d = await _call('POST', '/v1/auth/device/register', {'publicKey': _b64url(pub), 'device': _device});
    final id = d['keyId'] as String;
    await _storage.write(key: _dkSeedKey, value: base64Encode(seed));
    await _storage.write(key: _dkIdKey, value: id);
    _deviceKeyId = id;
  }

  /// Logs in with the key saved on this phone after a fingerprint check.
  Future<AuthResult> loginWithFingerprint() async {
    final id = _deviceKeyId;
    final seedB64 = await _storage.read(key: _dkSeedKey);
    if (id == null || seedB64 == null) {
      await _clearDeviceKey();
      throw ApiException(-1, 'NO_KEY', 'Fingerprint login is not set up on this phone. Log in with OTP.');
    }
    await _askFingerprint('Confirm it\'s you to log in to BAATLY');
    final Map<String, dynamic> ch;
    try {
      ch = await _call('POST', '/v1/auth/device/challenge', {'keyId': id});
    } on ApiException catch (e) {
      if (e.code == 'DEVICE_KEY_NOT_FOUND') await _clearDeviceKey();
      rethrow;
    }
    final kp = await crypto.Ed25519().newKeyPairFromSeed(base64Decode(seedB64));
    final sig = await crypto.Ed25519().sign(utf8.encode(ch['challenge'] as String), keyPair: kp);
    try {
      final d = await _call('POST', '/v1/auth/device/verify',
          {'flowId': ch['flowId'], 'keyId': id, 'signature': _b64url(sig.bytes), 'device': _device});
      return _session(d);
    } on ApiException catch (e) {
      if (e.code == 'DEVICE_KEY_NOT_FOUND' || e.code == 'BAD_SIGNATURE') await _clearDeviceKey();
      rethrow;
    }
  }

  /// Turns fingerprint login off for this phone.
  Future<void> disableFingerprint() async {
    final id = _deviceKeyId;
    if (id != null && _token != null) {
      try {
        await _call('DELETE', '/v1/me/device-keys/$id');
      } catch (_) {}
    }
    await _clearDeviceKey();
  }

  Future<void> _clearDeviceKey() async {
    _deviceKeyId = null;
    try {
      await _storage.delete(key: _dkIdKey);
      await _storage.delete(key: _dkSeedKey);
    } catch (_) {}
  }

  static String _b64url(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  // ------------------------------------------------------------ passkeys
  /// Creates a passkey for the logged-in user (fingerprint / screen lock).
  Future<void> createPasskey() async {
    final o = await _call('POST', '/v1/auth/passkey/register/options');
    final req = RegisterRequestType.fromJson(o['options'] as Map<String, dynamic>);
    final RegisterResponseType res;
    try {
      res = await _auth.register(req);
    } on AuthenticatorException catch (e) {
      throw _passkeyError(e);
    }
    await _call('POST', '/v1/auth/passkey/register/verify', {'flowId': o['flowId'], 'response': res.toJson(), 'device': _device});
  }

  /// Signs in with a passkey saved on this phone / Google account.
  Future<AuthResult> loginWithPasskey({String? countryCode, String? number}) async {
    final o = await _call('POST', '/v1/auth/passkey/login/options',
        number != null && number.length >= 6 ? {'countryCode': countryCode?.replaceAll('+', ''), 'number': number} : <String, dynamic>{});
    final req = AuthenticateRequestType.fromJson(o['options'] as Map<String, dynamic>, preferImmediatelyAvailableCredentials: false);
    final AuthenticateResponseType res;
    try {
      res = await _auth.authenticate(req);
    } on AuthenticatorException catch (e) {
      throw _passkeyError(e);
    }
    final d = await _call('POST', '/v1/auth/passkey/login/verify', {'flowId': o['flowId'], 'response': res.toJson(), 'device': _device});
    return _session(d);
  }

  ApiException _passkeyError(AuthenticatorException e) {
    final msg = switch (e) {
      PasskeyAuthCancelledException() => 'Cancelled',
      NoCredentialsAvailableException() => 'No BAATLY passkey found. Type your phone number above and tap "Log in with passkey" again, or log in with OTP.',
      DeviceNotSupportedException() || PasskeyUnsupportedException() => "This phone doesn't support passkeys. Log in with OTP.",
      DomainNotAssociatedException(:final message) => 'Passkey setup is incomplete (app not linked to domain). [domain] ${message ?? ''}',
      NoCreateOptionException(:final message) =>
        'No passkey provider is on. Open phone Settings → Passwords & accounts (or Autofill) and turn on Google Password Manager. [no-create-option] ${message ?? ''}',
      MissingGoogleSignInException() => 'Sign in to a Google account on this phone to save passkeys. [missing-google-sign-in]',
      SyncAccountNotAvailableException() => 'Your Google account needs to sync passwords. Check Google Password Manager settings. [sync-account]',
      ExcludeCredentialsCanNotBeRegisteredException() => 'ALREADY_EXISTS',
      TimeoutException() => 'Passkey request timed out. Please try again. [timeout]',
      UnhandledAuthenticatorException(:final code, :final message) => "Passkey didn't work. [$code] ${message ?? ''}",
      _ => "Passkey didn't work. [${e.runtimeType}]",
    };
    final code = switch (e) {
      PasskeyAuthCancelledException() => 'CANCELLED',
      ExcludeCredentialsCanNotBeRegisteredException() => 'ALREADY_EXISTS',
      _ => 'PASSKEY',
    };
    return ApiException(-1, code, msg.trim());
  }
}
