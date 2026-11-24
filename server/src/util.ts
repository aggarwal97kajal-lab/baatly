export interface Env {
  DB: D1Database;
  HUB: DurableObjectNamespace;
  MEDIA?: R2Bucket; // chat media (ciphertext); optional until R2 is enabled
  // vars (wrangler.toml)
  RP_NAME: string;
  ANDROID_PACKAGE: string;
  ANDROID_CERT_SHA256: string; // colon-separated hex, comma-separated if several
  // secrets (wrangler secret put)
  MC_CUSTOMER_ID?: string;
  MC_PASSWORD?: string;
  DEMO_OTP?: string;
  FCM_SERVICE_ACCOUNT?: string;
  TURN_KEY_ID?: string; // Cloudflare Realtime TURN (optional)
  TURN_KEY_TOKEN?: string; // Firebase service-account JSON (secret) // "true" only while Message Central is not configured
}

export class HttpError extends Error {
  constructor(public status: number, public code: string, message?: string) {
    super(message ?? code);
  }
}

export const now = () => Date.now();

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
}

export function randomId(bytes = 16): string {
  const b = crypto.getRandomValues(new Uint8Array(bytes));
  return b64url(b);
}

export function b64url(bytes: Uint8Array): string {
  let s = '';
  for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function fromB64url(s: string): Uint8Array<ArrayBuffer> {
  const pad = s.length % 4 === 0 ? '' : '='.repeat(4 - (s.length % 4));
  const bin = atob(s.replace(/-/g, '+').replace(/_/g, '/') + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function readJson<T>(req: Request): Promise<T> {
  try {
    return (await req.json()) as T;
  } catch {
    throw new HttpError(400, 'BAD_JSON');
  }
}

/** Normalise to E.164. Only India (+91) is strictly validated for now. */
export function normalisePhone(countryCode: string, number: string): string {
  const cc = String(countryCode ?? '').replace(/\D/g, '');
  const n = String(number ?? '').replace(/\D/g, '');
  if (!cc || !n) throw new HttpError(400, 'INVALID_PHONE');
  if (cc === '91' && !/^[6-9]\d{9}$/.test(n)) throw new HttpError(400, 'INVALID_PHONE');
  if (n.length < 6 || n.length > 14) throw new HttpError(400, 'INVALID_PHONE');
  return `+${cc}${n}`;
}

/** Android passkey origins look like "android:apk-key-hash:<b64url sha256 of signing cert>". */
export function androidOrigins(env: Env): string[] {
  return (env.ANDROID_CERT_SHA256 || '')
    .split(',')
    .map((h) => h.trim())
    .filter(Boolean)
    .map((hex) => {
      const bytes = new Uint8Array(hex.split(':').map((x) => parseInt(x, 16)));
      return `android:apk-key-hash:${b64url(bytes)}`;
    });
}

export function clientIp(req: Request): string {
  return req.headers.get('cf-connecting-ip') ?? '';
}
