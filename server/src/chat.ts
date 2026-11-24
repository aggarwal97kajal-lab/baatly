import { notify, pushConfigured } from './fcm';
import { cleanPrivacy, presenceFor, publicView } from './privacy';
import { Env, HttpError, fromB64url, json, now, randomId, readJson } from './util';

type Me = { id: string; phone: string; name: string; username: string | null; about: string };
type Ctx = { req: Request; env: Env; url: URL };

const MAX_BODY = 64 * 1024;

function hub(env: Env, userId: string) {
  return env.HUB.get(env.HUB.idFromName(userId));
}

/** Pushes to live sockets; returns how many phones got it live. */
export async function push(env: Env, to: string, event: unknown): Promise<number> {
  try {
    const r = await hub(env, to).fetch('https://hub/push', { method: 'POST', body: JSON.stringify(event) });
    return ((await r.json()) as { live: number }).live ?? 0;
  } catch (e) {
    console.error('push failed', e);
    return 0;
  }
}

/** Store an event for `to` and push it live if they are connected. */
async function deliver(env: Env, to: string, event: Record<string, unknown>) {
  const id = randomId();
  const ev = { ...event, id, at: now() };
  await env.DB.prepare('INSERT INTO inbox (id, to_user, event, created_at) VALUES (?,?,?,?)')
    .bind(id, to, JSON.stringify(ev), now())
    .run();
  const live = await push(env, to, ev);
  return { ...ev, live };
}

async function userExists(env: Env, id: string) {
  return !!(await env.DB.prepare('SELECT id FROM users WHERE id = ?').bind(id).first());
}

/** Accepts numbers as saved in a phone book and returns E.164, or null. */
function e164(raw: string): string | null {
  let s = String(raw ?? '').trim();
  const plus = s.startsWith('+');
  s = s.replace(/\D/g, '');
  if (!s) return null;
  if (plus) return s.length >= 8 && s.length <= 15 ? `+${s}` : null;
  if (s.startsWith('00')) return `+${s.slice(2)}`;
  if (s.length === 11 && s.startsWith('0')) s = s.slice(1);
  if (s.length === 10 && /^[6-9]/.test(s)) return `+91${s}`;
  if (s.length === 12 && s.startsWith('91')) return `+${s}`;
  return null;
}

export async function chatRoute(c: Ctx, me: Me, m: string, p: string, sessionId: string): Promise<Response | null> {
  const env = c.env;

  if (m === 'PUT' && p === '/v1/keys') {
    const b = await readJson<{ x25519: string }>(c.req);
    let raw: Uint8Array;
    try {
      raw = fromB64url(String(b.x25519 ?? ''));
    } catch {
      throw new HttpError(400, 'INVALID_KEY');
    }
    if (raw.length !== 32) throw new HttpError(400, 'INVALID_KEY');
    await env.DB.prepare(
      'INSERT INTO user_keys (user_id, x25519, updated_at) VALUES (?,?,?) ON CONFLICT(user_id) DO UPDATE SET x25519 = excluded.x25519, updated_at = excluded.updated_at',
    )
      .bind(me.id, b.x25519, now())
      .run();
    return json({ ok: true });
  }

  if (m === 'POST' && p === '/v1/contacts/match') {
    const b = await readJson<{ numbers: string[] }>(c.req);
    const list = Array.isArray(b.numbers) ? b.numbers.slice(0, 5000) : [];
    const want = new Map<string, string>(); // e164 -> as sent
    for (const n of list) {
      const e = e164(n);
      if (e && e !== me.phone) want.set(e, n);
    }
    const phones = [...want.keys()];
    const out: unknown[] = [];
    for (let i = 0; i < phones.length; i += 90) {
      const chunk = phones.slice(i, i + 90);
      const q = `SELECT u.id, u.phone, u.name, u.username, u.about, u.photo_ver, k.x25519 FROM users u LEFT JOIN user_keys k ON k.user_id = u.id WHERE u.phone IN (${chunk.map(() => '?').join(',')})`;
      const r = await env.DB.prepare(q).bind(...chunk).all<{ id: string; about: string; photo_ver: number }>();
      for (const row of r.results) out.push(await publicView(env, row, me.id));
    }
    // The uploaded phone book is not stored. We only remember which BAATLY
    // users are in it, so "My contacts" privacy options can be enforced.
    const ids = (out as { id: string }[]).map((u) => u.id);
    const stmts = [env.DB.prepare('DELETE FROM user_contacts WHERE user_id = ?').bind(me.id)];
    for (const id of ids) stmts.push(env.DB.prepare('INSERT OR IGNORE INTO user_contacts (user_id, contact_id) VALUES (?,?)').bind(me.id, id));
    for (let i = 0; i < stmts.length; i += 50) await env.DB.batch(stmts.slice(i, i + 50));
    return json({ users: out });
  }

  const um = p.match(/^\/v1\/users\/([\w-]+)$/);
  if (m === 'GET' && um) {
    const row = await env.DB.prepare(
      'SELECT u.id, u.phone, u.name, u.username, u.about, u.photo_ver, k.x25519 FROM users u LEFT JOIN user_keys k ON k.user_id = u.id WHERE u.id = ?',
    )
      .bind(um[1])
      .first<{ id: string; about: string; photo_ver: number }>();
    if (!row) throw new HttpError(404, 'USER_NOT_FOUND');
    return json({ user: await publicView(env, row, me.id) });
  }

  const ph = p.match(/^\/v1\/users\/([\w-]+)\/photo$/);
  if (m === 'GET' && ph) {
    const row = await env.DB.prepare('SELECT id, photo, photo_ver, about FROM users WHERE id = ?').bind(ph[1]).first<{ id: string; photo: string | null; photo_ver: number; about: string }>();
    if (!row || !row.photo) throw new HttpError(404, 'NO_PHOTO');
    const v = await publicView(env, row, me.id);
    if (!v.photo_ver) throw new HttpError(404, 'NO_PHOTO');
    return json({ photo: row.photo, ver: row.photo_ver });
  }

  if (m === 'PUT' && p === '/v1/me/photo') {
    const b = await readJson<{ photo: string }>(c.req);
    const photo = String(b.photo ?? '');
    if (photo.length < 100 || photo.length > 700_000) throw new HttpError(413, 'PHOTO_TOO_LARGE', 'This photo is too large.');
    await env.DB.prepare('UPDATE users SET photo = ?, photo_ver = photo_ver + 1 WHERE id = ?').bind(photo, me.id).run();
    const r = await env.DB.prepare('SELECT photo_ver FROM users WHERE id = ?').bind(me.id).first<{ photo_ver: number }>();
    return json({ ver: r?.photo_ver ?? 1 });
  }

  if (m === 'DELETE' && p === '/v1/me/photo') {
    await env.DB.prepare('UPDATE users SET photo = NULL, photo_ver = 0 WHERE id = ?').bind(me.id).run();
    return json({ ok: true });
  }

  if (m === 'GET' && p === '/v1/me/privacy') {
    const r = await env.DB.prepare('SELECT privacy FROM users WHERE id = ?').bind(me.id).first<{ privacy: string }>();
    let v: unknown = {};
    try {
      v = JSON.parse(r?.privacy || '{}');
    } catch {}
    return json({ privacy: cleanPrivacy(v) });
  }

  if (m === 'PUT' && p === '/v1/me/privacy') {
    const b = await readJson<{ privacy: unknown }>(c.req);
    const v = cleanPrivacy(b.privacy);
    await env.DB.prepare('UPDATE users SET privacy = ? WHERE id = ?').bind(JSON.stringify(v), me.id).run();
    return json({ privacy: v });
  }

  const pm = p.match(/^\/v1\/users\/([\w-]+)\/presence$/);
  if ((m === 'GET' || m === 'POST') && pm) {
    const h = hub(env, pm[1]);
    // POST = "I have this chat open": get pushed online/offline changes instantly.
    if (m === 'POST') await h.fetch('https://hub/watch', { method: 'POST', body: JSON.stringify({ watcher: me.id }) });
    const r = (await (await h.fetch('https://hub/presence')).json()) as { online: boolean; lastSeen: number | null };
    return json(await presenceFor(env, pm[1], me.id, r.online, r.lastSeen));
  }

  if (m === 'POST' && p === '/v1/messages') {
    const b = await readJson<{ to: string; msgId: string; body: string }>(c.req);
    const to = String(b.to ?? '');
    const body = String(b.body ?? '');
    const msgId = String(b.msgId ?? '').slice(0, 64);
    if (!msgId || !body) throw new HttpError(400, 'BAD_MESSAGE');
    if (body.length > MAX_BODY) throw new HttpError(413, 'MESSAGE_TOO_LARGE');
    if (to === me.id || !(await userExists(env, to))) throw new HttpError(404, 'USER_NOT_FOUND');
    const ev = await deliver(env, to, { type: 'msg', from: me.id, msgId, body });
    if (ev.live === 0 && pushConfigured(env)) {
      try {
        await notify(env, to, me.name || me.phone, 'New message', { type: 'msg', chat: me.id });
      } catch (e) {
        console.error('notify failed', e);
      }
    }
    return json({ ok: true, at: ev.at });
  }

  if (m === 'POST' && p === '/v1/receipts') {
    const b = await readJson<{ to: string; msgIds: string[]; status: string }>(c.req);
    const status = b.status === 'read' ? 'read' : 'delivered';
    const ids = (Array.isArray(b.msgIds) ? b.msgIds : []).map(String).slice(0, 500);
    if (!ids.length || !(await userExists(env, String(b.to ?? '')))) return json({ ok: true });
    await deliver(env, b.to, { type: 'receipt', from: me.id, msgIds: ids, status });
    return json({ ok: true });
  }

  if (m === 'POST' && p === '/v1/typing') {
    const b = await readJson<{ to: string; typing: boolean }>(c.req);
    await push(env, String(b.to ?? ''), { type: 'typing', from: me.id, typing: !!b.typing });
    return json({ ok: true });
  }

  if (m === 'GET' && p === '/v1/inbox') {
    const r = await env.DB.prepare('SELECT event FROM inbox WHERE to_user = ? ORDER BY created_at LIMIT 500').bind(me.id).all<{ event: string }>();
    return json({ events: r.results.map((x) => JSON.parse(x.event)) });
  }

  if (m === 'POST' && p === '/v1/inbox/ack') {
    const b = await readJson<{ ids: string[] }>(c.req);
    const ids = (Array.isArray(b.ids) ? b.ids : []).map(String).slice(0, 500);
    for (let i = 0; i < ids.length; i += 90) {
      const chunk = ids.slice(i, i + 90);
      await env.DB.prepare(`DELETE FROM inbox WHERE to_user = ? AND id IN (${chunk.map(() => '?').join(',')})`)
        .bind(me.id, ...chunk)
        .run();
    }
    return json({ ok: true });
  }

  if (m === 'PUT' && p === '/v1/push/token') {
    const b = await readJson<{ token: string }>(c.req);
    const token = String(b.token ?? '');
    if (token.length < 20 || token.length > 4096) throw new HttpError(400, 'BAD_TOKEN');
    await env.DB.prepare(
      'INSERT INTO push_tokens (token, user_id, session_id, updated_at) VALUES (?,?,?,?) ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id, session_id = excluded.session_id, updated_at = excluded.updated_at',
    )
      .bind(token, me.id, sessionId, now())
      .run();
    return json({ ok: true, configured: pushConfigured(env) });
  }

  if (m === 'GET' && p === '/v1/ws') {
    if (c.req.headers.get('upgrade')?.toLowerCase() !== 'websocket') throw new HttpError(426, 'UPGRADE_REQUIRED');
    const req = new Request(c.req);
    req.headers.set('x-user', me.id);
    return hub(env, me.id).fetch(req);
  }

  return null;
}
