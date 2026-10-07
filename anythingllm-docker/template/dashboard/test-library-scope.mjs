// The document library must list THIS tenant's documents and nothing else,
// and every handler that takes a docpath (content, scope, delete, lock) must
// refuse any other (weown-fleet#48). Runs the REAL dashboard (node server.js)
// against a stub AnythingLLM whose system document store also holds files that
// belong to nobody here: another brand's folder on the same instance, and an
// operator's unattached test file in AnythingLLM's shared default folder.
//
// Run from anywhere: node test-library-scope.mjs   (zero dependencies)
// It starts the server.js that sits next to this file, so copying this file
// beside an older server.js runs the same scenario against that version.
// Every credential below is a throwaway test value for this local run.
import { spawn } from 'node:child_process';
import http from 'node:http';
import net from 'node:net';
import crypto from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
let bad = 0;
const check = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name}`);
  if (!ok) console.log('       got =', JSON.stringify(got), '\n       want=', JSON.stringify(want));
};
const freePort = () => new Promise((ok) => {
  const s = net.createServer().listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => ok(port)); });
});

// ── the instance's state, as AnythingLLM would report it ────────────────────
const U = (n) => `0000000${n}-0000-4000-8000-000000000000`;
const P = {
  fee: `tenant-a/fee-schedule.pdf-${U(1)}.json`,       // tenant folder, embedded private
  faq: `tenant-a/faq.md-${U(2)}.json`,                 // tenant folder, embedded public
  legacy: `custom-documents/legacy-guide.pdf-${U(3)}.json`, // default folder, embedded private (pre-fix upload)
  detached: `tenant-a/detached-notes.txt-${U(4)}.json`, // (i)   tenant folder, in NO workspace
  other: `other-brand/other-pricing.pdf-${U(5)}.json`,  // (ii)  another brand's folder
  opTest: `custom-documents/operator-test.txt-${U(6)}.json`, // (iii) operator test file, default folder, unattached
  lookalike: `tenant-a-archive/old.txt-${U(7)}.json`,    // folder whose name merely STARTS with the tenant's
};
const wsDoc = (id, docpath, title) => ({ id, docpath, metadata: JSON.stringify({ title }) });
const WORKSPACES = {
  'ws-private': [wsDoc(1, P.fee, 'fee-schedule.pdf'), wsDoc(3, P.legacy, 'legacy-guide.pdf')],
  'ws-public': [wsDoc(2, P.faq, 'faq.md')],
};
const file = (docpath, title) => ({ name: path.basename(docpath), type: 'file', id: `id-${path.basename(docpath)}`, title });
const STORE = {
  localFiles: {
    name: 'documents', type: 'folder', items: [
      { name: 'tenant-a', type: 'folder', items: [file(P.fee, 'fee-schedule.pdf'), file(P.faq, 'faq.md'), file(P.detached, 'detached-notes.txt')] },
      { name: 'other-brand', type: 'folder', items: [file(P.other, 'other-pricing.pdf')] },
      { name: 'custom-documents', type: 'folder', items: [file(P.legacy, 'legacy-guide.pdf'), file(P.opTest, 'operator-test.txt')] },
      { name: 'tenant-a-archive', type: 'folder', items: [file(P.lookalike, 'old.txt')] },
    ],
  },
};

// ── stub AnythingLLM: records every call so a scenario can inspect them ─────
let calls = [];
const stub = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    calls.push({ method: req.method, url: req.url, body });
    const reply = (code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
    if (req.url === '/api/ping') return reply(200, { online: true });
    const ws = /^\/api\/v1\/workspace\/([^/]+)$/.exec(req.url);
    if (ws && req.method === 'GET' && WORKSPACES[ws[1]]) return reply(200, { workspace: [{ slug: ws[1], documents: WORKSPACES[ws[1]], threads: [] }] });
    if (req.url === '/api/v1/documents' && req.method === 'GET') return reply(200, STORE);
    const up = /^\/api\/v1\/document\/upload(?:\/([^/?]+))?$/.exec(req.url);
    if (up && req.method === 'POST') {
      // Mirrors AnythingLLM: no folder segment = its default folder.
      const folder = up[1] ? decodeURIComponent(up[1]) : 'custom-documents';
      const name = (/filename="([^"]+)"/.exec(body) || [])[1] || 'upload.txt';
      return reply(200, { success: true, error: null, documents: [{ location: `${folder}/${name}-${U(9)}.json`, title: name }] });
    }
    // GET /api/v1/document/:name, as AnythingLLM's findDocumentInDocuments does
    // it: the FILE NAME is looked up in every folder in turn and the first hit
    // wins; the answer is the stored metadata (no pageContent, no location).
    const byName = /^\/api\/v1\/document\/([^/?]+)$/.exec(req.url);
    if (byName && req.method === 'GET') {
      const want = decodeURIComponent(byName[1]);
      for (const folder of STORE.localFiles.items) {
        const hit = folder.items.find((f) => f.name === want);
        if (hit) return reply(200, { document: { name: hit.name, type: 'file', title: hit.title, cached: false } });
      }
      return reply(404, { document: null });
    }
    if (/\/update-embeddings$/.test(req.url) && req.method === 'POST') return reply(200, { workspace: {} });
    // Not modelled: what AnythingLLM answers here. The dashboard sends this
    // DELETE's JSON body without a Content-Length, so it can arrive empty; the
    // checks below therefore read WHICH documents the dashboard targeted from
    // the update-embeddings detach calls, never from this call's body.
    if (req.url === '/api/v1/system/remove-documents' && req.method === 'DELETE') return reply(200, { success: true });
    reply(404, { error: 'not found' });
  });
});

const SECRET = 'test-only-session-secret';
const stateDir = mkdtempSync(path.join(tmpdir(), 'dash-library-'));
const children = [];
function startDashboard(allmUrl, folder) {
  return new Promise(async (ok, fail) => {
    const port = await freePort();
    const log = { out: '' };
    const env = {
      PATH: process.env.PATH, PORT: String(port), BASE_PATH: '/app', ALLM_URL: allmUrl,
      ALLM_ADMIN_API_KEY: 'test-only-key', DASHBOARD_PASSWORD_HASH: 'scrypt$00$00',
      DASHBOARD_SESSION_SECRET: SECRET, DASHBOARD_STATE_DIR: stateDir,
      PUBLIC_DOMAIN: 'chat.example.test',
    };
    if (folder !== undefined) env.DASHBOARD_DOCUMENT_FOLDER = folder;
    const child = spawn(process.execPath, [path.join(HERE, 'server.js')], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    children.push(child);
    child.stdout.on('data', (c) => { log.out += c; if (/listening :\d+/.test(log.out)) ok({ port, log }); });
    child.stderr.on('data', (c) => { log.out += c; });
    child.on('exit', (code) => fail(new Error(`dashboard exited ${code}: ${log.out}`)));
  });
}
const exp = Date.now() + 3600e3;
const COOKIE = `dsession=${exp}.${crypto.createHmac('sha256', SECRET).update(String(exp)).digest('hex')}`;
const authed = (extra = {}) => ({ Cookie: COOKIE, 'X-Dashboard': '1', ...extra });
function request(port, method, p, { headers = {}, body } = {}) {
  return new Promise((ok) => {
    const req = http.request({ host: '127.0.0.1', port, method, path: p, headers }, (r) => {
      const chunks = []; r.on('data', (c) => chunks.push(c));
      r.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json = null; try { json = JSON.parse(text); } catch { /* not json */ }
        ok({ status: r.statusCode, json });
      });
    });
    req.on('error', (e) => ok({ status: `ERR ${e.code || e.message}`, json: null }));
    if (body !== undefined) req.end(body); else req.end();
  });
}
// The library reduced to what this test is about: which documents, and their scopes.
const library = async (port) => {
  const r = await request(port, 'GET', '/app/api/documents', { headers: authed() });
  return { status: r.status, docs: ((r.json && r.json.documents) || []).map((d) => [d.path, d.private, d.public]).sort() };
};
const upload = (port, name, onDup) => request(port, 'POST', '/app/api/upload', {
  headers: authed({
    'X-Upload-Filename': name, 'X-Upload-Scope': 'private',
    'Content-Type': 'multipart/form-data; boundary=testboundary',
    ...(onDup ? { 'X-Upload-On-Duplicate': onDup } : {}),
  }),
  body: `--testboundary\r\nContent-Disposition: form-data; name="file"; filename="${name}"\r\n\r\nhello\r\n--testboundary--\r\n`,
});

const post = (port, p, obj) => request(port, 'POST', p, {
  headers: authed({ 'Content-Type': 'application/json' }), body: JSON.stringify(obj),
});

// Hand-derived expectations (not read back from the server):
// sources 1+2, the workspaces, always count: fee (private), legacy (private), faq (public).
const WORKSPACE_ONLY = [[P.fee, true, false], [P.legacy, true, false], [P.faq, false, true]].sort();
// source 3, the store, adds ONLY files under "tenant-a/" not already listed:
// detached-notes (i). Not other-brand (ii), not the operator test file (iii),
// not tenant-a-archive/ (a different folder that shares a name prefix).
const TENANT_A = [...WORKSPACE_ONLY, [P.detached, false, false]].sort();

try {
  await new Promise((ok) => stub.listen(0, '127.0.0.1', ok));
  const allmUrl = `http://127.0.0.1:${stub.address().port}`;
  const tenant = await startDashboard(allmUrl, 'tenant-a');
  const unset = await startDashboard(allmUrl, undefined);
  const shared = await startDashboard(allmUrl, 'custom-documents');
  const invalid = await startDashboard(allmUrl, '../other-brand');

  // ── listing ──
  {
    const r = await library(tenant.port);
    check('folder set: library = workspace docs + the unattached file in the tenant folder', r, { status: 200, docs: TENANT_A });
    const paths = r.docs.map((d) => d[0]);
    check('folder set: another brand\'s file is not listed', paths.includes(P.other), false);
    check('folder set: operator test file in custom-documents is not listed', paths.includes(P.opTest), false);
  }
  for (const [label, d] of [['folder unset', unset], ['folder = custom-documents (shared default)', shared], ['folder invalid', invalid]]) {
    calls = [];
    const r = await library(d.port);
    check(`${label}: fails closed, library = workspace docs only`, r, { status: 200, docs: WORKSPACE_ONLY });
    check(`${label}: system store not even queried`, calls.some((c) => c.url === '/api/v1/documents'), false);
  }

  // ── upload goes to the tenant folder ──
  {
    calls = [];
    const r = await upload(tenant.port, 'new-notes.txt');
    const upCall = calls.find((c) => c.url.startsWith('/api/v1/document/upload'));
    check('upload (folder set): sent to the tenant folder', upCall && upCall.url, '/api/v1/document/upload/tenant-a');
    check('upload (folder set): stored under tenant-a/', [r.status, r.json && r.json.location], [200, `tenant-a/new-notes.txt-${U(9)}.json`]);
    calls = [];
    await upload(unset.port, 'new-notes.txt');
    const upUnset = calls.find((c) => c.url.startsWith('/api/v1/document/upload'));
    check('upload (folder unset): AnythingLLM default upload, unchanged', upUnset && upUnset.url, '/api/v1/document/upload');
  }

  // ── replace-on-duplicate only ever targets this tenant's files ──
  // A replace detaches each target from both workspaces, then purges it. The
  // detach calls name the targets, so they are what is checked here.
  {
    const targeted = () => calls
      .filter((c) => /\/update-embeddings$/.test(c.url))
      .flatMap((c) => { try { return JSON.parse(c.body).deletes || []; } catch { return []; } });
    const purges = () => calls.filter((c) => c.url === '/api/v1/system/remove-documents').length;
    calls = [];
    const r = await upload(tenant.port, 'other-pricing.pdf', 'replace');
    check('replace: a same-named file of another brand is NOT targeted', [r.status, [...new Set(targeted())], purges()], [200, [], 0]);
    calls = [];
    const r2 = await upload(tenant.port, 'detached-notes.txt', 'replace');
    check('replace (control): the tenant\'s own same-named file IS targeted', [r2.status, [...new Set(targeted())], purges()], [200, [P.detached], 1]);
  }

  // ── every handler that takes a docpath: this tenant's documents only ──
  // Hand-derived: with the folder "tenant-a", a docpath is the tenant's iff it
  // is embedded in ws-private/ws-public (fee, faq, legacy) or is a file that
  // exists in tenant-a/ (fee, faq, detached). Everything else answers 404 —
  // the same code whether or not the file exists — and AnythingLLM is never
  // asked about it (no call names its path or file name). With the folder
  // unset only the embedded rule exists, so detached is refused too.
  // Endpoint order matters only for lock, run last so no document is locked
  // when delete runs.
  {
    // tenant prefix + another brand's file NAME: /content looks documents up by
    // file name across all folders, so a prefix check alone would serve it.
    const CRAFTED = `tenant-a/${path.basename(P.other)}`;
    const ENDPOINTS = {
      content: (port, dp) => request(port, 'GET', `/app/api/documents/content?path=${encodeURIComponent(dp)}`, { headers: authed() }),
      scope: (port, dp) => post(port, '/app/api/documents/scope', { docpath: dp, scope: 'private', on: true }),
      delete: (port, dp) => post(port, '/app/api/documents/delete', { docpath: dp }),
      lock: (port, dp) => post(port, '/app/api/documents/lock', { docpath: dp, locked: true }),
    };
    const askedAbout = (dp) => calls.some((c) => {
      const url = decodeURIComponent(c.url);
      return [dp, path.basename(dp)].some((s) => url.includes(s) || c.body.includes(s));
    });
    const FOREIGN = [
      ['another brand\'s docpath', P.other],
      ['operator test file (custom-documents, unattached)', P.opTest],
      ['tenant folder + another brand\'s file name', CRAFTED],
    ];
    const ALLOWED = [
      ['file in the tenant folder, in no workspace', P.detached],
      ['file embedded in a tenant workspace, stored in custom-documents', P.legacy],
    ];
    for (const [ep, call] of Object.entries(ENDPOINTS)) {
      for (const [label, dp] of FOREIGN) {
        calls = [];
        const r = await call(tenant.port, dp);
        check(`${ep}: ${label} → 404, AnythingLLM not asked about it`, [r.status, askedAbout(dp)], [404, false]);
      }
      for (const [label, dp] of ALLOWED) {
        const r = await call(tenant.port, dp);
        check(`${ep}: ${label} → allowed`, r.status, 200);
      }
      const u1 = await call(unset.port, P.detached);
      check(`${ep} (folder unset): tenant-folder file in no workspace → 404`, u1.status, 404);
      const u2 = await call(unset.port, P.legacy);
      check(`${ep} (folder unset): workspace-embedded file → allowed`, u2.status, 200);
    }
  }
} finally {
  for (const c of children) c.kill();
  stub.close();
  rmSync(stateDir, { recursive: true, force: true });
}

console.log(bad ? `\n${bad} FAILURES` : '\nall checks pass');
process.exit(bad ? 1 : 0);
