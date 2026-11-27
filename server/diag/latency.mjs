// Measures real message timing on the live server with two throwaway users.
import { execSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import WebSocket from 'ws';

const API = 'https://baatly-api.pitaragames.workers.dev';
const sql = (q) => execSync(`npx wrangler d1 execute baatly-db --remote --json --command ${JSON.stringify(q)}`, { stdio: ['ignore', 'pipe', 'inherit'] }).toString();
const t0 = Date.now();
const users = ['diag_lat_a', 'diag_lat_b'].map((id, i) => ({ id, phone: `+1999000000${i}`, token: randomBytes(24).toString('hex') }));
const sha = (s) => createHash('sha256').update(s).digest('hex');

function cleanup() {
  try {
    sql(`DELETE FROM inbox WHERE to_user IN ('diag_lat_a','diag_lat_b'); DELETE FROM sessions WHERE user_id IN ('diag_lat_a','diag_lat_b'); DELETE FROM users WHERE id IN ('diag_lat_a','diag_lat_b');`);
  } catch (e) { console.log('cleanup error', e.message); }
}
cleanup();
sql(users.map((u) => `INSERT INTO users (id, phone, name, created_at, updated_at) VALUES ('${u.id}','${u.phone}','Diag',${t0},${t0}); INSERT INTO sessions (id, user_id, token_hash, method, created_at, last_seen_at) VALUES ('s_${u.id}','${u.id}','${sha(u.token)}','otp',${t0},${t0});`).join(' '));

const http = async (u, method, path, body) => {
  const t = Date.now();
  const r = await fetch(API + path, { method, headers: { authorization: `Bearer ${u.token}`, 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const j = await r.json().catch(() => ({}));
  return { ms: Date.now() - t, status: r.status, j };
};
const open = (u) => new Promise((res, rej) => {
  const t = Date.now();
  const ws = new WebSocket(API.replace('https', 'wss') + '/v1/ws', { headers: { authorization: `Bearer ${u.token}` } });
  ws.on('open', () => { console.log(`ws open ${u.id}: ${Date.now() - t} ms`); res(ws); });
  ws.on('error', rej);
});
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const [A, B] = users;
try {
  console.log('GET /v1/me:', (await http(A, 'GET', '/v1/me')).ms, 'ms (cold)', (await http(A, 'GET', '/v1/me')).ms, 'ms (warm)');
  const wa = await open(A);
  const wb = await open(B);
  const got = new Map();
  wb.on('message', (d) => { const s = d.toString(); if (s === 'pong') return; try { const e = JSON.parse(s); if (e.type === 'msg') got.get(e.msgId)?.(Date.now()); } catch {} });
  const acks = new Map();
  wa.on('message', (d) => { try { const e = JSON.parse(d.toString()); if (e.type === 'ack') acks.get(e.rid)?.(Date.now()); } catch {} });
  await sleep(1000);
  console.log('presence of B seen by A:', JSON.stringify((await http(A, 'POST', '/v1/users/presence', { ids: [B.id] })).j));
  for (let i = 0; i < 6; i++) {
    const msgId = 'm' + randomBytes(6).toString('hex'), rid = 'r' + i;
    const recv = new Promise((r) => got.set(msgId, r));
    const ack = new Promise((r) => acks.set(rid, r));
    const t = Date.now();
    wa.send(JSON.stringify({ type: 'send', rid, path: '/v1/messages', body: { to: B.id, msgId, body: 'diag' } }));
    const [ta, tr] = await Promise.all([ack, Promise.race([recv, sleep(15000).then(() => null)])]);
    console.log(`socket send #${i}: ack ${ta - t} ms, B received ${tr ? tr - t + ' ms' : 'NOT within 15 s'}`);
    await sleep(500);
  }
  for (let i = 0; i < 4; i++) {
    const msgId = 'h' + randomBytes(6).toString('hex');
    const recv = new Promise((r) => got.set(msgId, r));
    const t = Date.now();
    const r = await http(A, 'POST', '/v1/messages', { to: B.id, msgId, body: 'diag' });
    const tr = await Promise.race([recv, sleep(15000).then(() => null)]);
    console.log(`http send #${i}: reply ${r.ms} ms (${r.status}), B received ${tr ? tr - t + ' ms' : 'NOT within 15 s'}`);
  }
  // Idle 70 s with pings like the app, then send again (hibernation wake-up).
  const pa = setInterval(() => wa.send('ping'), 15000), pb = setInterval(() => wb.send('ping'), 15000);
  await sleep(70000);
  {
    const msgId = 'z' + randomBytes(6).toString('hex'), rid = 'rz';
    const recv = new Promise((r) => got.set(msgId, r));
    const ack = new Promise((r) => acks.set(rid, r));
    const t = Date.now();
    wa.send(JSON.stringify({ type: 'send', rid, path: '/v1/messages', body: { to: B.id, msgId, body: 'diag' } }));
    const [ta, tr] = await Promise.all([Promise.race([ack, sleep(15000).then(() => null)]), Promise.race([recv, sleep(15000).then(() => null)])]);
    console.log(`after 70 s idle: ack ${ta ? ta - t + ' ms' : 'NONE'}, B received ${tr ? tr - t + ' ms' : 'NOT within 15 s'}`);
  }
  clearInterval(pa); clearInterval(pb);
  wa.close(); wb.close();
} catch (e) {
  console.log('ERROR', e);
} finally {
  cleanup();
}
