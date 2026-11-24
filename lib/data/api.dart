import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  final _auth = PasskeyAuthenticator();

  Future<void> load() async {
    try {
      _token = await _storage.read(key: _tokenKey);
    } catch (_) {
      _token = null;
    }
  }

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
    return AuthResult(ApiUser.fromJson(d['user'] as Map<String, dynamic>), d['isNew'] == true, d['hasPasskey'] == true);
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

  Future<void> deleteAccount() async {
    await _call('DELETE', '/v1/me');
    await _setToken(null);
  }

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
  Future<AuthResult> loginWithPasskey() async {
    final o = await _call('POST', '/v1/auth/passkey/login/options');
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
      NoCredentialsAvailableException() => 'No BAATLY passkey found on this phone. Log in with OTP.',
      DeviceNotSupportedException() => 'This phone doesn\'t support passkeys. Log in with OTP.',
      DomainNotAssociatedException() => 'Passkey setup is incomplete (domain link). Log in with OTP.',
      _ => 'Passkey didn\'t work. Make sure a screen lock and Google account are set up.',
    };
    return ApiException(-1, e is PasskeyAuthCancelledException ? 'CANCELLED' : 'PASSKEY', msg);
  }
}
