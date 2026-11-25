import { Env, HttpError, json, now, randomId, readJson } from './util';

type Me = { id: string };
type Ctx = { req: Request; env: Env; url: URL };

/** Has `a` blocked `b` (or the other way round)? */
export async function blocked(env: Env, a: string, b: string) {
  return !!(await env.DB.prepare('SELECT 1 FROM blocks WHERE (user_id = ? AND blocked_id = ?) OR (user_id = ? AND blocked_id = ?)').bind(a, b, b, a).first());
}

/** Fixed-window limit: at most `max` actions per `windowSec`. */
export async function limit(env: Env, what: string, user: string, max: number, windowSec: number) {
  const win = Math.floor(Date.now() / 1000 / windowSec);
  const k = `${what}:${user}:${win}`;
  const r = await env.DB.prepare(
    'INSERT INTO rate_limits (k, n, expires) VALUES (?, 1, ?) ON CONFLICT(k) DO UPDATE SET n = n + 1 RETURNING n',
  )
    .bind(k, (win + 1) * windowSec * 1000)
    .first<{ n: number }>();
  if ((r?.n ?? 0) > max) throw new HttpError(429, 'SLOW_DOWN', "You're sending too fast. Please wait a moment.");
}

export async function cleanupRateLimits(env: Env) {
  await env.DB.prepare('DELETE FROM rate_limits WHERE expires < ?').bind(now()).run();
}

export async function safetyRoute(c: Ctx, me: Me, m: string, p: string): Promise<Response | null> {
  const env = c.env;
  if (m === 'GET' && p === '/v1/blocks') {
    const r = await env.DB.prepare('SELECT blocked_id FROM blocks WHERE user_id = ?').bind(me.id).all<{ blocked_id: string }>();
    return json({ blocked: r.results.map((x) => x.blocked_id) });
  }
  const b = p.match(/^\/v1\/blocks\/([\w-]+)$/);
  if (b && m === 'PUT') {
    if (b[1] === me.id) throw new HttpError(400, 'BAD_USER');
    await env.DB.prepare('INSERT OR IGNORE INTO blocks (user_id, blocked_id, created_at) VALUES (?,?,?)').bind(me.id, b[1], now()).run();
    return json({ ok: true });
  }
  if (b && m === 'DELETE') {
    await env.DB.prepare('DELETE FROM blocks WHERE user_id = ? AND blocked_id = ?').bind(me.id, b[1]).run();
    return json({ ok: true });
  }
  if (m === 'POST' && p === '/v1/reports') {
    await limit(env, 'report', me.id, 20, 86400);
    const r = await readJson<{ user: string; reason?: string; evidence?: string[]; block?: boolean }>(c.req);
    const user = String(r.user ?? '');
    if (!user || user === me.id) throw new HttpError(400, 'BAD_USER');
    const evidence = (Array.isArray(r.evidence) ? r.evidence : []).map(String).slice(-5).join('\n---\n').slice(0, 5000);
    await env.DB.prepare('INSERT INTO reports (id, reporter, reported, reason, evidence, created_at) VALUES (?,?,?,?,?,?)')
      .bind(randomId(), me.id, user, String(r.reason ?? 'spam').slice(0, 100), evidence, now())
      .run();
    if (r.block) await env.DB.prepare('INSERT OR IGNORE INTO blocks (user_id, blocked_id, created_at) VALUES (?,?,?)').bind(me.id, user, now()).run();
    return json({ ok: true });
  }
  return null;
}
