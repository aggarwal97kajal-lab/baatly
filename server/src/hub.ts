import { DurableObject } from 'cloudflare:workers';
import type { Env } from './util';

/**
 * One instance per user. Holds that user's live WebSocket(s) and pushes
 * events to them. Uses hibernation, so idle connections cost nothing.
 */
export class UserHub extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  async fetch(req: Request): Promise<Response> {
    const url = new URL(req.url);
    if (req.headers.get('upgrade')?.toLowerCase() === 'websocket') {
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1]);
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    if (url.pathname === '/push') {
      const body = await req.text();
      let n = 0;
      for (const ws of this.ctx.getWebSockets()) {
        try {
          ws.send(body);
          n++;
        } catch {}
      }
      return Response.json({ live: n });
    }
    if (url.pathname === '/presence') {
      const online = this.ctx.getWebSockets().length > 0;
      const lastSeen = (await this.ctx.storage.get<number>('lastSeen')) ?? null;
      return Response.json({ online, lastSeen });
    }
    return new Response('not found', { status: 404 });
  }

  async webSocketClose(ws: WebSocket, code: number) {
    await this.ctx.storage.put('lastSeen', Date.now());
    try {
      ws.close(code === 1005 ? 1000 : code);
    } catch {}
  }

  async webSocketError() {
    await this.ctx.storage.put('lastSeen', Date.now());
  }
}
