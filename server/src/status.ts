import { push } from './chat';
import { blocked } from './safety';
import { Env, HttpError, json, now, randomId, readJson } from './util';

type Me = { id: string };
type Ctx = { req: Request; env: Env; url: URL };

const TTL = 24 * 60 * 60 * 1000;
const MAX_BODY = 3 * 1024 * 1024; // base64 chars (~2.2 MB photo)
const MAX_VIEWERS = 5000;

export async function statusRoute(c: Ctx, me: Me, m: string, p: string): Promise<Response | null> {
  const env = c.env;
  const t = now();

  if (m === 'POST' && p === '/v1/status') {
    const b = await readJson<{ body: string; keys: Record<string, string>; allowShare?: boolean }>(c.req);
    const body = String(b.body ?? '');
    if (!body) throw new HttpError(400, 'BAD_STATUS');
    if (body.length > MAX_BODY) throw new HttpError(413, 'STATUS_TOO_LARGE', 'This photo is too large. Try a smaller one.');
    const all = Object.entries(b.keys ?? {}).filter(([v, k]) => typeof v === 'string' && typeof k === 'string' && k.length < 2000);
    const keys: [string, string][] = [];
    for (const kv of all) if (kv[0] === me.id || !(await blocked(env, me.id, kv[0]))) keys.push(kv);
    if (!keys.some(([v]) => v === me.id)) throw new HttpError(400, 'OWNER_KEY_MISSING');
    if (keys.length > MAX_VIEWERS + 1) throw new HttpError(400, 'TOO_MANY_VIEWERS');
    const id = randomId();
    const stmts = [
      env.DB.prepare('INSERT INTO statuses (id, owner_id, body, allow_share, created_at, expires_at) VALUES (?,?,?,?,?,?)').bind(
        id,
        me.id,
        body,
        b.allowShare === false ? 0 : 1,
        t,
        t + TTL,
      ),
    ];
    for (const [viewer, sealed] of keys) {
      stmts.push(env.DB.prepare('INSERT OR REPLACE INTO status_keys (status_id, viewer_id, sealed) VALUES (?,?,?)').bind(id, viewer, sealed));
    }
    for (let i = 0; i < stmts.length; i += 50) await env.DB.batch(stmts.slice(i, i + 50));
    // Tell viewers who are online right now, so it shows up immediately.
    const viewers = keys.map(([v]) => v).filter((v) => v !== me.id);
    for (let i = 0; i < viewers.length; i += 20) {
      await Promise.all(viewers.slice(i, i + 20).map((v) => push(env, v, { type: 'status', from: me.id, id })));
    }
    return json({ id, createdAt: t, expiresAt: t + TTL });
  }

  // Statuses other people shared with me (newest last).
  if (m === 'GET' && p === '/v1/status/feed') {
    const r = await env.DB.prepare(
      `SELECT s.id, s.owner_id, s.allow_share, s.created_at, k.sealed, u.name, u.phone, uk.x25519,
              EXISTS(SELECT 1 FROM status_views v WHERE v.status_id = s.id AND v.viewer_id = ?) AS viewed
         FROM status_keys k
         JOIN statuses s ON s.id = k.status_id
         JOIN users u ON u.id = s.owner_id
         LEFT JOIN user_keys uk ON uk.user_id = s.owner_id
        WHERE k.viewer_id = ? AND s.owner_id != ? AND s.expires_at > ?
        ORDER BY s.created_at
        LIMIT 1000`,
    )
      .bind(me.id, me.id, me.id, t)
      .all();
    return json({ statuses: r.results });
  }

  if (m === 'GET' && p === '/v1/status/mine') {
    const r = await env.DB.prepare(
      `SELECT s.id, s.created_at, s.allow_share, k.sealed,
              (SELECT COUNT(*) FROM status_views v WHERE v.status_id = s.id) AS views
         FROM statuses s
         JOIN status_keys k ON k.status_id = s.id AND k.viewer_id = s.owner_id
        WHERE s.owner_id = ? AND s.expires_at > ?
        ORDER BY s.created_at`,
    )
      .bind(me.id, t)
      .all();
    return json({ statuses: r.results });
  }

  const one = p.match(/^\/v1\/status\/([\w-]+)(\/(body|view|views))?$/);
  if (!one) return null;
  const [, id, , sub] = one;
  const st = await env.DB.prepare('SELECT id, owner_id, expires_at FROM statuses WHERE id = ?').bind(id).first<{ id: string; owner_id: string; expires_at: number }>();
  if (!st || st.expires_at <= t) throw new HttpError(404, 'STATUS_GONE', 'This status is no longer available.');
  const mine = st.owner_id === me.id;
  const allowed =
    mine || !!(await env.DB.prepare('SELECT 1 FROM status_keys WHERE status_id = ? AND viewer_id = ?').bind(id, me.id).first());
  if (!allowed) throw new HttpError(404, 'STATUS_GONE', 'This status is no longer available.');

  if (m === 'GET' && sub === 'body') {
    const row = await env.DB.prepare('SELECT body FROM statuses WHERE id = ?').bind(id).first<{ body: string }>();
    return json({ body: row!.body });
  }
  if (m === 'POST' && sub === 'view') {
    if (!mine) {
      const r = await env.DB.prepare('INSERT OR IGNORE INTO status_views (status_id, viewer_id, at) VALUES (?,?,?)').bind(id, me.id, t).run();
      if (r.meta.changes > 0) await push(env, st.owner_id, { type: 'status_view', statusId: id, viewer: me.id, at: t });
    }
    return json({ ok: true });
  }
  if (m === 'GET' && sub === 'views') {
    if (!mine) throw new HttpError(403, 'NOT_YOURS');
    const r = await env.DB.prepare('SELECT viewer_id, at FROM status_views WHERE status_id = ? ORDER BY at DESC').bind(id).all();
    return json({ views: r.results });
  }
  if (m === 'DELETE' && !sub) {
    if (!mine) throw new HttpError(403, 'NOT_YOURS');
    const viewers = await env.DB.prepare('SELECT viewer_id FROM status_keys WHERE status_id = ? AND viewer_id != ?').bind(id, me.id).all<{ viewer_id: string }>();
    await deleteStatuses(env, [id]);
    await Promise.all(viewers.results.slice(0, 200).map((v) => push(env, v.viewer_id, { type: 'status', from: me.id, id, deleted: true })));
    return json({ ok: true });
  }
  return null;
}

export async function deleteStatuses(env: Env, ids: string[]) {
  for (let i = 0; i < ids.length; i += 30) {
    const chunk = ids.slice(i, i + 30);
    const q = chunk.map(() => '?').join(',');
    await env.DB.batch([
      env.DB.prepare(`DELETE FROM status_keys WHERE status_id IN (${q})`).bind(...chunk),
      env.DB.prepare(`DELETE FROM status_views WHERE status_id IN (${q})`).bind(...chunk),
      env.DB.prepare(`DELETE FROM statuses WHERE id IN (${q})`).bind(...chunk),
    ]);
  }
}

/** Hourly: remove statuses older than 24 hours. */
export async function expireStatuses(env: Env) {
  const r = await env.DB.prepare('SELECT id FROM statuses WHERE expires_at <= ? LIMIT 2000').bind(now()).all<{ id: string }>();
  await deleteStatuses(env, r.results.map((x) => x.id));
}

export async function deleteUserStatuses(env: Env, userId: string) {
  const r = await env.DB.prepare('SELECT id FROM statuses WHERE owner_id = ?').bind(userId).all<{ id: string }>();
  await deleteStatuses(env, r.results.map((x) => x.id));
  await env.DB.prepare('DELETE FROM status_keys WHERE viewer_id = ?').bind(userId).run();
  await env.DB.prepare('DELETE FROM status_views WHERE viewer_id = ?').bind(userId).run();
}
