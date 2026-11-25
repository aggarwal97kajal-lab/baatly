import { Env, HttpError, json } from './util';

type Me = { id: string };
type Ctx = { req: Request; env: Env; url: URL };

type Fmt = { url?: string; width?: number; height?: number };
type Item = { id: number | string; title?: string; file?: Record<string, Record<string, Fmt>> };

/** GIF / sticker search through KLIPY. The key stays on the server. */
export async function gifRoute(c: Ctx, me: Me, m: string, p: string): Promise<Response | null> {
  if (m !== 'GET' || p !== '/v1/gifs') return null;
  const key = c.env.KLIPY_KEY;
  if (!key) throw new HttpError(503, 'GIFS_OFF', 'GIF search is not set up yet.');
  const kind = c.url.searchParams.get('kind') === 'stickers' ? 'stickers' : 'gifs';
  const q = (c.url.searchParams.get('q') ?? '').trim().slice(0, 80);
  const page = Math.max(1, Math.min(50, Number(c.url.searchParams.get('page') ?? '1') || 1));
  // KLIPY wants a stable per-user id; send a hash, not the real one.
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`baatly:${me.id}`)));
  const customer = [...h.slice(0, 12)].map((b) => b.toString(16).padStart(2, '0')).join('');
  const qs = new URLSearchParams({ page: String(page), per_page: '30', customer_id: customer, locale: 'in', content_filter: 'medium' });
  if (q) qs.set('q', q);
  const url = `https://api.klipy.com/api/v1/${encodeURIComponent(key)}/${kind}/${q ? 'search' : 'trending'}?${qs}`;
  const r = await fetch(url, { cf: { cacheTtl: q ? 300 : 900, cacheEverything: true } } as RequestInit);
  if (!r.ok) throw new HttpError(502, 'GIFS_FAILED', "Couldn't load GIFs. Try again.");
  const j = (await r.json()) as { data?: { data?: Item[]; has_next?: boolean } };
  const pick = (it: Item, size: string, fmt: string) => it.file?.[size]?.[fmt];
  const items = (j.data?.data ?? [])
    .map((it) => {
      const full = kind === 'stickers' ? pick(it, 'md', 'webp') ?? pick(it, 'md', 'gif') : pick(it, 'md', 'gif') ?? pick(it, 'hd', 'gif');
      const thumb = pick(it, 'sm', 'webp') ?? pick(it, 'sm', 'gif') ?? pick(it, 'xs', 'gif') ?? full;
      if (!full?.url || !thumb?.url) return null;
      return { id: String(it.id), title: it.title ?? '', url: full.url, thumb: thumb.url, w: full.width ?? 0, h: full.height ?? 0 };
    })
    .filter(Boolean);
  return json({ items, more: !!j.data?.has_next });
}
