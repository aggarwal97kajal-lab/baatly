import type { Env } from './util';

/** m: 0 everyone, 1 my contacts, 2 my contacts except x, 3 nobody */
export type Rule = { m: number; x?: string[] };
export type Privacy = { lastSeen: Rule; online: number; photo: Rule; about: Rule };

const def: Privacy = { lastSeen: { m: 0 }, online: 0, photo: { m: 0 }, about: { m: 0 } };

function rule(v: unknown): Rule {
  const r = (v ?? {}) as Rule;
  const m = [0, 1, 2, 3].includes(Number(r.m)) ? Number(r.m) : 0;
  const x = Array.isArray(r.x) ? r.x.map(String).slice(0, 5000) : [];
  return { m, x };
}

export function cleanPrivacy(v: unknown): Privacy {
  const p = (v ?? {}) as Record<string, unknown>;
  return {
    lastSeen: rule(p.lastSeen),
    online: Number(p.online) === 1 ? 1 : 0,
    photo: rule(p.photo),
    about: rule(p.about),
  };
}

export function parsePrivacy(s: string | null | undefined): Privacy {
  try {
    return cleanPrivacy(JSON.parse(s || '{}'));
  } catch {
    return def;
  }
}

export async function privacyOf(env: Env, userId: string): Promise<Privacy> {
  const r = await env.DB.prepare('SELECT privacy FROM users WHERE id = ?').bind(userId).first<{ privacy: string }>();
  return parsePrivacy(r?.privacy);
}

export async function isContact(env: Env, owner: string, viewer: string) {
  return !!(await env.DB.prepare('SELECT 1 FROM user_contacts WHERE user_id = ? AND contact_id = ?').bind(owner, viewer).first());
}

/** Can `viewer` see something of `owner` guarded by `r`? */
export async function allowed(env: Env, owner: string, viewer: string, r: Rule): Promise<boolean> {
  if (owner === viewer) return true;
  if (r.m === 0) return true;
  if (r.m === 3) return false;
  if (!(await isContact(env, owner, viewer))) return false;
  return r.m === 1 || !(r.x ?? []).includes(viewer);
}

/** What `viewer` may see of `owner`'s presence. */
export async function presenceFor(env: Env, owner: string, viewer: string, online: boolean, lastSeen: number | null) {
  const p = await privacyOf(env, owner);
  const seeLast = await allowed(env, owner, viewer, p.lastSeen);
  const seeOnline = p.online === 1 ? seeLast : true;
  // Like WhatsApp: if you hide your last seen, you can't see others'.
  const mine = await privacyOf(env, viewer);
  return {
    online: seeOnline && online,
    lastSeen: seeLast && mine.lastSeen.m !== 3 && !online ? lastSeen : null,
  };
}

/** Strip about/photo a viewer may not see. */
export async function publicView<T extends { id: string; about?: string | null; photo_ver?: number | null }>(env: Env, row: T, viewer: string): Promise<T> {
  const p = await privacyOf(env, row.id);
  const out = { ...row };
  if (!(await allowed(env, row.id, viewer, p.about))) out.about = '';
  if (!(await allowed(env, row.id, viewer, p.photo))) out.photo_ver = 0;
  return out;
}
