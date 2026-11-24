import { Env, HttpError } from './util';

/**
 * Message Central VerifyNow (v3) client.
 * Docs: https://www.messagecentral.com/product/verify-now/api-india
 *  1. GET  /auth/v1/authentication/token?customerId&key=<base64 password>&scope=NEW
 *  2. POST /verification/v3/send?countryCode&customerId&flowType=SMS&mobileNumber&otpLength
 *  3. GET  /verification/v3/validateOtp?verificationId&code      (header: authToken)
 * Message Central generates, delivers and checks the OTP — we never see or store it.
 */
const BASE = 'https://cpaas.messagecentral.com';

let cachedToken: { token: string; at: number } | null = null;

export function otpConfigured(env: Env): boolean {
  return Boolean(env.MC_CUSTOMER_ID && env.MC_PASSWORD);
}

export function demoMode(env: Env): boolean {
  // Demo only when the provider is NOT configured and explicitly allowed.
  return !otpConfigured(env) && env.DEMO_OTP === 'true';
}

async function token(env: Env): Promise<string> {
  if (cachedToken && Date.now() - cachedToken.at < 20 * 60 * 1000) return cachedToken.token;
  const key = btoa(env.MC_PASSWORD!);
  const url = `${BASE}/auth/v1/authentication/token?customerId=${encodeURIComponent(env.MC_CUSTOMER_ID!)}&key=${encodeURIComponent(key)}&scope=NEW&country=91`;
  const r = await fetch(url, { headers: { accept: '*/*' } });
  const body = (await r.json().catch(() => ({}))) as { token?: string };
  if (!r.ok || !body.token) throw new HttpError(502, 'OTP_PROVIDER_AUTH_FAILED');
  cachedToken = { token: body.token, at: Date.now() };
  return body.token;
}

/** Returns the provider's verification id. */
export async function sendOtp(env: Env, e164: string): Promise<string> {
  if (demoMode(env)) return 'demo';
  if (!otpConfigured(env)) throw new HttpError(503, 'OTP_NOT_CONFIGURED');
  const m = e164.match(/^\+(91)(\d{10})$/) ?? e164.match(/^\+(\d{1,3})(\d{6,14})$/);
  if (!m) throw new HttpError(400, 'INVALID_PHONE');
  const [, cc, num] = m;
  const url = `${BASE}/verification/v3/send?countryCode=${cc}&customerId=${encodeURIComponent(env.MC_CUSTOMER_ID!)}&flowType=SMS&mobileNumber=${num}&otpLength=6`;
  const r = await fetch(url, { method: 'POST', headers: { authToken: await token(env) } });
  const body = (await r.json().catch(() => ({}))) as { responseCode?: number; data?: { verificationId?: string | number } };
  const vid = body.data?.verificationId;
  if (body.responseCode === 506) throw new HttpError(429, 'OTP_ALREADY_SENT');
  if (body.responseCode === 800) throw new HttpError(429, 'OTP_LIMIT_REACHED');
  if (!r.ok || body.responseCode !== 200 || vid == null) {
    if (r.status === 401) cachedToken = null;
    throw new HttpError(502, 'OTP_SEND_FAILED');
  }
  return String(vid);
}

export type OtpResult = 'ok' | 'wrong' | 'expired';

export async function checkOtp(env: Env, providerRef: string, code: string): Promise<OtpResult> {
  if (providerRef === 'demo') return demoMode(env) && code === '123456' ? 'ok' : 'wrong';
  if (!otpConfigured(env)) throw new HttpError(503, 'OTP_NOT_CONFIGURED');
  const url = `${BASE}/verification/v3/validateOtp?verificationId=${encodeURIComponent(providerRef)}&code=${encodeURIComponent(code)}`;
  const r = await fetch(url, { headers: { authToken: await token(env) } });
  const body = (await r.json().catch(() => ({}))) as { responseCode?: number; data?: { verificationStatus?: string } };
  if (body.responseCode === 200 && body.data?.verificationStatus === 'VERIFICATION_COMPLETED') return 'ok';
  if (body.responseCode === 703) return 'ok'; // already verified
  if (body.responseCode === 705) return 'expired';
  if (body.responseCode === 702 || body.responseCode === 700) return 'wrong';
  if (r.status === 401) cachedToken = null;
  throw new HttpError(502, 'OTP_CHECK_FAILED');
}
