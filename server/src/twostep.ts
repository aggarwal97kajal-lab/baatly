import { Env, HttpError, json, now, randomId, readJson } from './util';

const RESET_WAIT_MS = 7 * 86400_000;
const TICKET_MS = 15 * 60_000;

function b64(buf: ArrayBuffer | Uint8Array) {
  const u = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let s = '';
  for (const x of u) s += String.fromCharCode(x);
  return btoa(s);
}

export async function hashPin(pin: string, salt: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(pin), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: new TextEncoder().encode(salt), iterations: 100_000 }, key, 256);
  return b64(bits);
}

type Row = { user_id: string; hash: string; salt: string; reset_at: number | null; fails: number; locked_until: number | null };

/** Called after the SMS code is right. Returns a ticket when the PIN is still needed. */
export async function needsPin(env: Env, userId: string, device: string): Promise<{ ticket: string; resetAt: number | null } | null> {
  const r = await env.DB.prepare('SELECT * FROM two_step WHERE user_id = ?').bind(userId).first<Row>();
  if (!r) return null;
  if (r.reset_at != null && r.reset_at <= now()) {
    // Waited 7 days after "Forgot PIN": PIN is switched off.
    await env.DB.prepare('DELETE FROM two_step WHERE user_id = ?').bind(userId).run();
    return null;
  }
  const id = randomId();
  await env.DB.prepare('DELETE FROM pin_tickets WHERE expires_at < ?').bind(now()).run();
  await env.DB.prepare('INSERT INTO pin_tickets (id, user_id, device, expires_at) VALUES (?,?,?,?)').bind(id, userId, device, now() + TICKET_MS).run();
  return { ticket: id, resetAt: r.reset_at };
}

/** POST /v1/auth/pin {ticket, pin} → user id when right. */
export async function checkPinTicket(env: Env, ticket: string, pin: string): Promise<{ userId: string; device: string }> {
  const t = await env.DB.prepare('SELECT * FROM pin_tickets WHERE id = ?').bind(ticket).first<{ user_id: string; device: string; expires_at: number }>();
  if (!t || t.expires_at < now()) throw new HttpError(400, 'TICKET_EXPIRED', 'Please verify your number again.');
  const r = await env.DB.prepare('SELECT * FROM two_step WHERE user_id = ?').bind(t.user_id).first<Row>();
  if (!r) return { userId: t.user_id, device: t.device };
  if (r.locked_until && r.locked_until > now()) {
    const mins = Math.ceil((r.locked_until - now()) / 60000);
    throw new HttpError(429, 'PIN_LOCKED', `Too many wrong PINs. Try again in ${mins} min.`);
  }
  if ((await hashPin(pin, r.salt)) !== r.hash) {
    const fails = r.fails + 1;
    const lock = fails >= 5 ? now() + Math.min(24 * 3600_000, 2 ** (fails - 5) * 3600_000) : null;
    await env.DB.prepare('UPDATE two_step SET fails = ?, locked_until = ? WHERE user_id = ?').bind(fails, lock, t.user_id).run();
    throw new HttpError(400, 'WRONG_PIN', fails >= 5 ? 'Wrong PIN. Locked for a while.' : 'Wrong PIN');
  }
  await env.DB.prepare('UPDATE two_step SET fails = 0, locked_until = NULL, reset_at = NULL WHERE user_id = ?').bind(t.user_id).run();
  await env.DB.prepare('DELETE FROM pin_tickets WHERE id = ?').bind(ticket).run();
  return { userId: t.user_id, device: t.device };
}

/** POST /v1/auth/pin/reset {ticket}: start the 7-day wait. */
export async function startPinReset(env: Env, c: { req: Request }) {
  const b = await readJson<{ ticket: string }>(c.req);
  const t = await env.DB.prepare('SELECT * FROM pin_tickets WHERE id = ?').bind(String(b.ticket ?? '')).first<{ user_id: string; expires_at: number }>();
  if (!t || t.expires_at < now()) throw new HttpError(400, 'TICKET_EXPIRED', 'Please verify your number again.');
  const r = await env.DB.prepare('SELECT reset_at FROM two_step WHERE user_id = ?').bind(t.user_id).first<{ reset_at: number | null }>();
  let at = r?.reset_at ?? null;
  if (r && at == null) {
    at = now() + RESET_WAIT_MS;
    await env.DB.prepare('UPDATE two_step SET reset_at = ? WHERE user_id = ?').bind(at, t.user_id).run();
  }
  return json({ resetAt: at });
}

/** Signed-in: GET/PUT/DELETE /v1/me/two-step */
export async function twoStepRoute(c: { req: Request; env: Env }, userId: string, m: string): Promise<Response> {
  const env = c.env;
  if (m === 'GET') {
    const r = await env.DB.prepare('SELECT reset_at FROM two_step WHERE user_id = ?').bind(userId).first<{ reset_at: number | null }>();
    return json({ enabled: !!r });
  }
  if (m === 'PUT') {
    const b = await readJson<{ pin: string }>(c.req);
    const pin = String(b.pin ?? '');
    if (!/^\d{6}$/.test(pin)) throw new HttpError(400, 'BAD_PIN', 'PIN must be 6 digits');
    const salt = randomId();
    const hash = await hashPin(pin, salt);
    await env.DB.prepare(
      'INSERT INTO two_step (user_id, hash, salt) VALUES (?,?,?) ON CONFLICT(user_id) DO UPDATE SET hash = excluded.hash, salt = excluded.salt, reset_at = NULL, fails = 0, locked_until = NULL',
    ).bind(userId, hash, salt).run();
    return json({ ok: true });
  }
  if (m === 'DELETE') {
    await env.DB.prepare('DELETE FROM two_step WHERE user_id = ?').bind(userId).run();
    return json({ ok: true });
  }
  throw new HttpError(405, 'METHOD');
}
