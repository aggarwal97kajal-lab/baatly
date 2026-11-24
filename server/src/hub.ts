import { DurableObject } from 'cloudflare:workers';
import { presenceFor } from './privacy';
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
