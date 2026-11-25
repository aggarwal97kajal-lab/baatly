import { DurableObject } from 'cloudflare:workers';
import { chatRoute } from './chat';
import { groupRoute } from './groups';
import { presenceFor } from './privacy';
import { HttpError } from './util';
import type { Env } from './util';

const WATCH_MS = 150_000;

/**
 * One instance per user. Holds that user's live WebSocket(s), pushes events
 * to them, and tells people who have this user's chat open when they go
 * online/offline (instantly, respecting privacy). Uses hibernation.
 */
export class UserHub extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  private openSockets(except?: WebSocket) {
    return this.ctx.getWebSockets().filter((w) => w !== except && w.readyState === WebSocket.OPEN);
  }

  async fetch(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const uid = req.headers.get('x-user');
    if (uid) await this.ctx.storage.put('uid', uid);
    const meHdr = req.headers.get('x-me');
    if (meHdr) {
      try {
        await this.ctx.storage.put('me', JSON.parse(decodeURIComponent(meHdr)));
      } catch {}
    }

    if (req.headers.get('upgrade')?.toLowerCase() === 'websocket') {
      const wasOnline = this.openSockets().length > 0;
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1]);
      if (!wasOnline) this.ctx.waitUntil(this.tellWatchers(true));
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    if (url.pathname === '/push') {
      const body = await req.text();
      let n = 0;
      for (const ws of this.openSockets()) {
        try {
          ws.send(body);
          n++;
        } catch {}
      }
      return Response.json({ live: n });
    }
    if (url.pathname === '/presence') {
      const online = this.openSockets().length > 0;
      const lastSeen = (await this.ctx.storage.get<number>('lastSeen')) ?? null;
      return Response.json({ online, lastSeen });
    }
    if (url.pathname === '/watch') {
      const { watcher } = (await req.json()) as { watcher: string };
      const w = (await this.ctx.storage.get<Record<string, number>>('watchers')) ?? {};
      const t = Date.now();
      for (const k of Object.keys(w)) if (w[k] < t) delete w[k];
      w[watcher] = t + WATCH_MS;
      await this.ctx.storage.put('watchers', w);
      return Response.json({ ok: true });
    }
    return new Response('not found', { status: 404 });
  }

  private async tellWatchers(online: boolean) {
    const uid = await this.ctx.storage.get<string>('uid');
    const w = (await this.ctx.storage.get<Record<string, number>>('watchers')) ?? {};
    if (!uid) return;
    const t = Date.now();
    const lastSeen = online ? null : ((await this.ctx.storage.get<number>('lastSeen')) ?? t);
    await Promise.all(
      Object.entries(w)
        .filter(([, exp]) => exp > t)
        .map(async ([watcher]) => {
          try {
            const p = await presenceFor(this.env, uid, watcher, online, lastSeen);
            await this.env.HUB.get(this.env.HUB.idFromName(watcher)).fetch('https://hub/push', {
              method: 'POST',
              body: JSON.stringify({ type: 'presence', user: uid, ...p }),
            });
          } catch {}
        }),
    );
  }

  private async closed(ws: WebSocket) {
    await this.ctx.storage.put('lastSeen', Date.now());
    if (this.openSockets(ws).length === 0) await this.tellWatchers(false);
  }

  // ------------------------------------------------------------ fast send
  // The phone sends messages over its open socket. We store the message here
  // (on-disk, instant), answer "accepted" right away (= ✓), then deliver it.
  // If delivery can't finish now, an alarm retries it.
  async webSocketMessage(ws: WebSocket, data: string | ArrayBuffer) {
    if (typeof data !== 'string' || data === 'ping') return;
    let m: { type?: string; rid?: string; path?: string; body?: unknown };
    try {
      m = JSON.parse(data);
    } catch {
      return;
    }
    if (m.type !== 'send' || !m.rid || !m.path) return;
    const path = String(m.path);
    if (path !== '/v1/messages' && !/^\/v1\/groups\/[\w-]+\/messages$/.test(path)) {
      ws.send(JSON.stringify({ type: 'ack', rid: m.rid, ok: false }));
      return;
    }
    const key = `q:${Date.now()}:${m.rid}`;
    await this.ctx.storage.put(key, { rid: m.rid, path, body: m.body, tries: 0 });
    ws.send(JSON.stringify({ type: 'ack', rid: m.rid, ok: true }));
    this.ctx.waitUntil(this.run(key));
  }

  private async run(key: string) {
    const item = await this.ctx.storage.get<{ rid: string; path: string; body: unknown; tries: number }>(key);
    const me = await this.ctx.storage.get<{ id: string; phone: string; name: string; username: string | null; about: string }>('me');
    if (!item || !me) return;
    const url = new URL(`https://hub${item.path}`);
    const c = {
      req: new Request(url, { method: 'POST', body: JSON.stringify(item.body ?? {}), headers: { 'content-type': 'application/json' } }),
      env: this.env,
      url,
      later: (p: Promise<unknown>) => this.ctx.waitUntil(p.catch(() => {})),
    };
    try {
      if (item.path === '/v1/messages') await chatRoute(c, me, 'POST', item.path, '');
      else await groupRoute(c, me, 'POST', item.path);
      await this.ctx.storage.delete(key);
    } catch (e) {
      const status = e instanceof HttpError ? e.status : 0;
      // Bad request / not allowed: give up and tell the phone.
      if ((status >= 400 && status < 500 && status !== 429) || item.tries >= 8) {
        await this.ctx.storage.delete(key);
        const msgId = (item.body as { msgId?: string })?.msgId;
        const out = JSON.stringify({ type: 'send_failed', rid: item.rid, msgId, error: e instanceof HttpError ? e.code : 'ERROR' });
        for (const w of this.openSockets()) {
          try {
            w.send(out);
          } catch {}
        }
        return;
      }
      item.tries++;
      await this.ctx.storage.put(key, item);
      const at = Date.now() + Math.min(60_000, 2_000 * 2 ** item.tries);
      const cur = await this.ctx.storage.getAlarm();
      if (!cur || cur > at) await this.ctx.storage.setAlarm(at);
    }
  }

  async alarm() {
    const pending = await this.ctx.storage.list({ prefix: 'q:' });
    for (const key of pending.keys()) await this.run(key);
  }

  async webSocketClose(ws: WebSocket, code: number) {
    try {
      ws.close(code === 1005 || code === 1006 ? 1000 : code);
    } catch {}
    await this.closed(ws);
  }

  async webSocketError(ws: WebSocket) {
    await this.closed(ws);
  }
}
