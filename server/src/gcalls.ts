import { push } from './chat';
import { notify, pushConfigured } from './fcm';
import { limit } from './safety';
import { Env, HttpError, json, now, readJson } from './util';

type Me = { id: string; name: string; phone: string };
type Ctx = { req: Request; env: Env; url: URL; later?: (p: Promise<unknown>) => void };

/** Everyone sends to everyone, so keep it small enough for a phone. */
export const MAX_IN_CALL = 4;

type Row = { id: string; group_id: string; creator: string; video: number; created_at: number; ended_at: number | null };

async function groupMembers(env: Env, gid: string) {
  if (gid.startsWith('adhoc:')) {
    const a = await env.DB.prepare('SELECT user_id FROM adhoc_call_members WHERE call_id = ?').bind(gid.slice(6)).all<{ user_id: string }>();
    return a.results.map((x) => x.user_id);
  }
  const r = await env.DB.prepare('SELECT user_id FROM group_members WHERE group_id = ?').bind(gid).all<{ user_id: string }>();
  return r.results.map((x) => x.user_id);
}

async function inCall(env: Env, id: string) {
  const r = await env.DB.prepare('SELECT user_id FROM group_call_members WHERE call_id = ? AND left_at IS NULL').bind(id).all<{ user_id: string }>();
  return r.results.map((x) => x.user_id);
}

export async function groupCallRoute(c: Ctx, me: Me, m: string, p: string): Promise<Response | null> {
  const env = c.env;
  const t = now();
  const bg = (x: Promise<unknown>) => (c.later ? c.later(x) : x.catch(() => {}));

  // "Add person" on a 1:1 call: a small call between chosen people, no group needed.
  if (m === 'POST' && p === '/v1/gcalls/adhoc') {
    const b = await readJson<{ people: string[]; callId: string; video?: boolean; upgrade?: string; upgradePeer?: string }>(c.req);
    const id = String(b.callId ?? '').slice(0, 64);
    if (!id.startsWith('grp-')) throw new HttpError(400, 'BAD_CALL');
    const people = [...new Set((b.people ?? []).map(String))].filter((u) => u !== me.id).slice(0, MAX_IN_CALL - 1);
    if (!people.length) throw new HttpError(400, 'BAD_CALL');
    await limit(env, 'gcall', me.id, 20, 600);
    const gid = `adhoc:${id}`;
    const stmts = [
      env.DB.prepare('INSERT INTO group_calls (id, group_id, creator, video, created_at) VALUES (?,?,?,?,?)').bind(id, gid, me.id, b.video ? 1 : 0, t),
      ...[me.id, ...people].map((u) => env.DB.prepare('INSERT OR IGNORE INTO adhoc_call_members (call_id, user_id) VALUES (?,?)').bind(id, u)),
    ];
    await env.DB.batch(stmts);
    const upgrade = String(b.upgrade ?? '');
    bg(
      Promise.all(
        people.map(async (u) => {
          const live = await push(env, u, { type: 'gcall', action: 'ring', callId: id, groupId: gid, from: me.id, video: !!b.video, upgrade: u === b.upgradePeer ? upgrade : '', name: me.name || me.phone });
          if (pushConfigured(env) && !(upgrade && u === b.upgradePeer)) {
            try {
              await notify(env, u, me.name || me.phone, b.video ? 'Group video call' : 'Group voice call', {
                type: 'call', callId: id, from: me.id, group: gid, video: b.video ? '1' : '0', live: String(live),
              });
            } catch {}
          }
        }),
      ),
    );
    return json({ callId: id, groupId: gid });
  }

  // Start a call in a group (or join the one already running there).
  if (m === 'POST' && p === '/v1/gcalls') {
    const b = await readJson<{ groupId: string; callId: string; video?: boolean }>(c.req);
    const gid = String(b.groupId ?? '');
    const members = await groupMembers(env, gid);
    if (!members.includes(me.id)) throw new HttpError(404, 'GROUP_NOT_FOUND');
    const running = await env.DB.prepare('SELECT * FROM group_calls WHERE group_id = ? AND ended_at IS NULL AND created_at > ? ORDER BY created_at DESC LIMIT 1')
      .bind(gid, t - 6 * 3600_000)
      .first<Row>();
    if (running && (await inCall(env, running.id)).length > 0) return json({ callId: running.id, video: running.video === 1, existing: true });
    await limit(env, 'gcall', me.id, 20, 600);
    const id = String(b.callId ?? '').slice(0, 64);
    if (!id.startsWith('grp-')) throw new HttpError(400, 'BAD_CALL');
    await env.DB.prepare('INSERT INTO group_calls (id, group_id, creator, video, created_at) VALUES (?,?,?,?,?)').bind(id, gid, me.id, b.video ? 1 : 0, t).run();
    const g = await env.DB.prepare('SELECT name FROM groups WHERE id = ?').bind(gid).first<{ name: string }>();
    const others = members.filter((u) => u !== me.id);
    bg(
      Promise.all(
        others.map(async (u) => {
          const live = await push(env, u, { type: 'gcall', action: 'ring', callId: id, groupId: gid, from: me.id, video: !!b.video });
          if (pushConfigured(env)) {
            try {
              await notify(env, u, g?.name || 'Group call', `${me.name || me.phone} · ${b.video ? 'group video call' : 'group voice call'}`, {
                type: 'call',
                callId: id,
                from: me.id,
                group: gid,
                video: b.video ? '1' : '0',
                live: String(live),
              });
            } catch {}
          }
        }),
      ),
    );
    return json({ callId: id, video: !!b.video, existing: false });
  }

  const g = p.match(/^\/v1\/gcalls\/(grp-[\w-]+)(\/(join|leave|signal))?$/);
  if (!g) return null;
  const call = await env.DB.prepare('SELECT * FROM group_calls WHERE id = ?').bind(g[1]).first<Row>();
  if (!call) throw new HttpError(404, 'CALL_NOT_FOUND');
  const members = await groupMembers(env, call.group_id);
  if (!members.includes(me.id)) throw new HttpError(404, 'CALL_NOT_FOUND');
  const action = g[3];

  if (m === 'GET' && !action) {
    return json({ call: { id: call.id, groupId: call.group_id, video: call.video === 1, ended: call.ended_at != null, creator: call.creator, people: await inCall(env, call.id) } });
  }

  if (m === 'POST' && action === 'join') {
    if (call.ended_at) throw new HttpError(410, 'CALL_ENDED', 'This call has ended.');
    const people = (await inCall(env, call.id)).filter((u) => u !== me.id);
    if (people.length >= MAX_IN_CALL) throw new HttpError(409, 'CALL_FULL', `Group calls can have up to ${MAX_IN_CALL} people.`);
    await env.DB.prepare(
      'INSERT INTO group_call_members (call_id, user_id, joined_at) VALUES (?,?,?) ON CONFLICT(call_id, user_id) DO UPDATE SET joined_at = excluded.joined_at, left_at = NULL',
    )
      .bind(call.id, me.id, t)
      .run();
    bg(Promise.all(people.map((u) => push(env, u, { type: 'gcall', action: 'joined', callId: call.id, from: me.id }))));
    return json({ people, video: call.video === 1, groupId: call.group_id });
  }

  if (m === 'POST' && action === 'leave') {
    await env.DB.prepare('UPDATE group_call_members SET left_at = ? WHERE call_id = ? AND user_id = ?').bind(t, call.id, me.id).run();
    const people = await inCall(env, call.id);
    if (people.length === 0 && !call.ended_at) await env.DB.prepare('UPDATE group_calls SET ended_at = ? WHERE id = ?').bind(t, call.id).run();
    // Nobody picked up and the caller hung up: stop everyone's ringing.
    const targets = people.length === 0 ? members.filter((u) => u !== me.id) : people;
    bg(Promise.all(targets.map((u) => push(env, u, { type: 'gcall', action: people.length === 0 ? 'ended' : 'left', callId: call.id, from: me.id }))));
    return json({ ok: true });
  }

  if (m === 'POST' && action === 'signal') {
    const b = await readJson<{ to: string; kind: string; data: string }>(c.req);
    const to = String(b.to ?? '');
    const kind = String(b.kind ?? '');
    const data = String(b.data ?? '');
    if (!['offer', 'answer'].includes(kind) || data.length > 60_000) throw new HttpError(400, 'BAD_SIGNAL');
    if (!members.includes(to)) throw new HttpError(404, 'USER_NOT_FOUND');
    await push(env, to, { type: 'gcall', action: kind, callId: call.id, from: me.id, data });
    return json({ ok: true });
  }
  return null;
}
