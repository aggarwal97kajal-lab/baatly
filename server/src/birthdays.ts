import { Env, HttpError, json, readJson } from './util';

type Me = { id: string };
type Ctx = { req: Request; env: Env };

function validDob(s: string) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return false;
  const y = Number(m[1]), mo = Number(m[2]), d = Number(m[3]);
  const t = new Date(Date.UTC(y, mo - 1, d));
  if (t.getUTCFullYear() !== y || t.getUTCMonth() !== mo - 1 || t.getUTCDate() !== d) return false;
  const nowY = new Date().getUTCFullYear();
  return y >= nowY - 120 && t.getTime() <= Date.now();
}

/** Birthdays: my date of birth, and the day/month of people I've saved who share theirs with me. */
export async function birthdayRoute(c: Ctx, me: Me, m: string, p: string): Promise<Response | null> {
  const env = c.env;
  if (p === '/v1/me/birthday') {
    if (m === 'GET') {
      const r = await env.DB.prepare('SELECT birthday, birthday_share FROM users WHERE id = ?').bind(me.id).first<{ birthday: string | null; birthday_share: number }>();
      return json({ date: r?.birthday ?? null, share: r?.birthday_share ?? 1 });
    }
    if (m === 'PUT') {
      const b = await readJson<{ date?: string; share?: number }>(c.req);
      const date = String(b.date ?? '');
      if (!validDob(date)) throw new HttpError(400, 'INVALID_DATE', 'Enter a valid date of birth.');
      const share = [0, 1, 3].includes(Number(b.share)) ? Number(b.share) : 1;
      await env.DB.prepare('UPDATE users SET birthday = ?, birthday_share = ? WHERE id = ?').bind(date, share, me.id).run();
      return json({ ok: true });
    }
  }
  if (p === '/v1/birthdays' && m === 'GET') {
    const rows = await env.DB.prepare(
      `SELECT u.id AS id, substr(u.birthday, 6, 5) AS bd
         FROM user_contacts mine JOIN users u ON u.id = mine.contact_id
        WHERE mine.user_id = ?1 AND u.birthday IS NOT NULL
          AND (u.birthday_share = 0
               OR (u.birthday_share = 1 AND EXISTS (SELECT 1 FROM user_contacts t WHERE t.user_id = u.id AND t.contact_id = ?1)))
        LIMIT 5000`,
    )
      .bind(me.id)
      .all<{ id: string; bd: string }>();
    return json({ items: rows.results.map((r) => ({ id: r.id, bd: r.bd })) });
  }
  return null;
}
