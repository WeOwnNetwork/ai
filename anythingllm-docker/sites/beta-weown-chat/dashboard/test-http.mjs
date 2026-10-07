// Run the REAL dashboard server (node server.js) against a stub AnythingLLM and
// check, over HTTP: the public /healthz error body, the /brand/logo response
// headers, SVG logo upload rejection, /api/documents/content locationVerified,
// and the 413 for an oversize request body.
// Run from this directory: node test-http.mjs
// Every credential below is a throwaway test value for this local run.
import { spawn } from 'node:child_process';
import http from 'node:http';
import net from 'node:net';
import crypto from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

let bad = 0;
const check = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name}`);
  if (!ok) console.log('       got=', got, 'want=', want);
};

const freePort = () => new Promise((ok) => {
  const s = net.createServer().listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => ok(port)); });
});

// Stub AnythingLLM: /api/ping, and GET /api/v1/document/:name returning the
// location shapes ALLM is known to send (folder-qualified, bare, absent).
const DOCS = {
  'good.json': { location: 'custom-documents/good.json', title: 'Good', pageContent: 'hello' },
  'bare.json': { location: 'bare.json', title: 'Bare', pageContent: 'hello' },
  'none.json': { title: 'None', pageContent: 'hello' },
};
// The three documents are this tenant's: embedded in its private workspace.
// Every docpath handler checks that before anything else (weown-fleet#48).
const WS_DOCS = {
  'ws-private': Object.keys(DOCS).map((n, i) => ({ id: i + 1, docpath: `custom-documents/${n}` })),
  'ws-public': [],
};
const allm = http.createServer((req, res) => {
  if (req.url === '/api/ping') { res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end('{"online":true}'); }
  const ws = /^\/api\/v1\/workspace\/([^/?]+)$/.exec(req.url);
  if (ws && WS_DOCS[ws[1]]) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ workspace: [{ slug: ws[1], documents: WS_DOCS[ws[1]] }] }));
  }
  const m = /^\/api\/v1\/document\/([^/?]+)/.exec(req.url);
  if (m && DOCS[decodeURIComponent(m[1])]) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ document: DOCS[decodeURIComponent(m[1])] }));
  }
  res.writeHead(404, { 'Content-Type': 'application/json' }); res.end('{"error":"not found"}');
});
// A socket that accepts and never answers, for the healthz timeout path.
const silent = net.createServer(() => {});

const SECRET = 'test-only-session-secret';
const stateDir = mkdtempSync(path.join(tmpdir(), 'dash-http-'));
const children = [];
function startDashboard(allmUrl) {
  return new Promise(async (ok, fail) => {
    const port = await freePort();
    const log = { out: '' };
    const child = spawn(process.execPath, ['server.js'], {
      env: {
        PATH: process.env.PATH, PORT: String(port), BASE_PATH: '/app', ALLM_URL: allmUrl,
        ALLM_ADMIN_API_KEY: 'test-only-key', DASHBOARD_PASSWORD_HASH: 'scrypt$00$00',
        DASHBOARD_SESSION_SECRET: SECRET, DASHBOARD_STATE_DIR: stateDir,
        PUBLIC_DOMAIN: 'chat.example.test', EMBED_ID: 'emb_test',
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    children.push(child);
    const onData = (c) => { log.out += c; if (/listening :\d+/.test(log.out)) ok({ port, log }); };
    child.stdout.on('data', onData); child.stderr.on('data', (c) => { log.out += c; });
    child.on('exit', (code) => fail(new Error(`dashboard exited ${code}: ${log.out}`)));
  });
}
const exp = Date.now() + 3600e3;
const COOKIE = `dsession=${exp}.${crypto.createHmac('sha256', SECRET).update(String(exp)).digest('hex')}`;

function request(port, method, p, { headers = {}, body } = {}) {
  return new Promise((ok) => {
    const req = http.request({ host: '127.0.0.1', port, method, path: p, headers }, (r) => {
      const chunks = []; r.on('data', (c) => chunks.push(c));
      r.on('end', () => ok({ status: r.statusCode, headers: r.headers, body: Buffer.concat(chunks).toString('utf8') }));
      r.on('error', (e) => ok({ status: `ERR ${e.code || e.message}`, headers: {}, body: '' }));
    });
    req.on('error', (e) => ok({ status: `ERR ${e.code || e.message}`, headers: {}, body: '' }));
    if (body !== undefined) req.end(body); else req.end();
  });
}
const authed = (extra = {}) => ({ Cookie: COOKIE, 'X-Dashboard': '1', ...extra });
const json = (s) => { try { return JSON.parse(s); } catch { return null; } };

try {
  await new Promise((ok) => allm.listen(0, '127.0.0.1', ok));
  await new Promise((ok) => silent.listen(0, '127.0.0.1', ok));
  const allmPort = allm.address().port;
  const deadPort = await freePort(); // nothing listens here → ECONNREFUSED
  const main = await startDashboard(`http://127.0.0.1:${allmPort}`);
  const dead = await startDashboard(`http://127.0.0.1:${deadPort}`);
  const hung = await startDashboard(`http://127.0.0.1:${silent.address().port}`);

  // ── /healthz: generic public body, detail only in the server log ──
  {
    const up = await request(main.port, 'GET', '/app/healthz');
    check('healthz up: 200 online', [up.status, json(up.body)], [200, { ok: true, app: 'online' }]);
    const r = await request(dead.port, 'GET', '/app/healthz');
    check('healthz refused: 503 generic "unreachable"', [r.status, json(r.body)], [503, { ok: false, app: 'unreachable' }]);
    check('healthz refused: body names no address/port', /127\.0\.0\.1|ECONNREFUSED|\d{4,5}/.test(r.body), false);
    const r2 = await request(dead.port, 'GET', '/healthz');
    check('healthz (unprefixed) refused: generic', json(r2.body), { ok: false, app: 'unreachable' });
    await new Promise((ok) => setTimeout(ok, 100));
    check('healthz refused: detail logged server-side', dead.log.out.includes(`ECONNREFUSED 127.0.0.1:${deadPort}`), true);
    const t = await request(hung.port, 'GET', '/app/healthz');
    check('healthz no answer in 3s: 503 "timeout"', [t.status, json(t.body)], [503, { ok: false, app: 'timeout' }]);
  }

  // ── /brand/logo: sandboxing CSP + nosniff, also for a logo stored before this fix ──
  const CSP = "default-src 'none'; style-src 'unsafe-inline'; sandbox";
  {
    const d = await request(main.port, 'GET', '/app/brand/logo');
    check('default mark: CSP sandbox', d.headers['content-security-policy'], CSP);
    check('default mark: nosniff', d.headers['x-content-type-options'], 'nosniff');
    const mk = await request(main.port, 'GET', '/app/brand/weownchat-mark.svg');
    check('weownchat-mark: CSP sandbox', mk.headers['content-security-policy'], CSP);
    // A hostile SVG already on disk (uploaded under the old, weaker checks).
    mkdirSync(path.join(stateDir, 'embed-brand'), { recursive: true });
    const old = '<svg xmlns="http://www.w3.org/2000/svg"><x:script xmlns:x="http://www.w3.org/2000/svg">alert(document.domain)</x:script></svg>';
    writeFileSync(path.join(stateDir, 'embed-brand', 'logo.svg'), old);
    writeFileSync(path.join(stateDir, 'embed-appearance.json'), JSON.stringify({ themeId: 'weown', logo: { ext: 'svg', mime: 'image/svg+xml', updatedAt: '1' } }));
    const s = await request(main.port, 'GET', '/app/brand/logo');
    check('stored svg logo served: 200 same bytes', [s.status, s.body], [200, old]);
    check('stored svg logo: CSP sandbox (script blocked if opened directly)', s.headers['content-security-policy'], CSP);
    check('stored svg logo: nosniff', s.headers['x-content-type-options'], 'nosniff');
    check('stored svg logo: utf-8 svg type', s.headers['content-type'], 'image/svg+xml; charset=utf-8');
    check('stored svg logo: still loadable cross-origin by the widget', s.headers['access-control-allow-origin'], '*');
  }

  // ── SVG upload: hostile payloads refused at the real route, a normal logo accepted ──
  {
    const up = (name, body) => request(main.port, 'POST', '/app/api/embed-logo', {
      headers: authed({ 'X-Upload-Filename': name, 'Content-Type': 'image/svg+xml' }), body,
    });
    const NS = 'xmlns="http://www.w3.org/2000/svg"';
    const hostile = {
      'entity-encoded javascript: href': `<svg ${NS} xmlns:xlink="http://www.w3.org/1999/xlink"><a xlink:href="j&#x61;vascript:alert(document.domain)"><rect width="9" height="9"/></a></svg>`,
      'namespace-prefixed script': `<svg ${NS}><x:script xmlns:x="http://www.w3.org/2000/svg">alert(document.domain)</x:script></svg>`,
      'DTD entities spelling javascript:': `<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY a "java"><!ENTITY b "script:alert(1)">]><svg ${NS}><a href="&a;&b;"><rect width="9" height="9"/></a></svg>`,
      'backslash protocol-relative href': `<svg ${NS}><image href="\\\\evil.example/x.png"/></svg>`,
    };
    for (const [name, body] of Object.entries(hostile)) {
      const r = await up('logo.svg', body);
      check(`upload refused: ${name}`, r.status, 400);
    }
    const good = `<svg ${NS} viewBox="0 0 64 64"><defs><linearGradient id="g"><stop offset="0" stop-color="#00A3FF"/></linearGradient></defs><rect width="64" height="64" rx="12" fill="url(#g)"/></svg>`;
    const r = await up('logo.svg', good);
    check('upload accepted: ordinary logo', [r.status, json(r.body) && json(r.body).ok], [200, true]);
    const s = await request(main.port, 'GET', '/app/brand/logo');
    check('uploaded logo served back with CSP', [s.body, s.headers['content-security-policy']], [good, CSP]);
  }

  // ── /api/documents/content: locationVerified only on a folder-qualified exact match ──
  {
    const get = async (p) => json((await request(main.port, 'GET', `/app/api/documents/content?path=${encodeURIComponent(p)}`, { headers: authed() })).body);
    const g = await get('custom-documents/good.json');
    check('folder-qualified match: verified', [g.location, g.locationVerified], ['custom-documents/good.json', true]);
    const b = await get('custom-documents/bare.json');
    check('bare filename: NOT verified', [b.location, b.locationVerified], ['bare.json', false]);
    const n = await get('custom-documents/none.json');
    check('no location: NOT verified', [n.location, n.locationVerified], [null, false]);
  }

  // ── oversize bodies: 413 with the limit, delivered (not a dropped socket) ──
  {
    // /api/chat cap = max(6 MiB, 3 attachments x 4 MiB + 512 KiB) = 13,107,200 B = 12.5 MB
    const CHAT_CAP = Math.max(6 * 1048576, 3 * 4 * 1048576 + 512 * 1024);
    check('chat cap derivation', CHAT_CAP, 13107200);
    const big = `{"message":"${'a'.repeat(CHAT_CAP)}"}`; // CHAT_CAP + 14 bytes
    const r = await request(main.port, 'POST', '/app/api/chat', { headers: authed({ 'Content-Type': 'application/json' }), body: big });
    check('chat over cap: 413', r.status, 413);
    check('chat over cap: clear error', json(r.body), { error: 'request is too large — the limit is 12.5 MB' });
    check('chat over cap: Connection close', r.headers.connection, 'close');
    // default cap 256 KiB = 262,144 B, on another JSON endpoint
    const lock = await request(main.port, 'POST', '/app/api/documents/lock', { headers: authed({ 'Content-Type': 'application/json' }), body: `{"docpath":"${'x'.repeat(262144)}"}` });
    check('lock over 256 KB: 413 with limit', [lock.status, json(lock.body)], [413, { error: 'request is too large — the limit is 256 KB' }]);
    const small = await request(main.port, 'POST', '/app/api/documents/lock', { headers: authed({ 'Content-Type': 'application/json' }), body: '{}' });
    check('lock under cap: normal validation (400 docpath required)', [small.status, json(small.body)], [400, { error: 'docpath required' }]);
    // past twice the cap the server stops waiting: the connection is dropped
    // (no response is possible) and the process must survive it
    const huge = await request(main.port, 'POST', '/app/api/documents/lock', { headers: authed({ 'Content-Type': 'application/json' }), body: `{"docpath":"${'x'.repeat(3 * 262144)}"}` });
    console.log('       (over 2x cap got:', huge.status, ')');
    check('lock over 2x cap: connection dropped or 413, never processed', typeof huge.status === 'string' || huge.status === 413, true);
    const after = await request(main.port, 'GET', '/app/healthz');
    check('server still serving after oversize bodies', after.status, 200);
  }
} finally {
  for (const c of children) c.kill();
  allm.close(); silent.close();
  rmSync(stateDir, { recursive: true, force: true });
}

console.log(bad ? `\n${bad} FAILURES` : '\nall checks pass');
process.exit(bad ? 1 : 0);
