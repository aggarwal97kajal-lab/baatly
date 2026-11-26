// Push health check (run by CI). Prints only counts and FCM result codes, never tokens or ids.
import { execSync } from 'node:child_process';
import crypto from 'node:crypto';

const q = (sql) => JSON.parse(execSync(`npx wrangler d1 execute baatly-db --remote --json --command "${sql}"`, { encoding: 'utf8' }))[0].results;
const sa = JSON.parse(process.env.FCM_SERVICE_ACCOUNT || '{}');
console.log('service account project:', sa.project_id ? sa.project_id.replace(/./g, (c, i) => (i < 6 ? c : '*')) : 'MISSING');
console.log('tokens:', JSON.stringify(q('SELECT COUNT(*) AS rows, COUNT(DISTINCT token) AS tokens, COUNT(DISTINCT user_id) AS users FROM push_tokens')));
console.log('newest token rows (age min):', JSON.stringify(q("SELECT (strftime('%s','now')*1000 - updated_at)/60000 AS age_min FROM push_tokens ORDER BY updated_at DESC LIMIT 6")));
const rows = q('SELECT token FROM push_tokens ORDER BY updated_at DESC LIMIT 6');
if (!sa.private_key) process.exit(0);
const b64 = (b) => Buffer.from(b).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const head = b64(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
const body = b64(JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 }));
const sig = crypto.createSign('RSA-SHA256').update(`${head}.${body}`).sign(sa.private_key);
const jwt = `${head}.${body}.${b64(sig)}`;
const tr = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}` });
const tj = await tr.json();
console.log('oauth:', tr.status, tj.error || 'ok');
if (!tj.access_token) process.exit(0);
for (const [i, r] of rows.entries()) {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: { authorization: `Bearer ${tj.access_token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ validate_only: true, message: { token: r.token, data: { type: 'ping' }, android: { priority: 'HIGH' } } }),
  });
  const t = await res.text();
  const code = (t.match(/"errorCode":\s*"(\w+)"/) || t.match(/"status":\s*"(\w+)"/) || [])[1] || '';
  console.log(`token #${i + 1}:`, res.status, code);
}
