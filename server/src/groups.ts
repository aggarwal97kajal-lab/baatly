import { deliver, push } from './chat';
import { notify, pushConfigured } from './fcm';
import { blocked, limit } from './safety';
import { Env, HttpError, json, now, randomId, readJson } from './util';

type Me = { id: string; name: string; phone: string };
type Ctx = { req: Request; env: Env; url: URL };

const MAX_MEMBERS = 256;

async function membership(env: Env, gid: string, uid: string) {
  return env.DB.prepare('SELECT role FROM group_members WHERE group_id = ? AND user_id = ?').bind(gid, uid).first<{ role: string }>();
}

async function memberIds(env: Env, gid: string) {
  const r = await env.DB.prepare('SELECT user_id FROM group_members WHERE group_id = ?').bind(gid).all<{ user_id: string }>();
  return r.results.map((x) => x.user_id);
}

async function info(env: Env, gid: string) {
  const g = await env.DB.prepare('SELECT id, name, about, photo_ver, created_by, created_at, edit_info, send_messages FROM groups WHERE id = ?').bind(gid).first();
  if (!g) return null;
  const m = await env.DB.prepare(
    `SELECT gm.user_id AS id, gm.role, u.name, u.phone, u.photo_ver, k.x25519
       FROM group_members gm JOIN users u ON u.id = gm.user_id LEFT JOIN user_keys k ON k.user_id = gm.user_id
      WHERE gm.group_id = ? ORDER BY gm.added_at`,
  )
    .bind(gid)
    .all();
  return { ...g, members: m.results };
}

/** Tell members (and anyone just removed) that the group changed. Stored, so offline phones get it too. */
async function groupEvent(env: Env, gid: string, ev: Record<string, unknown>, extra: string[] = []) {
  const ids = new Set([...(await memberIds(env, gid)), ...extra]);
  await Promise.all([...ids].map((u) => deliver(env, u, { type: 'group', group: gid, ...ev })));
}

async function validUsers(env: Env, ids: string[]) {
  const out: string[] = [];
  for (let i = 0; i < ids.length; i += 90) {
    const chunk = ids.slice(i, i + 90);
    const r = await env.DB.prepare(`SELECT id FROM users WHERE id IN (${chunk.map(() => '?').join(',')})`).bind(...chunk).all<{ id: string }>();
    out.push(...r.results.map((x) => x.id));
  }
  return out;
}

export async function groupRoute(c: Ctx, me: Me, m: string, p: string): Promise<Response | null> {
  const env = c.env;
  const t = now();

  if (m === 'POST' && p === '/v1/groups') {
    const b = await readJson<{ name: string; members: string[] }>(c.req);
    const name = String(b.name ?? '').trim().slice(0, 100);
    if (!name) throw new HttpError(400, 'GROUP_NAME_REQUIRED', 'Give the group a name.');
    await limit(env, 'group', me.id, 20, 3600);
    const wanted = [...new Set((Array.isArray(b.members) ? b.members : []).map(String))].filter((x) => x !== me.id);
    if (!wanted.length) throw new HttpError(400, 'NO_MEMBERS', 'Add at least one member.');
    if (wanted.length + 1 > MAX_MEMBERS) throw new HttpError(400, 'TOO_MANY_MEMBERS', `Groups can have up to ${MAX_MEMBERS} members.`);
    const members = await validUsers(env, wanted);
    const id = randomId();
    const stmts = [
      env.DB.prepare('INSERT INTO groups (id, name, created_by, created_at) VALUES (?,?,?,?)').bind(id, name, me.id, t),
      env.DB.prepare('INSERT INTO group_members (group_id, user_id, role, added_at) VALUES (?,?,?,?)').bind(id, me.id, 'admin', t),
      ...members.map((u) => env.DB.prepare('INSERT INTO group_members (group_id, user_id, role, added_at) VALUES (?,?,?,?)').bind(id, u, 'member', t)),
    ];
    for (let i = 0; i < stmts.length; i += 50) await env.DB.batch(stmts.slice(i, i + 50));
    await groupEvent(env, id, { action: 'created', actor: me.id, targets: members, name });
    return json({ group: await info(env, id) });
  }

  if (m === 'GET' && p === '/v1/groups') {
    const r = await env.DB.prepare('SELECT group_id FROM group_members WHERE user_id = ?').bind(me.id).all<{ group_id: string }>();
    const out = [];
    for (const x of r.results) out.push(await info(env, x.group_id));
    return json({ groups: out.filter(Boolean) });
  }

  const g = p.match(/^\/v1\/groups\/([\w-]+)(\/.*)?$/);
  if (!g) return null;
  const gid = g[1];
  const rest = g[2] ?? '';
  const mine = await membership(env, gid, me.id);
  if (!mine) throw new HttpError(404, 'NOT_IN_GROUP', "You're no longer in this group.");
  const admin = mine.role === 'admin';
  const settings = (await env.DB.prepare('SELECT edit_info, send_messages FROM groups WHERE id = ?').bind(gid).first<{ edit_info: string; send_messages: string }>())!;
  const canEdit = admin || settings.edit_info === 'all';

  if (m === 'GET' && rest === '') return json({ group: await info(env, gid) });

  if (m === 'PATCH' && rest === '') {
    if (!canEdit) throw new HttpError(403, 'ADMIN_ONLY', 'Only admins can edit this group\'s info.');
    const b = await readJson<{ name?: string; about?: string }>(c.req);
    if (b.name !== undefined) {
      const name = String(b.name).trim().slice(0, 100);
      if (!name) throw new HttpError(400, 'GROUP_NAME_REQUIRED', 'Give the group a name.');
      await env.DB.prepare('UPDATE groups SET name = ? WHERE id = ?').bind(name, gid).run();
      await groupEvent(env, gid, { action: 'renamed', actor: me.id, name });
    }
    if (b.about !== undefined) {
      await env.DB.prepare('UPDATE groups SET about = ? WHERE id = ?').bind(String(b.about).slice(0, 500), gid).run();
      await groupEvent(env, gid, { action: 'about', actor: me.id });
    }
    return json({ group: await info(env, gid) });
  }

  if (m === 'PATCH' && rest === '/settings') {
    if (!admin) throw new HttpError(403, 'ADMIN_ONLY', 'Only admins can change group settings.');
    const b = await readJson<{ editInfo?: string; sendMessages?: string }>(c.req);
    if (b.editInfo === 'all' || b.editInfo === 'admins') {
      await env.DB.prepare('UPDATE groups SET edit_info = ? WHERE id = ?').bind(b.editInfo, gid).run();
      await groupEvent(env, gid, { action: 'edit_info', actor: me.id, value: b.editInfo });
    }
    if (b.sendMessages === 'all' || b.sendMessages === 'admins') {
      await env.DB.prepare('UPDATE groups SET send_messages = ? WHERE id = ?').bind(b.sendMessages, gid).run();
      await groupEvent(env, gid, { action: 'send_messages', actor: me.id, value: b.sendMessages });
    }
    return json({ group: await info(env, gid) });
  }

  if (m === 'DELETE' && rest === '/photo') {
    if (!canEdit) throw new HttpError(403, 'ADMIN_ONLY', 'Only admins can edit this group\'s info.');
    await env.DB.prepare('UPDATE groups SET photo = NULL, photo_ver = 0 WHERE id = ?').bind(gid).run();
    await groupEvent(env, gid, { action: 'photo_removed', actor: me.id });
    return json({ ok: true });
  }

  if (m === 'PUT' && rest === '/photo') {
    if (!canEdit) throw new HttpError(403, 'ADMIN_ONLY', 'Only admins can edit this group\'s info.');
    const b = await readJson<{ photo: string }>(c.req);
    const photo = String(b.photo ?? '');
    if (photo.length < 100 || photo.length > 1_200_000) throw new HttpError(413, 'PHOTO_TOO_LARGE', 'This photo is too large.');
    await env.DB.prepare('UPDATE groups SET photo = ?, photo_ver = photo_ver + 1 WHERE id = ?').bind(photo, gid).run();
    await groupEvent(env, gid, { action: 'photo', actor: me.id });
    const v = await env.DB.prepare('SELECT photo_ver FROM groups WHERE id = ?').bind(gid).first<{ photo_ver: number }>();
    return json({ ok: true, ver: v?.photo_ver ?? 1 });
  }

  if (m === 'GET' && rest === '/photo') {
    const r = await env.DB.prepare('SELECT photo, photo_ver FROM groups WHERE id = ?').bind(gid).first<{ photo: string | null; photo_ver: number }>();
    if (!r?.photo) throw new HttpError(404, 'NO_PHOTO');
    return json({ photo: r.photo, ver: r.photo_ver });
  }

  if (m === 'POST' && rest === '/members') {
    if (!admin) throw new HttpError(403, 'ADMIN_ONLY', 'Only group admins can add members.');
    const b = await readJson<{ add: string[] }>(c.req);
    const current = new Set(await memberIds(env, gid));
    const add = (await validUsers(env, [...new Set((b.add ?? []).map(String))])).filter((u) => !current.has(u));
    if (current.size + add.length > MAX_MEMBERS) throw new HttpError(400, 'TOO_MANY_MEMBERS', `Groups can have up to ${MAX_MEMBERS} members.`);
    if (add.length) {
      await env.DB.batch(add.map((u) => env.DB.prepare('INSERT OR IGNORE INTO group_members (group_id, user_id, role, added_at) VALUES (?,?,?,?)').bind(gid, u, 'member', t)));
      await groupEvent(env, gid, { action: 'added', actor: me.id, targets: add });
    }
    return json({ group: await info(env, gid) });
  }

  const mm = rest.match(/^\/members\/([\w-]+)$/);
  if (m === 'DELETE' && mm) {
    const target = mm[1];
    const leaving = target === me.id;
    if (!leaving && !admin) throw new HttpError(403, 'ADMIN_ONLY', 'Only group admins can remove members.');
    await env.DB.prepare('DELETE FROM group_members WHERE group_id = ? AND user_id = ?').bind(gid, target).run();
    // Keep at least one admin.
    const left = await env.DB.prepare("SELECT user_id, role FROM group_members WHERE group_id = ? ORDER BY added_at").bind(gid).all<{ user_id: string; role: string }>();
    if (left.results.length && !left.results.some((x) => x.role === 'admin')) {
      await env.DB.prepare("UPDATE group_members SET role = 'admin' WHERE group_id = ? AND user_id = ?").bind(gid, left.results[0].user_id).run();
    }
    await groupEvent(env, gid, { action: leaving ? 'left' : 'removed', actor: me.id, targets: [target] }, [target]);
    return json({ ok: true });
  }

  const am = rest.match(/^\/admins\/([\w-]+)$/);
  if ((m === 'POST' || m === 'DELETE') && am) {
    if (!admin) throw new HttpError(403, 'ADMIN_ONLY', 'Only group admins can change admins.');
    if (!(await membership(env, gid, am[1]))) throw new HttpError(404, 'NOT_A_MEMBER');
    await env.DB.prepare('UPDATE group_members SET role = ? WHERE group_id = ? AND user_id = ?').bind(m === 'POST' ? 'admin' : 'member', gid, am[1]).run();
    await groupEvent(env, gid, { action: m === 'POST' ? 'admin' : 'unadmin', actor: me.id, targets: [am[1]] });
    return json({ ok: true });
  }

  // Encrypted message, one sealed copy per member (fan-out).
  if (m === 'POST' && rest === '/messages') {
    const b = await readJson<{ msgId: string; bodies: Record<string, string>; silent?: boolean; control?: boolean }>(c.req);
    // "Only admins can send messages" (control messages like votes/receipts still go through).
    if (settings.send_messages === 'admins' && !admin && !b.control) {
      throw new HttpError(403, 'ADMINS_ONLY_MESSAGES', 'Only admins can send messages to this group.');
    }
    const msgId = String(b.msgId ?? '').slice(0, 64);
    if (!msgId) throw new HttpError(400, 'BAD_MESSAGE');
    await limit(env, 'gmsg', me.id, 120, 60);
    const members = new Set(await memberIds(env, gid));
    const name = (await env.DB.prepare('SELECT name FROM groups WHERE id = ?').bind(gid).first<{ name: string }>())?.name ?? 'Group';
    let at = t;
    await Promise.all(
      Object.entries(b.bodies ?? {})
        .filter(([u, body]) => u !== me.id && members.has(u) && typeof body === 'string' && body.length < 64 * 1024)
        .map(async ([u, body]) => {
          const ev = await deliver(env, u, { type: 'msg', from: me.id, group: gid, msgId, body });
          at = ev.at as number;
          if (!b.silent && ev.live === 0 && pushConfigured(env)) {
            try {
              await notify(env, u, name, `${me.name || me.phone}: New message`, {
                type: 'msg',
                chat: gid,
                group: gid,
                from: me.id,
                msgId,
                phone: me.phone,
                sender: me.name || me.phone,
                body: body.length < 3000 ? body : '',
              });
            } catch {}
          }
        }),
    );
    return json({ ok: true, at });
  }

  if (m === 'POST' && rest === '/typing') {
    const ids = (await memberIds(env, gid)).filter((u) => u !== me.id);
    await Promise.all(ids.map((u) => push(env, u, { type: 'typing', from: me.id, group: gid, typing: true })));
    return json({ ok: true });
  }

  return null;
}
