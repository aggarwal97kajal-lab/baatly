import { push } from './chat';
import { notify, pushConfigured } from './fcm';
import { Env, HttpError, json, now, readJson } from './util';

type Me = { id: string; name: string; phone: string };
type Ctx = { req: Request; env: Env; url: URL };

const RING_MS = 50_000;

/** STUN always; Cloudflare TURN relay too when TURN_KEY_ID / TURN_KEY_TOKEN are set. */
async function iceServers(env: Env) {
  const servers: unknown[] = [{ urls: ['stun:stun.cloudflare.com:3478', 'stun:stun.l.google.com:19302'] }];
  if (env.TURN_KEY_ID && env.TURN_KEY_TOKEN) {
    try {
      const r = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${env.TURN_KEY_ID}/credentials/generate-ice-servers`, {
        method: 'POST',
        headers: { authorization: `Bearer ${env.TURN_KEY_TOKEN}`, 'content-type': 'application/json' },
        body: JSON.stringify({ ttl: 86400 }),
      });
      if (r.ok) {
        const j = (await r.json()) as { iceServers?: unknown };
        if (Array.isArray(j.iceServers)) servers.push(...j.iceServers);
        else if (j.iceServers) servers.push(j.iceServers);
      }
    } catch (e) {
      console.error('TURN credentials failed', e);
    }
  }
  return servers;
}

export async function callRoute(c: Ctx, me: Me, m: string, p: string): Promise<Response | null> {
  const env = c.env;
  const t = now();

  if (m === 'GET' && p === '/v1/calls/ice') return json({ iceServers: await iceServers(env), turn: !!(env.TURN_KEY_ID && env.TURN_KEY_TOKEN) });

  if (m === 'POST' && p === '/v1/calls') {
    const b = await readJson<{ to: string; callId: string; video?: boolean; offer: string }>(c.req);
    const to = String(b.to ?? '');
    const id = String(b.callId ?? '').slice(0, 64);
    const offer = String(b.offer ?? '');
    if (!id || !offer || offer.length > 60_000) throw new HttpError(400, 'BAD_CALL');
    if (to === me.id || !(await env.DB.prepare('SELECT 1 FROM users WHERE id = ?').bind(to).first())) throw new HttpError(404, 'USER_NOT_FOUND');
    await env.DB.prepare('INSERT INTO calls (id, caller, callee, video, offer, created_at) VALUES (?,?,?,?,?,?)').bind(id, me.id, to, b.video ? 1 : 0, offer, t).run();
    const live = await push(env, to, { type: 'call', action: 'offer', callId: id, from: me.id, video: !!b.video, offer });
    if (pushConfigured(env)) {
      try {
        await notify(env, to, me.name || me.phone, b.video ? 'Incoming video call' : 'Incoming voice call', {
          type: 'call',
          callId: id,
          from: me.id,
          video: b.video ? '1' : '0',
          phone: me.phone,
          live: String(live),
        });
      } catch {}
    }
    return json({ ok: true });
  }

  const g = p.match(/^\/v1\/calls\/([\w-]+)(\/signal)?$/);
  if (!g) return null;
  const call = await env.DB.prepare('SELECT * FROM calls WHERE id = ?').bind(g[1]).first<{
    id: string; caller: string; callee: string; video: number; offer: string; status: string; created_at: number;
  }>();
  if (!call || (call.caller !== me.id && call.callee !== me.id)) throw new HttpError(404, 'CALL_NOT_FOUND');
  const other = call.caller === me.id ? call.callee : call.caller;

  if (m === 'GET' && !g[2]) {
    const ringing = call.status === 'ringing' && t - call.created_at < RING_MS;
    return json({ call: { id: call.id, caller: call.caller, video: call.video === 1, status: ringing ? 'ringing' : call.status, offer: ringing ? call.offer : null } });
  }

  if (m === 'POST' && g[2]) {
    const b = await readJson<{ action: string; data?: string }>(c.req);
    const action = String(b.action ?? '');
    if (!['answer', 'ice', 'end', 'reject', 'ringing', 'busy'].includes(action)) throw new HttpError(400, 'BAD_ACTION');
    if (action === 'answer') await env.DB.prepare("UPDATE calls SET status = 'answered', answered_at = ? WHERE id = ?").bind(t, call.id).run();
    if (action === 'reject' || action === 'busy') await env.DB.prepare("UPDATE calls SET status = 'rejected', ended_at = ? WHERE id = ?").bind(t, call.id).run();
    if (action === 'end') {
      const status = call.status === 'answered' ? 'ended' : 'missed';
      await env.DB.prepare('UPDATE calls SET status = ?, ended_at = ? WHERE id = ?').bind(status, t, call.id).run();
    }
    await push(env, other, { type: 'call', action, callId: call.id, from: me.id, data: b.data ?? null });
    return json({ ok: true });
  }
  return null;
}
