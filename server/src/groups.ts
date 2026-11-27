import { deliver, push } from './chat';
import { notify, pushConfigured } from './fcm';
import { blocked, limit } from './safety';
import { Env, HttpError, json, now, randomId, readJson } from './util';

type Me = { id: string; name: string; phone: string };
type Ctx = { req: Request; env: Env; url: URL; later?: (p: Promise<unknown>) => void };

const MAX_MEMBERS = 256;

async function membership(env: Env, gid: string, uid: string) {
  return env.DB.prepare('SELECT role FROM group_members WHERE group_id = ? AND user_id = ?').bind(gid, uid).first<{ role: string }>();
}

async function memberIds(env: Env, gid: string) {
  const r = await env.DB.prepare('SELECT user_id FROM group_members WHERE group_id = ?').bind(gid).all<{ user_id: string }>();
  return r.results.map((x) => x.user_id);
}

async function info(env: Env, gid: string) {
  const g = await env.DB.prepare('SELECT id, name, about, photo_ver, created_by, created_at, edit_info, send_messages, community_id FROM groups WHERE id = ?').bind(gid).first();
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
  // Tell members after replying, so the app doesn't wait for every member's delivery.
  const bg = (pr: Promise<unknown>) => (c.later ? c.later(pr) : pr);
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
      bg(groupEvent(env, gid, { action: 'renamed', actor: me.id, name }));
    }
    if (b.about !== undefined) {
      await env.DB.prepare('UPDATE groups SET about = ? WHERE id = ?').bind(String(b.about).slice(0, 500), gid).run();
      bg(groupEvent(env, gid, { action: 'about', actor: me.id }));
    }
    return json({ group: await info(env, gid) });
  }

  if (m === 'PATCH' && rest === '/settings') {
    if (!admin) throw new HttpError(403, 'ADMIN_ONLY', 'Only admins can change group settings.');
    const b = await readJson<{ editInfo?: string; sendMessages?: string }>(c.req);
    if (b.editInfo === 'all' || b.editInfo === 'admins') {
      await env.DB.prepare('UPDATE groups SET edit_info = ? WHERE id = ?').bind(b.editInfo, gid).run();
      bg(groupEvent(env, gid, { action: 'edit_info', actor: me.id, value: b.editInfo }));
    }
    if (b.sendMessages === 'all' || b.sendMessages === 'admins') {
      await env.DB.prepare('UPDATE groups SET send_messages = ? WHERE id = ?').bind(b.sendMessages, gid).run();
      bg(groupEvent(env, gid, { action: 'send_messages', actor: me.id, value: b.sendMessages }));
    }
    return json({ group: await info(env, gid) });
  }

  if (m === 'DELETE' && rest === '/photo') {
    if (!canEdit) throw new HttpError(403, 'ADMIN_ONLY', 'Only admins can edit this group\'s info.');
    await env.DB.prepare('UPDATE groups SET photo = NULL, photo_ver = 0 WHERE id = ?').bind(gid).run();
    bg(groupEvent(env, gid, { action: 'photo_removed', actor: me.id }));
    return json({ ok: true });
  }

  if (m === 'PUT' && rest === '/photo') {
    if (!canEdit) throw new HttpError(403, 'ADMIN_ONLY', 'Only admins can edit this group\'s info.');
    const b = await readJson<{ photo: string }>(c.req);
    const photo = String(b.photo ?? '');
    if (photo.length < 100 || photo.length > 1_200_000) throw new HttpError(413, 'PHOTO_TOO_LARGE', 'This photo is too large.');
    await env.DB.prepare('UPDATE groups SET photo = ?, photo_ver = photo_ver + 1 WHERE id = ?').bind(photo, gid).run();
    bg(groupEvent(env, gid, { action: 'photo', actor: me.id }));
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
      bg(groupEvent(env, gid, { action: 'added', actor: me.id, targets: add }));
      bg(addToAnnouncements(env, gid, add, me.id));
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
    bg(groupEvent(env, gid, { action: leaving ? 'left' : 'removed', actor: me.id, targets: [target] }, [target]));
    return json({ ok: true });
  }

  const am = rest.match(/^\/admins\/([\w-]+)$/);
  if ((m === 'POST' || m === 'DELETE') && am) {
    if (!admin) throw new HttpError(403, 'ADMIN_ONLY', 'Only group admins can change admins.');
    if (!(await membership(env, gid, am[1]))) throw new HttpError(404, 'NOT_A_MEMBER');
    await env.DB.prepare('UPDATE group_members SET role = ? WHERE group_id = ? AND user_id = ?').bind(m === 'POST' ? 'admin' : 'member', gid, am[1]).run();
    bg(groupEvent(env, gid, { action: m === 'POST' ? 'admin' : 'unadmin', actor: me.id, targets: [am[1]] }));
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
          const ev = await deliver(env, u, { type: 'msg', from: me.id, group: gid, msgId, body, ...(b.silent ? { silent: true } : {}) });
          at = ev.at as number;
          if (!b.silent && ev.live === 0 && pushConfigured(env)) {
            bg(
              notify(env, u, name, `${me.name || me.phone}: New message`, {
                type: 'msg',
                chat: gid,
                group: gid,
                from: me.id,
                msgId,
                phone: me.phone,
                sender: me.name || me.phone,
                body: body.length < 3000 ? body : '',
              }).catch(() => {}),
            );
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


const MAX_COMMUNITY_GROUPS = 20;

/** People added to a community's group also join its announcement group. */
async function addToAnnouncements(env: Env, gid: string, users: string[], actor: string) {
  const g = await env.DB.prepare('SELECT c.announce_id AS a FROM groups g JOIN communities c ON c.id = g.community_id WHERE g.id = ?').bind(gid).first<{ a: string }>();
  if (!g || g.a === gid || !users.length) return;
  const current = new Set(await memberIds(env, g.a));
  const add = users.filter((u) => !current.has(u));
  if (!add.length) return;
  const t = now();
  await env.DB.batch(add.map((u) => env.DB.prepare('INSERT OR IGNORE INTO group_members (group_id, user_id, role, added_at) VALUES (?,?,?,?)').bind(g.a, u, 'member', t)));
  await groupEvent(env, g.a, { action: 'added', actor, targets: add });
}

async function communityView(env: Env, cid: string, me: string) {
  const c = await env.DB.prepare('SELECT * FROM communities WHERE id = ?').bind(cid).first<{ id: string; name: string; about: string; creator: string; announce_id: string }>();
  if (!c) return null;
  const role = await membership(env, c.announce_id, me);
  const gs = await env.DB.prepare(
    `SELECT g.id, g.name, (SELECT COUNT(*) FROM group_members WHERE group_id = g.id) AS members,
            EXISTS(SELECT 1 FROM group_members WHERE group_id = g.id AND user_id = ?) AS joined
       FROM groups g WHERE g.community_id = ? AND g.id != ? ORDER BY g.created_at`,
  )
    .bind(me, cid, c.announce_id)
    .all<{ id: string; name: string; members: number; joined: number }>();
  const inAny = !!role || gs.results.some((g) => g.joined);
  if (!inAny) return null;
  return {
    id: c.id,
    name: c.name,
    about: c.about,
    announce: c.announce_id,
    admin: role?.role === 'admin',
    member: !!role,
    groups: gs.results.map((g) => ({ id: g.id, name: g.name, members: g.members, joined: !!g.joined })),
  };
}

export async function communityRoute(c: Ctx, me: Me, m: string, p: string): Promise<Response | null> {
  const env = c.env;
  const bg = (pr: Promise<unknown>) => (c.later ? c.later(pr) : pr);
  const t = now();

  if (m === 'POST' && p === '/v1/communities') {
    const b = await readJson<{ name: string; about?: string; groups?: string[] }>(c.req);
    const name = String(b.name ?? '').trim().slice(0, 100);
    if (!name) throw new HttpError(400, 'NAME_REQUIRED', 'Give the community a name.');
    await limit(env, 'community', me.id, 10, 3600);
    const gids = [...new Set((b.groups ?? []).map(String))].slice(0, MAX_COMMUNITY_GROUPS);
    for (const g of gids) {
      const r = await membership(env, g, me.id);
      if (r?.role !== 'admin') throw new HttpError(403, 'ADMIN_ONLY', 'You can only add groups where you are an admin.');
      const already = await env.DB.prepare('SELECT community_id FROM groups WHERE id = ?').bind(g).first<{ community_id: string | null }>();
      if (already?.community_id) throw new HttpError(409, 'IN_COMMUNITY', 'One of these groups is already in a community.');
    }
    const people = new Set<string>();
    for (const g of gids) for (const u of await memberIds(env, g)) people.add(u);
    people.delete(me.id);
    const cid = randomId();
    const aid = randomId();
    const about = String(b.about ?? '').slice(0, 500);
    const stmts = [
      env.DB.prepare('INSERT INTO communities (id, name, about, creator, announce_id, created_at) VALUES (?,?,?,?,?,?)').bind(cid, name, about, me.id, aid, t),
      env.DB.prepare("INSERT INTO groups (id, name, about, created_by, created_at, edit_info, send_messages, community_id) VALUES (?,?,?,?,?,'admins','admins',?)").bind(
        aid,
        name,
        'Announcements from the community admins',
        me.id,
        t,
        cid,
      ),
      env.DB.prepare('INSERT INTO group_members (group_id, user_id, role, added_at) VALUES (?,?,?,?)').bind(aid, me.id, 'admin', t),
      ...[...people].map((u) => env.DB.prepare('INSERT INTO group_members (group_id, user_id, role, added_at) VALUES (?,?,?,?)').bind(aid, u, 'member', t)),
      ...gids.map((g) => env.DB.prepare('UPDATE groups SET community_id = ? WHERE id = ?').bind(cid, g)),
    ];
    for (let i = 0; i < stmts.length; i += 50) await env.DB.batch(stmts.slice(i, i + 50));
    await groupEvent(env, aid, { action: 'created', actor: me.id, targets: [...people], name });
    return json({ community: await communityView(env, cid, me.id) });
  }

  if (m === 'GET' && p === '/v1/communities') {
    const r = await env.DB.prepare(
      `SELECT DISTINCT g.community_id AS cid FROM group_members gm JOIN groups g ON g.id = gm.group_id
        WHERE gm.user_id = ? AND g.community_id IS NOT NULL`,
    )
      .bind(me.id)
      .all<{ cid: string }>();
    const out = [];
    for (const x of r.results) {
      const v = await communityView(env, x.cid, me.id);
      if (v) out.push(v);
    }
    return json({ communities: out });
  }

  const mm = p.match(/^\/v1\/communities\/([\w-]+)(\/.*)?$/);
  if (!mm) return null;
  const cid = mm[1];
  const rest = mm[2] ?? '';
  const view = await communityView(env, cid, me.id);
  if (!view) throw new HttpError(404, 'COMMUNITY_NOT_FOUND');

  if (m === 'GET' && rest === '') return json({ community: view });

  // Link one more group (community admin who also admins that group).
  if (m === 'POST' && rest === '/groups') {
    if (!view.admin) throw new HttpError(403, 'ADMIN_ONLY', 'Only community admins can add groups.');
    const b = await readJson<{ groupId: string }>(c.req);
    const gid = String(b.groupId ?? '');
    if ((await membership(env, gid, me.id))?.role !== 'admin') throw new HttpError(403, 'ADMIN_ONLY', 'You can only add groups where you are an admin.');
    const g = await env.DB.prepare('SELECT community_id FROM groups WHERE id = ?').bind(gid).first<{ community_id: string | null }>();
    if (g?.community_id) throw new HttpError(409, 'IN_COMMUNITY', 'This group is already in a community.');
    if (view.groups.length >= MAX_COMMUNITY_GROUPS) throw new HttpError(400, 'TOO_MANY_GROUPS', `A community can have up to ${MAX_COMMUNITY_GROUPS} groups.`);
    await env.DB.prepare('UPDATE groups SET community_id = ? WHERE id = ?').bind(cid, gid).run();
    bg(addToAnnouncements(env, gid, await memberIds(env, gid), me.id));
    return json({ community: await communityView(env, cid, me.id) });
  }

  // Remove a group from the community (it keeps working as a normal group).
  const rg = rest.match(/^\/groups\/([\w-]+)$/);
  if (m === 'DELETE' && rg) {
    if (!view.admin) throw new HttpError(403, 'ADMIN_ONLY', 'Only community admins can remove groups.');
    await env.DB.prepare('UPDATE groups SET community_id = NULL WHERE id = ? AND community_id = ? AND id != ?').bind(rg[1], cid, view.announce).run();
    return json({ community: await communityView(env, cid, me.id) });
  }

  // Community members can join any of its groups.
  const jg = rest.match(/^\/groups\/([\w-]+)\/join$/);
  if (m === 'POST' && jg) {
    if (!view.member) throw new HttpError(403, 'NOT_MEMBER');
    const g = view.groups.find((x) => x.id === jg[1]);
    if (!g) throw new HttpError(404, 'GROUP_NOT_FOUND');
    if (!g.joined) {
      if (g.members >= MAX_MEMBERS) throw new HttpError(400, 'TOO_MANY_MEMBERS', 'This group is full.');
      await env.DB.prepare('INSERT OR IGNORE INTO group_members (group_id, user_id, role, added_at) VALUES (?,?,?,?)').bind(g.id, me.id, 'member', t).run();
      await groupEvent(env, g.id, { action: 'added', actor: me.id, targets: [me.id] });
    }
    return json({ community: await communityView(env, cid, me.id) });
  }
  return null;
}
