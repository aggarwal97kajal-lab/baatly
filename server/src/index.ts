import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from '@simplewebauthn/server';
import type { AuthenticationResponseJSON, AuthenticatorTransportFuture, RegistrationResponseJSON } from '@simplewebauthn/server';

import { checkOtp, demoMode, otpConfigured, sendOtp } from './otp';
import {
  Env,
  HttpError,
  androidOrigins,
  b64url,
  clientIp,
  fromB64url,
  json,
  normalisePhone,
  now,
  randomId,
  readJson,
  sha256Hex,
} from './util';

type User = { id: string; phone: string; name: string; username: string | null; about: string; created_at: number };
type Ctx = { req: Request; env: Env; url: URL };

const OTP_PER_PHONE_10MIN = 3;
const OTP_PER_IP_HOUR = 10;
const OTP_MAX_ATTEMPTS = 5;
const OTP_TTL_MS = 10 * 60 * 1000;
const CHALLENGE_TTL_MS = 5 * 60 * 1000;

const publicUser = (u: User) => ({ id: u.id, phone: u.phone, name: u.name, username: u.username, about: u.about });

// --------------------------------------------------------------- sessions
async function createSession(env: Env, userId: string, method: 'otp' | 'passkey', device: string) {
  const token = randomId(32);
  await env.DB.prepare(
    'INSERT INTO sessions (id, user_id, token_hash, device, method, created_at, last_seen_at) VALUES (?,?,?,?,?,?,?)',
  )
    .bind(randomId(), userId, await sha256Hex(token), device.slice(0, 80), method, now(), now())
    .run();
  return token;
}

async function requireUser(c: Ctx): Promise<{ user: User; sessionId: string }> {
  const h = c.req.headers.get('authorization') ?? '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : '';
  if (!token) throw new HttpError(401, 'UNAUTHENTICATED');
  const row = await c.env.DB.prepare(
    'SELECT s.id AS sid, u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?',
  )
    .bind(await sha256Hex(token))
    .first<User & { sid: string }>();
  if (!row) throw new HttpError(401, 'UNAUTHENTICATED');
  await c.env.DB.prepare('UPDATE sessions SET last_seen_at = ? WHERE id = ?').bind(now(), row.sid).run();
  const { sid, ...user } = row;
  return { user, sessionId: sid };
}

// --------------------------------------------------------------- OTP
async function otpSend(c: Ctx) {
  const body = await readJson<{ countryCode: string; number: string }>(c.req);
  const phone = normalisePhone(body.countryCode, body.number);
  const ip = clientIp(c.req);
  const t = now();
  const perPhone = await c.env.DB.prepare('SELECT COUNT(*) AS n FROM otp_requests WHERE phone = ? AND created_at > ?')
    .bind(phone, t - 10 * 60 * 1000)
    .first<{ n: number }>();
  if ((perPhone?.n ?? 0) >= OTP_PER_PHONE_10MIN) throw new HttpError(429, 'TOO_MANY_OTP', 'Too many codes requested. Please try again later.');
  if (ip) {
    const perIp = await c.env.DB.prepare('SELECT COUNT(*) AS n FROM otp_requests WHERE ip = ? AND created_at > ?')
      .bind(ip, t - 60 * 60 * 1000)
      .first<{ n: number }>();
    if ((perIp?.n ?? 0) >= OTP_PER_IP_HOUR) throw new HttpError(429, 'TOO_MANY_OTP', 'Too many codes requested. Please try again later.');
  }
  const ref = await sendOtp(c.env, phone);
  const requestId = randomId();
  await c.env.DB.prepare('INSERT INTO otp_requests (id, phone, ip, provider_ref, created_at) VALUES (?,?,?,?,?)')
    .bind(requestId, phone, ip, ref, t)
    .run();
  return json({ requestId, phone, resendAfterSeconds: 30, demo: ref === 'demo' });
}

async function otpVerify(c: Ctx) {
  const body = await readJson<{ requestId: string; code: string; device?: string }>(c.req);
  const code = String(body.code ?? '').replace(/\D/g, '');
  if (code.length < 4 || code.length > 8) throw new HttpError(400, 'INVALID_CODE');
  const r = await c.env.DB.prepare('SELECT * FROM otp_requests WHERE id = ?')
    .bind(String(body.requestId ?? ''))
    .first<{ id: string; phone: string; provider_ref: string; attempts: number; verified: number; created_at: number }>();
  if (!r || r.verified) throw new HttpError(400, 'INVALID_REQUEST');
  if (now() - r.created_at > OTP_TTL_MS) throw new HttpError(400, 'OTP_EXPIRED', 'Code expired. Request a new one.');
  if (r.attempts >= OTP_MAX_ATTEMPTS) throw new HttpError(429, 'TOO_MANY_ATTEMPTS', 'Too many wrong attempts. Request a new code.');
  await c.env.DB.prepare('UPDATE otp_requests SET attempts = attempts + 1 WHERE id = ?').bind(r.id).run();

  const result = await checkOtp(c.env, r.provider_ref, code);
  if (result === 'expired') throw new HttpError(400, 'OTP_EXPIRED', 'Code expired. Request a new one.');
  if (result !== 'ok') throw new HttpError(400, 'WRONG_OTP', 'Incorrect code');
  await c.env.DB.prepare('UPDATE otp_requests SET verified = 1 WHERE id = ?').bind(r.id).run();

  let user = await c.env.DB.prepare('SELECT * FROM users WHERE phone = ?').bind(r.phone).first<User>();
  const isNew = !user;
  if (!user) {
    const t = now();
    const id = randomId();
    await c.env.DB.prepare('INSERT INTO users (id, phone, created_at, updated_at) VALUES (?,?,?,?)').bind(id, r.phone, t, t).run();
    user = (await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first<User>())!;
  }
  const token = await createSession(c.env, user.id, 'otp', body.device ?? '');
  const pk = await c.env.DB.prepare('SELECT COUNT(*) AS n FROM passkeys WHERE user_id = ?').bind(user.id).first<{ n: number }>();
  return json({ token, isNew, hasPasskey: (pk?.n ?? 0) > 0, user: publicUser(user) });
}

// --------------------------------------------------------------- passkeys
function rp(c: Ctx) {
  const rpID = c.url.hostname;
  return { rpID, origins: [...androidOrigins(c.env), `https://${rpID}`] };
}

async function saveChallenge(env: Env, kind: 'register' | 'login', challenge: string, userId: string | null) {
  const id = randomId();
  await env.DB.prepare('DELETE FROM challenges WHERE expires_at < ?').bind(now()).run();
  await env.DB.prepare('INSERT INTO challenges (id, user_id, challenge, kind, expires_at) VALUES (?,?,?,?,?)')
    .bind(id, userId, challenge, kind, now() + CHALLENGE_TTL_MS)
    .run();
  return id;
}

async function takeChallenge(env: Env, id: string, kind: 'register' | 'login') {
  const row = await env.DB.prepare('SELECT * FROM challenges WHERE id = ? AND kind = ?')
    .bind(id, kind)
    .first<{ challenge: string; user_id: string | null; expires_at: number }>();
  await env.DB.prepare('DELETE FROM challenges WHERE id = ?').bind(id).run();
  if (!row || row.expires_at < now()) throw new HttpError(400, 'CHALLENGE_EXPIRED');
  return row;
}

async function passkeyRegisterOptions(c: Ctx) {
  const { user } = await requireUser(c);
  const { rpID } = rp(c);
  const existing = await c.env.DB.prepare('SELECT id, transports FROM passkeys WHERE user_id = ?')
    .bind(user.id)
    .all<{ id: string; transports: string }>();
  const options = await generateRegistrationOptions({
    rpName: c.env.RP_NAME,
    rpID,
    userID: new Uint8Array(new TextEncoder().encode(user.id)),
    userName: user.phone,
    userDisplayName: user.name || user.phone,
    attestationType: 'none',
    excludeCredentials: existing.results.map((p) => ({ id: p.id, transports: JSON.parse(p.transports) as AuthenticatorTransportFuture[] })),
    authenticatorSelection: { residentKey: 'required', requireResidentKey: true, userVerification: 'preferred', authenticatorAttachment: 'platform' },
  });
  const flowId = await saveChallenge(c.env, 'register', options.challenge, user.id);
  return json({ flowId, options });
}

async function passkeyRegisterVerify(c: Ctx) {
  const { user } = await requireUser(c);
  const body = await readJson<{ flowId: string; response: RegistrationResponseJSON; device?: string }>(c.req);
  const ch = await takeChallenge(c.env, body.flowId, 'register');
  if (ch.user_id !== user.id) throw new HttpError(400, 'CHALLENGE_MISMATCH');
  const { rpID, origins } = rp(c);
  let v;
  try {
    v = await verifyRegistrationResponse({
      response: body.response,
      expectedChallenge: ch.challenge,
      expectedOrigin: origins,
      expectedRPID: rpID,
      requireUserVerification: false,
    });
  } catch (e) {
    throw new HttpError(400, 'PASSKEY_INVALID', (e as Error).message);
  }
  if (!v.verified) throw new HttpError(400, 'PASSKEY_INVALID');
  const info = v.registrationInfo;
  const cred = info.credential;
  await c.env.DB.prepare(
    'INSERT OR REPLACE INTO passkeys (id, user_id, public_key, counter, transports, device, created_at, aaguid, device_type, backed_up) VALUES (?,?,?,?,?,?,?,?,?,?)',
  )
    .bind(
      cred.id,
      user.id,
      b64url(cred.publicKey),
      cred.counter,
      JSON.stringify(cred.transports ?? body.response?.response?.transports ?? []),
      (body.device ?? '').slice(0, 80),
      now(),
      info.aaguid ?? '',
      info.credentialDeviceType ?? '',
      info.credentialBackedUp ? 1 : 0,
    )
    .run();
  return json({ ok: true });
}

async function passkeyLoginOptions(c: Ctx) {
  const { rpID } = rp(c);
  // If the app sends the typed phone number, point the phone at that user's
  // exact passkeys (more reliable on some Android builds than discovery).
  let allow: { id: string; transports?: AuthenticatorTransportFuture[] }[] = [];
  const body = await c.req.json<{ countryCode?: string; number?: string }>().catch(() => ({}) as { countryCode?: string; number?: string });
  if (body.countryCode && body.number) {
    try {
      const phone = normalisePhone(body.countryCode, body.number);
      const rows = await c.env.DB.prepare('SELECT p.id, p.transports FROM passkeys p JOIN users u ON u.id = p.user_id WHERE u.phone = ?')
        .bind(phone)
        .all<{ id: string; transports: string }>();
      allow = rows.results.map((r) => ({ id: r.id, transports: JSON.parse(r.transports) as AuthenticatorTransportFuture[] }));
    } catch {
      allow = [];
    }
  }
  const options = await generateAuthenticationOptions({ rpID, userVerification: 'preferred', allowCredentials: allow });
  const flowId = await saveChallenge(c.env, 'login', options.challenge, null);
  return json({ flowId, options });
}

async function passkeyLoginVerify(c: Ctx) {
  const body = await readJson<{ flowId: string; response: AuthenticationResponseJSON; device?: string }>(c.req);
  const ch = await takeChallenge(c.env, body.flowId, 'login');
  const pk = await c.env.DB.prepare('SELECT * FROM passkeys WHERE id = ?')
    .bind(body.response?.id ?? '')
    .first<{ id: string; user_id: string; public_key: string; counter: number; transports: string }>();
  if (!pk) throw new HttpError(404, 'PASSKEY_NOT_FOUND', 'This passkey is no longer registered. Log in with OTP.');
  const { rpID, origins } = rp(c);
  let v;
  try {
    v = await verifyAuthenticationResponse({
      response: body.response,
      expectedChallenge: ch.challenge,
      expectedOrigin: origins,
      expectedRPID: rpID,
      requireUserVerification: false,
      credential: {
        id: pk.id,
        publicKey: fromB64url(pk.public_key),
        counter: pk.counter,
        transports: JSON.parse(pk.transports) as AuthenticatorTransportFuture[],
      },
    });
  } catch (e) {
    throw new HttpError(400, 'PASSKEY_INVALID', (e as Error).message);
  }
  if (!v.verified) throw new HttpError(400, 'PASSKEY_INVALID');
  await c.env.DB.prepare('UPDATE passkeys SET counter = ?, last_used_at = ? WHERE id = ?')
    .bind(v.authenticationInfo.newCounter, now(), pk.id)
    .run();
  const user = (await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(pk.user_id).first<User>())!;
  const token = await createSession(c.env, user.id, 'passkey', body.device ?? '');
  return json({ token, isNew: false, hasPasskey: true, user: publicUser(user) });
}

// --------------------------------------------------------------- fingerprint (device key) login
async function deviceKeyRegister(c: Ctx) {
  const { user } = await requireUser(c);
  const b = await readJson<{ publicKey: string; device?: string }>(c.req);
  let raw: Uint8Array;
  try {
    raw = fromB64url(String(b.publicKey ?? ''));
  } catch {
    throw new HttpError(400, 'INVALID_KEY');
  }
  if (raw.length !== 32) throw new HttpError(400, 'INVALID_KEY');
  const id = randomId();
  await c.env.DB.prepare('INSERT INTO device_keys (id, user_id, public_key, device, created_at) VALUES (?,?,?,?,?)')
    .bind(id, user.id, b64url(raw), (b.device ?? '').slice(0, 80), now())
    .run();
  return json({ keyId: id });
}

async function deviceKeyChallenge(c: Ctx) {
  const b = await readJson<{ keyId: string }>(c.req);
  const k = await c.env.DB.prepare('SELECT id FROM device_keys WHERE id = ?').bind(String(b.keyId ?? '')).first();
  if (!k) throw new HttpError(404, 'DEVICE_KEY_NOT_FOUND', 'Fingerprint login is not set up for this phone anymore. Log in with OTP.');
  const challenge = randomId(32);
  const flowId = await saveChallenge(c.env, 'login', challenge, `dk:${b.keyId}`);
  return json({ flowId, challenge });
}

async function deviceKeyVerify(c: Ctx) {
  const b = await readJson<{ flowId: string; keyId: string; signature: string; device?: string }>(c.req);
  const ch = await takeChallenge(c.env, String(b.flowId ?? ''), 'login');
  if (ch.user_id !== `dk:${b.keyId}`) throw new HttpError(400, 'CHALLENGE_MISMATCH');
  const k = await c.env.DB.prepare('SELECT * FROM device_keys WHERE id = ?')
    .bind(b.keyId)
    .first<{ id: string; user_id: string; public_key: string }>();
  if (!k) throw new HttpError(404, 'DEVICE_KEY_NOT_FOUND', 'Fingerprint login is not set up for this phone anymore. Log in with OTP.');
  let ok = false;
  try {
    const key = await crypto.subtle.importKey('raw', fromB64url(k.public_key), { name: 'Ed25519' }, false, ['verify']);
    ok = await crypto.subtle.verify({ name: 'Ed25519' }, key, fromB64url(String(b.signature ?? '')), new TextEncoder().encode(ch.challenge));
  } catch {
    ok = false;
  }
  if (!ok) throw new HttpError(401, 'BAD_SIGNATURE', 'Fingerprint login failed. Log in with OTP.');
  await c.env.DB.prepare('UPDATE device_keys SET last_used_at = ? WHERE id = ?').bind(now(), k.id).run();
  const user = (await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(k.user_id).first<User>())!;
  const token = await createSession(c.env, user.id, 'passkey', b.device ?? '');
  return json({ token, isNew: false, hasPasskey: true, user: publicUser(user) });
}

async function deviceKeyDelete(c: Ctx, id: string) {
  const { user } = await requireUser(c);
  await c.env.DB.prepare('DELETE FROM device_keys WHERE id = ? AND user_id = ?').bind(id, user.id).run();
  return json({ ok: true });
}

// --------------------------------------------------------------- profile & devices
async function me(c: Ctx) {
  const { user } = await requireUser(c);
  const pk = await c.env.DB.prepare('SELECT COUNT(*) AS n FROM passkeys WHERE user_id = ?').bind(user.id).first<{ n: number }>();
  return json({ user: publicUser(user), hasPasskey: (pk?.n ?? 0) > 0 });
}

async function updateMe(c: Ctx) {
  const { user } = await requireUser(c);
  const b = await readJson<{ name?: string; username?: string; about?: string }>(c.req);
  const name = (b.name ?? user.name).trim().slice(0, 60);
  const about = (b.about ?? user.about).trim().slice(0, 140);
  let username = b.username === undefined ? user.username : b.username.trim().toLowerCase();
  if (username === '') username = null;
  if (username && !/^[a-z0-9._]{3,20}$/.test(username)) throw new HttpError(400, 'INVALID_USERNAME');
  if (username && username !== user.username) {
    const taken = await c.env.DB.prepare('SELECT 1 FROM users WHERE username = ? AND id != ?').bind(username, user.id).first();
    if (taken) throw new HttpError(409, 'USERNAME_TAKEN', 'This username is already taken');
  }
  await c.env.DB.prepare('UPDATE users SET name = ?, username = ?, about = ?, updated_at = ? WHERE id = ?')
    .bind(name, username, about, now(), user.id)
    .run();
  return json({ user: publicUser({ ...user, name, username, about }) });
}

async function usernameAvailable(c: Ctx) {
  const u = (c.url.searchParams.get('u') ?? '').toLowerCase();
  if (!/^[a-z0-9._]{3,20}$/.test(u)) return json({ available: false, reason: 'INVALID' });
  const taken = await c.env.DB.prepare('SELECT 1 FROM users WHERE username = ?').bind(u).first();
  return json({ available: !taken });
}

async function listSessions(c: Ctx) {
  const { user, sessionId } = await requireUser(c);
  const rows = await c.env.DB.prepare('SELECT id, device, method, created_at, last_seen_at FROM sessions WHERE user_id = ? ORDER BY last_seen_at DESC')
    .bind(user.id)
    .all();
  return json({ sessions: rows.results.map((r) => ({ ...r, current: r.id === sessionId })) });
}

async function logout(c: Ctx) {
  const { sessionId } = await requireUser(c);
  await c.env.DB.prepare('DELETE FROM sessions WHERE id = ?').bind(sessionId).run();
  return json({ ok: true });
}

async function revokeSession(c: Ctx, id: string) {
  const { user } = await requireUser(c);
  await c.env.DB.prepare('DELETE FROM sessions WHERE id = ? AND user_id = ?').bind(id, user.id).run();
  return json({ ok: true });
}

async function resetPasskeys(c: Ctx) {
  const { user } = await requireUser(c);
  await c.env.DB.prepare('DELETE FROM passkeys WHERE user_id = ?').bind(user.id).run();
  return json({ ok: true });
}

async function deleteAccount(c: Ctx) {
  const { user } = await requireUser(c);
  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM sessions WHERE user_id = ?').bind(user.id),
    c.env.DB.prepare('DELETE FROM passkeys WHERE user_id = ?').bind(user.id),
    c.env.DB.prepare('DELETE FROM device_keys WHERE user_id = ?').bind(user.id),
    c.env.DB.prepare('DELETE FROM challenges WHERE user_id = ?').bind(user.id),
    c.env.DB.prepare('DELETE FROM users WHERE id = ?').bind(user.id),
  ]);
  return json({ ok: true });
}

// --------------------------------------------------------------- router
function assetLinks(env: Env) {
  const fingerprints = (env.ANDROID_CERT_SHA256 || '').split(',').map((s) => s.trim()).filter(Boolean);
  return json([
    {
      relation: ['delegate_permission/common.handle_all_urls', 'delegate_permission/common.get_login_creds'],
      target: { namespace: 'android_app', package_name: env.ANDROID_PACKAGE, sha256_cert_fingerprints: fingerprints },
    },
  ]);
}

async function route(c: Ctx): Promise<Response> {
  const { req, url } = c;
  const p = url.pathname.replace(/\/+$/, '') || '/';
  const m = req.method;
  if (m === 'GET' && p === '/.well-known/assetlinks.json') return assetLinks(c.env);
  if (m === 'GET' && p === '/') {
    return json({ name: 'baatly-api', ok: true, otp: otpConfigured(c.env) ? 'messagecentral' : demoMode(c.env) ? 'demo' : 'not-configured', rpId: url.hostname });
  }
  if (m === 'POST' && p === '/v1/auth/otp/send') return otpSend(c);
  if (m === 'POST' && p === '/v1/auth/otp/verify') return otpVerify(c);
  if (m === 'POST' && p === '/v1/auth/passkey/register/options') return passkeyRegisterOptions(c);
  if (m === 'POST' && p === '/v1/auth/passkey/register/verify') return passkeyRegisterVerify(c);
  if (m === 'POST' && p === '/v1/auth/passkey/login/options') return passkeyLoginOptions(c);
  if (m === 'POST' && p === '/v1/auth/passkey/login/verify') return passkeyLoginVerify(c);
  if (m === 'POST' && p === '/v1/auth/logout') return logout(c);
  if (m === 'GET' && p === '/v1/me') return me(c);
  if (m === 'PATCH' && p === '/v1/me') return updateMe(c);
  if (m === 'DELETE' && p === '/v1/me') return deleteAccount(c);
  if (m === 'GET' && p === '/v1/username/available') return usernameAvailable(c);
  if (m === 'GET' && p === '/v1/me/sessions') return listSessions(c);
  if (m === 'DELETE' && p === '/v1/me/passkeys') return resetPasskeys(c);
  if (m === 'POST' && p === '/v1/auth/device/register') return deviceKeyRegister(c);
  if (m === 'POST' && p === '/v1/auth/device/challenge') return deviceKeyChallenge(c);
  if (m === 'POST' && p === '/v1/auth/device/verify') return deviceKeyVerify(c);
  const dk = p.match(/^\/v1\/me\/device-keys\/([\w-]+)$/);
  if (m === 'DELETE' && dk) return deviceKeyDelete(c, dk[1]);
  const s = p.match(/^\/v1\/me\/sessions\/([\w-]+)$/);
  if (m === 'DELETE' && s) return revokeSession(c, s[1]);
  throw new HttpError(404, 'NOT_FOUND');
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    try {
      return await route({ req, env, url: new URL(req.url) });
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.code, message: e.message }, e.status);
      console.error(e);
      return json({ error: 'SERVER_ERROR', message: 'Something went wrong. Please try again.' }, 500);
    }
  },
};
