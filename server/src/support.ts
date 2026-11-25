import { limit } from './safety';
import { Env, HttpError, json, now, randomId, readJson } from './util';

type Me = { id: string; name: string; phone: string };
type Ctx = { req: Request; env: Env; later?: (p: Promise<unknown>) => void };

/** Where "Contact us" goes. Never sent to the app. */
const SUPPORT_TO = 'aggarwal97kajal@gmail.com';

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);

export async function supportRoute(c: Ctx, me: Me, m: string, p: string): Promise<Response | null> {
  if (m !== 'POST' || p !== '/v1/support') return null;
  const env = c.env;
  await limit(env, 'support', me.id, 10, 3600);
  const b = await readJson<{ text: string; kind?: string; device?: string; version?: string; shots?: string[] }>(c.req);
  const text = String(b.text ?? '').trim().slice(0, 5000);
  if (text.length < 3) throw new HttpError(400, 'TEXT_REQUIRED', 'Please describe the problem.');
  const kind = b.kind === 'problem' ? 'problem' : 'help';
  const shots = (b.shots ?? []).filter((s) => typeof s === 'string' && s.length < 2_500_000).slice(0, 3);
  const id = randomId();
  const device = `${String(b.device ?? '').slice(0, 80)} · v${String(b.version ?? '').slice(0, 20)}`;
  await env.DB.prepare('INSERT INTO support_tickets (id, user_id, kind, text, device, shots, created_at) VALUES (?,?,?,?,?,?,?)')
    .bind(id, me.id, kind, text, device, shots.length, now())
    .run();

  if (env.RESEND_KEY) {
    const send = async () => {
      const html =
        `<p><b>${kind === 'problem' ? 'Problem report' : 'Help request'}</b> · ticket ${id}</p>` +
        `<p>From: ${esc(me.name || '—')} (${esc(me.phone)}) · user ${me.id}<br>Device: ${esc(device)}</p>` +
        `<pre style="white-space:pre-wrap;font:14px sans-serif">${esc(text)}</pre>`;
      const r = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { authorization: `Bearer ${env.RESEND_KEY}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          from: env.RESEND_FROM || 'BAATLY Support <onboarding@resend.dev>',
          to: [SUPPORT_TO],
          subject: `[BAATLY ${kind}] ${text.slice(0, 60).replace(/\s+/g, ' ')}`,
          html,
          attachments: shots.map((s, i) => ({ filename: `screenshot-${i + 1}.jpg`, content: s })),
        }),
      });
      if (r.ok) await env.DB.prepare('UPDATE support_tickets SET emailed = 1 WHERE id = ?').bind(id).run();
    };
    c.later ? c.later(send().catch(() => {})) : await send().catch(() => {});
  }
  return json({ ok: true, ticket: id });
}
