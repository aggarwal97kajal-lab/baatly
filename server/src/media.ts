import { Env, HttpError, json, now, randomId } from './util';

type Me = { id: string };
type Ctx = { req: Request; env: Env; url: URL };

const MAX = 64 * 1024 * 1024; // 64 MB per file
const KEEP_MS = 30 * 24 * 60 * 60 * 1000; // ciphertext kept 30 days for late downloads

export function mediaConfigured(env: Env) {
  return !!env.MEDIA;
}

export async function mediaRoute(c: Ctx, me: Me, m: string, p: string): Promise<Response | null> {
  const env = c.env;
  if (!env.MEDIA) throw new HttpError(503, 'MEDIA_NOT_CONFIGURED', 'Sending files is not set up on the server yet.');

  if (m === 'POST' && p === '/v1/media') {
    const len = Number(c.req.headers.get('content-length') ?? '0');
    if (len > MAX) throw new HttpError(413, 'FILE_TOO_LARGE', 'Files up to 64 MB can be sent.');
    const body = await c.req.arrayBuffer();
    if (body.byteLength === 0) throw new HttpError(400, 'EMPTY_FILE');
    if (body.byteLength > MAX) throw new HttpError(413, 'FILE_TOO_LARGE', 'Files up to 64 MB can be sent.');
    const id = randomId(18);
    await env.MEDIA.put(`m/${id}`, body, { httpMetadata: { contentType: 'application/octet-stream' } });
    await env.DB.prepare('INSERT INTO media (id, owner_id, size, created_at) VALUES (?,?,?,?)').bind(id, me.id, body.byteLength, now()).run();
    return json({ id, size: body.byteLength });
  }

  const g = p.match(/^\/v1\/media\/([\w-]+)$/);
  if (m === 'GET' && g) {
    const obj = await env.MEDIA.get(`m/${g[1]}`);
    if (!obj) throw new HttpError(404, 'MEDIA_GONE', 'This file is no longer available. Ask them to send it again.');
    return new Response(obj.body, {
      headers: { 'content-type': 'application/octet-stream', 'content-length': String(obj.size), 'cache-control': 'private, max-age=86400' },
    });
  }
  return null;
}

/** Daily-ish cleanup: drop ciphertext older than 30 days. */
export async function expireMedia(env: Env) {
  if (!env.MEDIA) return;
  const r = await env.DB.prepare('SELECT id FROM media WHERE created_at < ? LIMIT 500').bind(now() - KEEP_MS).all<{ id: string }>();
  const ids = r.results.map((x) => x.id);
  if (!ids.length) return;
  await env.MEDIA.delete(ids.map((id) => `m/${id}`));
  for (let i = 0; i < ids.length; i += 50) {
    const chunk = ids.slice(i, i + 50);
    await env.DB.prepare(`DELETE FROM media WHERE id IN (${chunk.map(() => '?').join(',')})`).bind(...chunk).run();
  }
}
