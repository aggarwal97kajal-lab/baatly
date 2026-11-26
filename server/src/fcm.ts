import type { Env } from './util';

/**
 * Firebase Cloud Messaging (HTTP v1). Credentials come from the
 * FCM_SERVICE_ACCOUNT secret (the service-account JSON from Firebase).
 * Message text is never sent: E2E means the server can't read it.
 */
type ServiceAccount = { project_id: string; client_email: string; private_key: string; token_uri?: string };

let cached: { token: string; exp: number; email: string } | null = null;

function sa(env: Env): ServiceAccount | null {
  if (!env.FCM_SERVICE_ACCOUNT) return null;
  try {
    const j = JSON.parse(env.FCM_SERVICE_ACCOUNT) as ServiceAccount;
    return j.client_email && j.private_key && j.project_id ? j : null;
  } catch {
    return null;
  }
}

export function pushConfigured(env: Env) {
  return sa(env) !== null;
}

const b64u = (b: ArrayBuffer | Uint8Array) => {
  const u = b instanceof Uint8Array ? b : new Uint8Array(b);
  let s = '';
  for (const x of u) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

async function accessToken(a: ServiceAccount): Promise<string> {
  const t = Math.floor(Date.now() / 1000);
  if (cached && cached.email === a.client_email && cached.exp - 60 > t) return cached.token;
  const aud = a.token_uri ?? 'https://oauth2.googleapis.com/token';
  const enc = new TextEncoder();
  const header = b64u(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = b64u(
    enc.encode(JSON.stringify({ iss: a.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud, iat: t, exp: t + 3600 })),
  );
  const pem = a.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (ch) => ch.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(`${header}.${claims}`));
  const r = await fetch(aud, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${header}.${claims}.${b64u(sig)}` }),
  });
  const j = (await r.json()) as { access_token?: string; expires_in?: number; error?: string };
  if (!j.access_token) throw new Error(`FCM auth failed: ${j.error ?? r.status}`);
  cached = { token: j.access_token, exp: t + (j.expires_in ?? 3600), email: a.client_email };
  return j.access_token;
}

/**
 * Wakes every phone of `userId` with a data-only push. The data carries the
 * still-encrypted message, so the phone decrypts it and shows the text itself;
 * Google and the server never see the plain text.
 */
export async function notify(env: Env, userId: string, title: string, body: string, data: Record<string, string>) {
  const a = sa(env);
  if (!a) return;
  if (data.chat) {
    const muted = await env.DB.prepare('SELECT 1 FROM mutes WHERE user_id = ? AND peer_id = ? AND until > ?').bind(userId, data.chat, Date.now()).first();
    if (muted) return;
  }
  const rows = await env.DB.prepare('SELECT token FROM push_tokens WHERE user_id = ?').bind(userId).all<{ token: string }>();
  if (!rows.results.length) return;
  const at = await accessToken(a);
  // "from" is a reserved FCM key (the whole push is rejected), so it travels as "fromId".
  const { from, ...rest } = data;
  const payload: Record<string, string> = { ...rest, acct: userId, title, preview: body };
  if (from !== undefined) payload.fromId = String(from);
  for (const { token } of rows.results) {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${a.project_id}/messages:send`, {
      method: 'POST',
      headers: { authorization: `Bearer ${at}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        message: {
          token,
          data: payload,
          android: { priority: 'HIGH', ttl: '2419200s' },
        },
      }),
    });
    if (r.status === 404 || r.status === 400) {
      const t = await r.text();
      // Only forget the phone when FCM says the token itself is dead, never for a bad payload.
      if (/UNREGISTERED|registration-token-not-registered|not a valid FCM registration token/i.test(t)) {
        await env.DB.prepare('DELETE FROM push_tokens WHERE token = ?').bind(token).run();
      } else {
        console.error('FCM send failed', r.status, t.slice(0, 300));
      }
    } else if (!r.ok) {
      console.error('FCM send failed', r.status, (await r.text()).slice(0, 300));
    }
  }
}
