import { push } from './chat';
import { limit } from './safety';
import { Env, HttpError, json, now, randomId, readJson } from './util';

type Me = { id: string; name: string; phone: string };
type Ctx = { req: Request; env: Env; url: URL; later?: (p: Promise<unknown>) => void };
type Ch = { id: string; name: string; description: string; owner: string; followers: number; last_post: number; created_at: number };

const pub = (c: Ch, me: string, following: boolean) => ({
  id: c.id,
  name: c.name,
  description: c.description,
  followers: c.followers,
  lastPost: c.last_post,
  mine: c.owner === me,
  following,
});

export async function channelRoute(c: Ctx, me: Me, m: string, p: string): Promise<Response | null> {
  const env = c.env;
  const t = now();
  const bg = (x: Promise<unknown>) => (c.later ? c.later(x) : x.catch(() => {}));

  if (m === 'POST' && p === '/v1/channels') {
    const b = await readJson<{ name: string; description?: string }>(c.req);
    const name = String(b.name ?? '').trim().slice(0, 60);
    if (name.length < 2) throw new HttpError(400, 'BAD_NAME', 'Give your channel a name');
    await limit(env, 'channel', me.id, 5, 86400);
    const id = randomId(12);
    await env.DB.batch([
      env.DB.prepare('INSERT INTO channels (id, name, description, owner, followers, created_at) VALUES (?,?,?,?,1,?)').bind(id, name, String(b.description ?? '').slice(0, 500), me.id, t),
      env.DB.prepare('INSERT INTO channel_followers (channel_id, user_id, at) VALUES (?,?,?)').bind(id, me.id, t),
    ]);
    const ch = (await env.DB.prepare('SELECT * FROM channels WHERE id = ?').bind(id).first<Ch>())!;
    return json({ channel: pub(ch, me.id, true) });
  }

  if (m === 'GET' && p === '/v1/channels/mine') {
    const r = await env.DB.prepare(
      `SELECT c.*, (SELECT text FROM channel_posts WHERE channel_id = c.id ORDER BY created_at DESC LIMIT 1) AS last_text
       FROM channels c JOIN channel_followers f ON f.channel_id = c.id WHERE f.user_id = ? ORDER BY c.last_post DESC LIMIT 200`,
    ).bind(me.id).all<Ch & { last_text: string | null }>();
    return json({ channels: r.results.map((x) => ({ ...pub(x, me.id, true), lastText: x.last_text ?? '' })) });
  }

  if (m === 'GET' && p === '/v1/channels/explore') {
    const q = (c.url.searchParams.get('q') ?? '').trim().toLowerCase().slice(0, 40);
    const r = q
      ? await env.DB.prepare('SELECT * FROM channels WHERE lower(name) LIKE ? ORDER BY followers DESC LIMIT 50').bind(`%${q}%`).all<Ch>()
      : await env.DB.prepare('SELECT * FROM channels ORDER BY followers DESC, last_post DESC LIMIT 50').all<Ch>();
    const ids = r.results.map((x) => x.id);
    const mine = ids.length
      ? await env.DB.prepare(`SELECT channel_id FROM channel_followers WHERE user_id = ? AND channel_id IN (${ids.map(() => '?').join(',')})`).bind(me.id, ...ids).all<{ channel_id: string }>()
      : { results: [] as { channel_id: string }[] };
    const f = new Set(mine.results.map((x) => x.channel_id));
    return json({ channels: r.results.map((x) => pub(x, me.id, f.has(x.id))) });
  }

  const g = p.match(/^\/v1\/channels\/([\w-]+)(?:\/(follow|posts)(?:\/([\w-]+)(?:\/(react))?)?)?$/);
  if (!g) return null;
  const ch = await env.DB.prepare('SELECT * FROM channels WHERE id = ?').bind(g[1]).first<Ch>();
  if (!ch) throw new HttpError(404, 'CHANNEL_NOT_FOUND', 'This channel no longer exists');
  const owner = ch.owner === me.id;
  const [, , sub, postId, react] = g;

  if (m === 'GET' && !sub) {
    const following = !!(await env.DB.prepare('SELECT 1 FROM channel_followers WHERE channel_id = ? AND user_id = ?').bind(ch.id, me.id).first());
    const before = Number(c.url.searchParams.get('before') ?? 0) || t + 1;
    const posts = await env.DB.prepare('SELECT * FROM channel_posts WHERE channel_id = ? AND created_at < ? ORDER BY created_at DESC LIMIT 50')
      .bind(ch.id, before)
      .all<{ id: string; text: string; media: string | null; created_at: number }>();
    const ids = posts.results.map((x) => x.id);
    const reacts = ids.length
      ? await env.DB.prepare(`SELECT post_id, emoji, COUNT(*) AS n, SUM(user_id = ?) AS mine FROM channel_reactions WHERE post_id IN (${ids.map(() => '?').join(',')}) GROUP BY post_id, emoji`)
          .bind(me.id, ...ids)
          .all<{ post_id: string; emoji: string; n: number; mine: number }>()
      : { results: [] as { post_id: string; emoji: string; n: number; mine: number }[] };
    const byPost = new Map<string, { e: string; n: number; mine: boolean }[]>();
    for (const r of reacts.results) {
      const l = byPost.get(r.post_id) ?? [];
      l.push({ e: r.emoji, n: r.n, mine: r.mine > 0 });
      byPost.set(r.post_id, l);
    }
    return json({
      channel: pub(ch, me.id, following),
      posts: posts.results.map((x) => ({ id: x.id, text: x.text, media: x.media ? JSON.parse(x.media) : null, at: x.created_at, reactions: byPost.get(x.id) ?? [] })),
    });
  }

  if (m === 'DELETE' && !sub) {
    if (!owner) throw new HttpError(403, 'NOT_OWNER');
    await env.DB.batch([
      env.DB.prepare('DELETE FROM channel_reactions WHERE post_id IN (SELECT id FROM channel_posts WHERE channel_id = ?)').bind(ch.id),
      env.DB.prepare('DELETE FROM channel_posts WHERE channel_id = ?').bind(ch.id),
      env.DB.prepare('DELETE FROM channel_followers WHERE channel_id = ?').bind(ch.id),
      env.DB.prepare('DELETE FROM channels WHERE id = ?').bind(ch.id),
    ]);
    return json({ ok: true });
  }

  if (sub === 'follow' && (m === 'POST' || m === 'DELETE')) {
    if (m === 'POST') {
      const r = await env.DB.prepare('INSERT OR IGNORE INTO channel_followers (channel_id, user_id, at) VALUES (?,?,?)').bind(ch.id, me.id, t).run();
      if (r.meta.changes) await env.DB.prepare('UPDATE channels SET followers = followers + 1 WHERE id = ?').bind(ch.id).run();
    } else {
      if (owner) throw new HttpError(400, 'OWNER', "You can't unfollow your own channel");
      const r = await env.DB.prepare('DELETE FROM channel_followers WHERE channel_id = ? AND user_id = ?').bind(ch.id, me.id).run();
      if (r.meta.changes) await env.DB.prepare('UPDATE channels SET followers = MAX(0, followers - 1) WHERE id = ?').bind(ch.id).run();
    }
    return json({ ok: true });
  }

  if (sub === 'posts' && m === 'POST' && !postId) {
    if (!owner) throw new HttpError(403, 'NOT_OWNER', 'Only the channel admin can post');
    const b = await readJson<{ text?: string; media?: unknown }>(c.req);
    const text = String(b.text ?? '').slice(0, 4000);
    const media = b.media ? JSON.stringify(b.media).slice(0, 20_000) : null;
    if (!text.trim() && !media) throw new HttpError(400, 'EMPTY');
    await limit(env, 'chpost', me.id, 200, 86400);
    const id = randomId(12);
    await env.DB.batch([
      env.DB.prepare('INSERT INTO channel_posts (id, channel_id, text, media, created_at) VALUES (?,?,?,?,?)').bind(id, ch.id, text, media, t),
      env.DB.prepare('UPDATE channels SET last_post = ? WHERE id = ?').bind(t, ch.id),
    ]);
    // Tell followers who are online (no notification, like WhatsApp channels).
    bg(
      (async () => {
        const f = await env.DB.prepare('SELECT user_id FROM channel_followers WHERE channel_id = ? AND user_id != ? LIMIT 1000').bind(ch.id, me.id).all<{ user_id: string }>();
        await Promise.all(f.results.map((x) => push(env, x.user_id, { type: 'channel', channel: ch.id }).catch(() => 0)));
      })(),
    );
    return json({ post: { id, text, media: b.media ?? null, at: t, reactions: [] } });
  }

  if (sub === 'posts' && postId && !react && m === 'DELETE') {
    if (!owner) throw new HttpError(403, 'NOT_OWNER');
    await env.DB.batch([
      env.DB.prepare('DELETE FROM channel_reactions WHERE post_id = ?').bind(postId),
      env.DB.prepare('DELETE FROM channel_posts WHERE id = ? AND channel_id = ?').bind(postId, ch.id),
    ]);
    return json({ ok: true });
  }

  if (sub === 'posts' && postId && react && m === 'POST') {
    const b = await readJson<{ emoji?: string | null }>(c.req);
    const e = b.emoji ? String(b.emoji).slice(0, 16) : null;
    if (e) await env.DB.prepare('INSERT INTO channel_reactions (post_id, user_id, emoji) VALUES (?,?,?) ON CONFLICT(post_id, user_id) DO UPDATE SET emoji = excluded.emoji').bind(postId, me.id, e).run();
    else await env.DB.prepare('DELETE FROM channel_reactions WHERE post_id = ? AND user_id = ?').bind(postId, me.id).run();
    return json({ ok: true });
  }
  return null;
}
