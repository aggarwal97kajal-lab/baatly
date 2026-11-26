import { Env, HttpError, json, now, randomId } from './util';

type Me = { id: string };
type Ctx = { req: Request; env: Env; url: URL };

const MAX = 64 * 1024 * 1024; // single-request upload (small files)
const BIG_MAX = 2 * 1024 * 1024 * 1024 + 64 * 1024 * 1024; // 2 GB (+ encryption overhead), sent in parts
const PART_MAX = 12 * 1024 * 1024; // one encrypted 8 MB chunk per part, with room to spare
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

  // ---------------------------------------------------------------- big files (up to 2 GB), in parts
  if (m === 'POST' && p === '/v1/media/big') {
    const b = (await c.req.json().catch(() => ({}))) as { size?: number };
    const size = Number(b.size ?? 0);
    if (!(size > 0)) throw new HttpError(400, 'EMPTY_FILE');
    if (size > BIG_MAX) throw new HttpError(413, 'FILE_TOO_LARGE', 'Files up to 2 GB can be sent.');
    const id = randomId(18);
    const mp = await env.MEDIA.createMultipartUpload(`m/${id}`, { httpMetadata: { contentType: 'application/octet-stream' } });
    return json({ id, upload: mp.uploadId });
  }
  const bp = p.match(/^\/v1\/media\/big\/([\w-]+)\/(\d{1,5})$/);
  if (m === 'PUT' && bp) {
    const upload = c.url.searchParams.get('u') ?? '';
    const n = Number(bp[2]);
    if (!upload || n < 1 || n > 10000) throw new HttpError(400, 'BAD_PART');
    const len = Number(c.req.headers.get('content-length') ?? '0');
    if (len > PART_MAX) throw new HttpError(413, 'PART_TOO_LARGE');
    const body = await c.req.arrayBuffer();
    if (body.byteLength === 0 || body.byteLength > PART_MAX) throw new HttpError(400, 'BAD_PART');
    const mp = env.MEDIA.resumeMultipartUpload(`m/${bp[1]}`, upload);
    const part = await mp.uploadPart(n, body);
    return json({ etag: part.etag });
  }
  const bd = p.match(/^\/v1\/media\/big\/([\w-]+)\/done$/);
  if (m === 'POST' && bd) {
    const b = (await c.req.json().catch(() => ({}))) as { upload?: string; parts?: { n: number; etag: string }[] };
    const parts = (b.parts ?? []).map((x) => ({ partNumber: Number(x.n), etag: String(x.etag) })).sort((a, z) => a.partNumber - z.partNumber);
    if (!b.upload || !parts.length) throw new HttpError(400, 'BAD_UPLOAD');
    const mp = env.MEDIA.resumeMultipartUpload(`m/${bd[1]}`, b.upload);
    const obj = await mp.complete(parts);
    await env.DB.prepare('INSERT INTO media (id, owner_id, size, created_at) VALUES (?,?,?,?)').bind(bd[1], me.id, obj.size, now()).run();
    return json({ id: bd[1], size: obj.size });
  }
  const ba = p.match(/^\/v1\/media\/big\/([\w-]+)$/);
  if (m === 'DELETE' && ba) {
    const upload = c.url.searchParams.get('u') ?? '';
    if (upload) {
      try {
        await env.MEDIA.resumeMultipartUpload(`m/${ba[1]}`, upload).abort();
      } catch {}
    }
    return json({ ok: true });
  }

  const g = p.match(/^\/v1\/media\/([\w-]+)$/);
  if (m === 'GET' && g) {
    // "Range: bytes=a-b" lets big files come down piece by piece (and resume).
    const rh = c.req.headers.get('range');
    const rm = rh ? /^bytes=(\d+)-(\d+)$/.exec(rh) : null;
    if (rm) {
      const offset = Number(rm[1]);
      const length = Number(rm[2]) - offset + 1;
      if (length <= 0 || length > PART_MAX * 2) throw new HttpError(416, 'BAD_RANGE');
      const obj = await env.MEDIA.get(`m/${g[1]}`, { range: { offset, length } });
      if (!obj) throw new HttpError(404, 'MEDIA_GONE', 'This file is no longer available. Ask them to send it again.');
      const end = Math.min(offset + length, obj.size) - 1;
      return new Response(obj.body, {
        status: 206,
        headers: {
          'content-type': 'application/octet-stream',
          'content-length': String(end - offset + 1),
          'content-range': `bytes ${offset}-${end}/${obj.size}`,
          'cache-control': 'private, max-age=86400',
        },
      });
    }
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
