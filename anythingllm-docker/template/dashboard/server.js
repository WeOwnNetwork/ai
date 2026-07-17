// {{ project_name }} customer dashboard — zero-dependency Node server.
// (Plain JS, no jinja vars: all instance config arrives via environment,
// injected at container start by the Infisical entrypoint wrapper.)
//
// WHAT THIS IS: the customer's ONLY surface. They authenticate HERE (never to
// AnythingLLM), and this server proxies scoped actions to the ALLM API with
// the admin Developer API key held server-side. Two sections:
//   Public  -> workspace WS_PUBLIC_SLUG  (grounds the website embed widget)
//   Private -> workspace WS_PRIVATE_SLUG (their business docs + private chat)
//
// Zero npm dependencies by design: no supply chain, no install step at deploy.
// Uploads and chat are streamed/proxied raw — this server never parses
// multipart bodies, it just authenticates, scopes, and forwards.
//
// Required env (Infisical): ALLM_ADMIN_API_KEY, DASHBOARD_PASSWORD_HASH
// (sha256 hex of the customer password), DASHBOARD_SESSION_SECRET.
// Optional env: DASHBOARD_CUSTOMER_EMAIL, WS_PUBLIC_SLUG, WS_PRIVATE_SLUG,
// EMBED_ID, PUBLIC_DOMAIN, ALLM_URL, PORT, BASE_PATH.
'use strict';
const http = require('http');
const https = require('https');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.env.PORT || '3000', 10);
const BASE = process.env.BASE_PATH || '/app';
const ALLM_URL = process.env.ALLM_URL || 'http://anythingllm:3001';
const API_KEY = process.env.ALLM_ADMIN_API_KEY || '';
const PW_HASH = (process.env.DASHBOARD_PASSWORD_HASH || '').toLowerCase();
const SESSION_SECRET = process.env.DASHBOARD_SESSION_SECRET || '';
const CUSTOMER_EMAIL = (process.env.DASHBOARD_CUSTOMER_EMAIL || '').toLowerCase();
const WS = { public: process.env.WS_PUBLIC_SLUG || 'ws-public', private: process.env.WS_PRIVATE_SLUG || 'ws-private' };
const EMBED_ID = process.env.EMBED_ID || '';
const PUBLIC_DOMAIN = process.env.PUBLIC_DOMAIN || '';
const VERSION = process.env.DASHBOARD_VERSION || 'v0';

for (const [k, v] of Object.entries({ ALLM_ADMIN_API_KEY: API_KEY, DASHBOARD_PASSWORD_HASH: PW_HASH, DASHBOARD_SESSION_SECRET: SESSION_SECRET })) {
  if (!v) { console.error(`refusing to start: ${k} not injected — set it in Infisical`); process.exit(1); }
}

// ── sessions: HMAC-signed expiry cookie, SameSite=Strict ─────────────────────
const hmac = (s) => crypto.createHmac('sha256', SESSION_SECRET).update(s).digest('hex');
const makeSession = () => { const exp = Date.now() + 12 * 3600e3; return `${exp}.${hmac(String(exp))}`; };
const validSession = (c) => {
  const m = /(?:^|;\s*)dsession=([^;]+)/.exec(c || ''); if (!m) return false;
  const [exp, sig] = m[1].split('.'); if (!exp || !sig) return false;
  try {
    return Number(exp) > Date.now() &&
      crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(hmac(exp)));
  } catch { return false; }
};

// naive login rate limit: 10 attempts / 10 min per IP
const attempts = new Map();
const throttled = (ip) => {
  const now = Date.now();
  const a = (attempts.get(ip) || []).filter((t) => now - t < 600e3);
  attempts.set(ip, a);
  return a.length >= 10;
};

// ── ALLM proxy helper ────────────────────────────────────────────────────────
function allm(method, apiPath, { body, headers, stream } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(apiPath, ALLM_URL);
    const lib = u.protocol === 'https:' ? https : http;
    const req = lib.request(u, { method, headers: { Authorization: `Bearer ${API_KEY}`, Accept: 'application/json', ...headers } }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        let json = null; try { json = JSON.parse(data); } catch { /* non-JSON */ }
        resolve({ status: res.statusCode, json, raw: data });
      });
    });
    req.on('error', reject);
    req.setTimeout(240e3, () => req.destroy(new Error('ALLM request timeout')));
    if (stream) stream.pipe(req);
    else { if (body !== undefined) req.end(JSON.stringify(body)); else req.end(); }
  });
}

const send = (res, code, obj, extra = {}) => {
  const body = typeof obj === 'string' ? obj : JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': typeof obj === 'string' ? 'text/html; charset=utf-8' : 'application/json', 'Cache-Control': 'no-store', ...extra });
  res.end(body);
};
const page = (name) => fs.readFileSync(path.join(__dirname, 'public', name), 'utf8');
const readBody = (req) => new Promise((r) => { let d = ''; req.on('data', (c) => (d += c)); req.on('end', () => { try { r(JSON.parse(d || '{}')); } catch { r({}); } }); });
const scopeOf = (p) => (p.endsWith('/public') ? 'public' : p.endsWith('/private') ? 'private' : null);

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x');
    let p = url.pathname;
    if (p === '/healthz') return send(res, 200, { ok: true });
    if (!p.startsWith(BASE)) return send(res, 302, 'redirecting', { Location: BASE + '/' });
    p = p.slice(BASE.length) || '/';
    const authed = validSession(req.headers.cookie);

    // CSRF: all state-changing calls must carry the custom header (fetch-only)
    if (req.method !== 'GET' && req.headers['x-dashboard'] !== '1' && p !== '/api/login')
      return send(res, 403, { error: 'missing X-Dashboard header' });

    // ── auth ──
    if (p === '/api/login' && req.method === 'POST') {
      const ip = req.socket.remoteAddress || '?';
      if (throttled(ip)) return send(res, 429, { error: 'too many attempts — wait 10 minutes' });
      const { email, password } = await readBody(req);
      const ok = crypto.createHash('sha256').update(password || '').digest('hex') === PW_HASH &&
                 (!CUSTOMER_EMAIL || (email || '').toLowerCase() === CUSTOMER_EMAIL);
      if (!ok) { attempts.get(ip).push(Date.now()); return send(res, 401, { error: 'invalid credentials' }); }
      return send(res, 200, { ok: true }, { 'Set-Cookie': `dsession=${makeSession()}; Path=${BASE}; HttpOnly; SameSite=Strict; Secure; Max-Age=43200` });
    }
    if (p === '/api/logout' && req.method === 'POST')
      return send(res, 200, { ok: true }, { 'Set-Cookie': `dsession=x; Path=${BASE}; HttpOnly; SameSite=Strict; Secure; Max-Age=0` });

    // ── pages ──
    if (p === '/' || p === '') return send(res, 200, page(authed ? 'index.html' : 'login.html'));
    if (p === '/version') return send(res, 200, { version: VERSION });

    if (!authed) return send(res, 401, { error: 'not authenticated' });

    // ── documents ──
    const scope = scopeOf(p);
    if (p.startsWith('/api/documents/') && scope && req.method === 'GET') {
      const r = await allm('GET', `/api/v1/workspace/${WS[scope]}`);
      const docs = ((r.json || {}).workspace || [])[0]?.documents || (r.json || {}).workspace?.documents || [];
      return send(res, r.status === 200 ? 200 : 502, { documents: docs.map((d) => ({ id: d.id, path: d.docpath, name: (d.metadata && JSON.parse(d.metadata).title) || d.docpath })) });
    }
    if (p.startsWith('/api/upload/') && scope && req.method === 'POST') {
      // stream the multipart body straight through to ALLM (never parsed here)
      const up = await allm('POST', '/api/v1/document/upload', { headers: { 'content-type': req.headers['content-type'], 'content-length': req.headers['content-length'] }, stream: req });
      const loc = up.json && up.json.documents && up.json.documents[0] && up.json.documents[0].location;
      if (!loc) return send(res, 502, { error: 'upload failed', detail: (up.json && up.json.error) || up.status });
      const emb = await allm('POST', `/api/v1/workspace/${WS[scope]}/update-embeddings`, { body: { adds: [loc] }, headers: { 'content-type': 'application/json' } });
      if (emb.status !== 200) return send(res, 502, { error: 'uploaded but embedding failed', detail: (emb.json && emb.json.error) || emb.status });
      return send(res, 200, { ok: true, location: loc });
    }
    if (p.startsWith('/api/remove/') && scope && req.method === 'POST') {
      const { docpath } = await readBody(req);
      if (!docpath) return send(res, 400, { error: 'docpath required' });
      const emb = await allm('POST', `/api/v1/workspace/${WS[scope]}/update-embeddings`, { body: { deletes: [docpath] }, headers: { 'content-type': 'application/json' } });
      // best-effort: also purge the file from the system document store
      await allm('DELETE', '/api/v1/system/remove-documents', { body: { names: [docpath] }, headers: { 'content-type': 'application/json' } }).catch(() => null);
      return send(res, emb.status === 200 ? 200 : 502, { ok: emb.status === 200 });
    }

    // ── private chat (proxied; customer never talks to ALLM directly) ──
    if (p === '/api/chat' && req.method === 'POST') {
      const { message } = await readBody(req);
      if (!message) return send(res, 400, { error: 'message required' });
      const r = await allm('POST', `/api/v1/workspace/${WS.private}/chat`, { body: { message, mode: 'chat' }, headers: { 'content-type': 'application/json' } });
      const text = (r.json && (r.json.textResponse || r.json.error)) || 'no response';
      return send(res, 200, { text, sources: (r.json && r.json.sources || []).map((s) => s.title).slice(0, 5) });
    }

    // ── embed snippet ──
    if (p === '/api/snippet' && req.method === 'GET') {
      if (!EMBED_ID) return send(res, 200, { snippet: '', note: 'Embed not provisioned yet — contact WeOwn support.' });
      const d = PUBLIC_DOMAIN || 'YOUR-INSTANCE-DOMAIN';
      return send(res, 200, { snippet: `<script data-embed-id="${EMBED_ID}"\n  data-base-api-url="https://${d}/api/embed"\n  src="https://${d}/embed/anythingllm-chat-widget.min.js"><\/script>` });
    }

    return send(res, 404, { error: 'not found' });
  } catch (e) {
    console.error('[dashboard]', e.message);
    send(res, 500, { error: 'internal error' });
  }
});

server.listen(PORT, () => console.log(`dashboard ${VERSION} listening :${PORT} base=${BASE} allm=${ALLM_URL} ws=${WS.public}/${WS.private}`));
