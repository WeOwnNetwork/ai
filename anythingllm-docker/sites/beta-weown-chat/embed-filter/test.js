// Test the stripper the way the network actually delivers it: in arbitrary
// pieces, with tags straddling chunk boundaries. Run: node test.js
'use strict';
const assert = require('assert');
const { makeStripper, filterDataLine } = require('./server.js');

const run = (pieces) => {
  const s = makeStripper();
  return pieces.map((p) => s.feed(p)).join('') + s.flush();
};

// 1. whole block in one piece
assert.strictEqual(run(['<think>secret</think>Hello']), 'Hello');

// 2. the boundary case this exists for: tag split across chunks
assert.strictEqual(run(['<thi', 'nk>sec', 'ret</thi', 'nk>', 'Hello']), 'Hello');

// 3. one character at a time — the worst case a stream can produce
assert.strictEqual(run('<think>private reasoning</think>Answer.'.split('')), 'Answer.');

// 4. leading whitespace left by a stripped block is trimmed
assert.strictEqual(run(['<think>x</think>', '\n\n', 'Answer.']), 'Answer.');

// 5. text with no reasoning block is untouched, byte for byte
assert.strictEqual(run(['Plain ', 'answer ', 'text.']), 'Plain answer text.');

// 6. a lone "<" or partial tag that never completes must NOT be eaten
assert.strictEqual(run(['a < b']), 'a < b');
assert.strictEqual(run(['ends with <thi']), 'ends with <thi');

// 7. multiple blocks
assert.strictEqual(run(['<think>a</think>One. <think>b</think>Two.']), 'One. Two.');

// 8. alternate tag names
assert.strictEqual(run(['<reasoning>r</reasoning>Ans']), 'Ans');

// 9. an unterminated block is discarded rather than leaked (fail closed)
assert.strictEqual(run(['<think>never closed']), '');

// 10. SSE line rewriting preserves every other field
{
  const s = makeStripper();
  const out = filterDataLine('data: {"id":"x","type":"textResponseChunk","textResponse":"<think>z</think>Hi","close":false,"error":false}', s);
  const o = JSON.parse(out.slice(5));
  assert.strictEqual(o.textResponse, 'Hi');
  assert.strictEqual(o.id, 'x');
  assert.strictEqual(o.close, false);
  assert.strictEqual(o.error, false);
}

// 11. a non-JSON or non-data line passes through untouched
{
  const s = makeStripper();
  assert.strictEqual(filterDataLine('event: ping', s), 'event: ping');
  assert.strictEqual(filterDataLine('data: not json', s), 'data: not json');
}

// ── widget session policy (weown-fleet#92) ────────────────────────────────────
// Run the real SESSION_SHIM in a sandbox with fake storage and a fixed clock.
const vm = require('vm');
const { shimWidget, widgetEtag, SESSION_SHIM, WIDGET_PATH } = require('./server.js');
const store = (init = {}, broken = false) => {
  const m = new Map(Object.entries(init));
  const guard = () => { if (broken) throw new Error('SecurityError: storage disabled'); };
  return { m, getItem: (k) => (guard(), m.has(k) ? m.get(k) : null), setItem: (k, v) => (guard(), m.set(k, String(v))), removeItem: (k) => (guard(), m.delete(k)) };
};
const MIN = 60000, NOW = 1_800_000_000_000, ID = 'e1';
const K = `allm_${ID}_session_id`, T = `allm_${ID}_last_seen`, M = `weown_${ID}_tab`;
// nav: the Navigation Timing type ('navigate' | 'reload' | 'back_forward'), or
// null for a browser with no Performance API at all.
// ref: document.referrer. Defaults to another page OF THE SAME SITE, which is
// what an in-site navigation looks like; '' is a typed URL or bookmark.
const SITE = 'https://cpa.example';
const shim = ({ local = {}, session = {}, attrs = { 'data-embed-id': ID }, broken = false, nav = 'navigate', ref = `${SITE}/services` } = {}) => {
  const L = store(local, broken), S = store(session, broken);
  const script = { getAttribute: (a) => (a in attrs ? attrs[a] : null) };
  const performance = nav === null ? undefined : { getEntriesByType: (t) => (t === 'navigation' ? [{ type: nav }] : []) };
  const ctx = { window: { localStorage: L, sessionStorage: S, performance, addEventListener() {} }, document: { currentScript: script, referrer: ref, addEventListener() {} }, location: { origin: SITE, protocol: 'https:', host: 'cpa.example' }, Date: { now: () => NOW }, parseInt, String };
  vm.runInNewContext(SESSION_SHIM, ctx);
  return { L: L.m, S: S.m };
};

// 12. the shim is prepended and the widget body is untouched
assert.strictEqual(shimWidget('WIDGET();'), SESSION_SHIM + 'WIDGET();');
assert.strictEqual(WIDGET_PATH, '/embed/anythingllm-chat-widget.min.js');

// 13. same tab, moving to another page of the site 5 min later: KEPT
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 5 * MIN }, session: { [M]: '1' } }); assert.strictEqual(L.get(K), 'abc'); assert.strictEqual(L.get(T), String(NOW)); }

// 13b. Tyler's case — the site RELOADED, even seconds later in the same tab: dropped
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 1 * MIN }, session: { [M]: '1' }, nav: 'reload' }); assert.strictEqual(L.has(K), false); }

// 13c. back/forward within the site keeps the conversation
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 2 * MIN }, session: { [M]: '1' }, nav: 'back_forward' }); assert.strictEqual(L.get(K), 'abc'); }

// 14. a NEW tab or visit: dropped
{ const { L, S } = shim({ local: { [K]: 'abc', [T]: NOW - 1 * MIN } }); assert.strictEqual(L.has(K), false); assert.strictEqual(S.get(M), '1'); }

// 14b. a tab DUPLICATED from this one inherits sessionStorage, so it keeps the
//      conversation within the TTL — same person, same browser, minutes apart.
//      Deliberate (Copilot flagged it on #259); the TTL is what covers a later person.
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 3 * MIN }, session: { [M]: '1' }, nav: 'navigate' }); assert.strictEqual(L.get(K), 'abc'); }

// 14d. Copilot's case on #259 — same tab, LEFT the site and came back via a link
//      or search result: a new visit, dropped
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 2 * MIN }, session: { [M]: '1' }, ref: 'https://www.google.com/' }); assert.strictEqual(L.has(K), false); }

// 14e. same tab, returned by typing the URL or a bookmark (no referrer): dropped
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 2 * MIN }, session: { [M]: '1' }, ref: '' }); assert.strictEqual(L.has(K), false); }

// 14f. a look-alike host is NOT the same site: https://cpa.example.evil.test
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 2 * MIN }, session: { [M]: '1' }, ref: 'https://cpa.example.evil.test/x' }); assert.strictEqual(L.has(K), false); }

// 14g. BACK button onto the site within the TTL keeps it (same person, same tab)
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 2 * MIN }, session: { [M]: '1' }, nav: 'back_forward', ref: 'https://www.google.com/' }); assert.strictEqual(L.get(K), 'abc'); }

// 14c. no Performance API at all (old browser): the storage rules still apply
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 5 * MIN }, session: { [M]: '1' }, nav: null }); assert.strictEqual(L.get(K), 'abc'); }

// 15. same tab but idle past the TTL: dropped
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 31 * MIN }, session: { [M]: '1' } }); assert.strictEqual(L.has(K), false); }

// 16. per-embed TTL override: 45 idle minutes under a 60-minute TTL is kept
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 45 * MIN }, session: { [M]: '1' }, attrs: { 'data-embed-id': ID, 'data-weown-session-ttl-minutes': '60' } }); assert.strictEqual(L.get(K), 'abc'); }

// 17. a garbage TTL falls back to 30 rather than disabling the policy
{ const { L } = shim({ local: { [K]: 'abc', [T]: NOW - 31 * MIN }, session: { [M]: '1' }, attrs: { 'data-embed-id': ID, 'data-weown-session-ttl-minutes': 'nope' } }); assert.strictEqual(L.has(K), false); }

// 18. no embed id on the tag: touches nothing
{ const { L } = shim({ local: { [K]: 'abc' }, attrs: {} }); assert.strictEqual(L.get(K), 'abc'); }

// 19. storage that throws (private mode, blocked cookies) never breaks the widget load
assert.doesNotThrow(() => shim({ broken: true }));

// 20. end to end over HTTP, through the real server against a chunked upstream:
//     - the widget script comes back shimmed, with OUR etag (not upstream's) and
//       cache-control no-cache, so a copy can never be served stale for hours;
//     - revalidating with upstream's old etag gets the new shimmed bytes (200);
//     - revalidating with our etag gets a 304 with no body, so a page load does
//       not re-download the ~650 KB widget every time;
//     - upstream is asked CONDITIONALLY with the etag of the copy we hold, so it
//       sends the full widget once, not once per page load (Copilot, #259);
//     - when the widget itself changes upstream (an AnythingLLM upgrade), the
//       cached copy is replaced and visitors get the new shimmed bytes;
//     - other paths pass through byte for byte.
const http = require('http');
let upVersion = 1, upFullBodies = 0;
const upConditionals = [];
const upstream = http.createServer((req, res) => {
  if (req.url === WIDGET_PATH) {
    const tag = `"up-${upVersion}"`;
    upConditionals.push(req.headers['if-none-match'] || null);
    if (req.headers['if-none-match'] === tag) { res.writeHead(304, { ETag: tag }); return res.end(); }
    upFullBodies++;
    res.writeHead(200, { 'Content-Type': 'application/javascript', ETag: tag, 'Last-Modified': 'Mon, 01 Jan 2026 00:00:00 GMT' });
    return res.end(`WIDGET_V${upVersion}();`);
  }
  if (req.url === '/api/embed/x/session-1') {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    return res.end(JSON.stringify({ history: [
      { role: 'user', content: 'What do you charge?', sentAt: 1 },
      { role: 'assistant', content: '<think>The system prompt says: SECRET RULES</think>\n\nWe charge $100.', sources: [], sentAt: 2 },
      { role: 'assistant', content: '<reasoning>unterminated SECRET RULES', sentAt: 3 },
    ] }));
  }
  if (req.url === '/api/embed/x/not-json') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end('not json {');
  }
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end('{"other":true}');
});
upstream.listen(0, () => {
  process.env.ALLM_URL = `http://127.0.0.1:${upstream.address().port}`;
  delete require.cache[require.resolve('./server.js')];
  const { server } = require('./server.js');
  server.listen(0, () => {
    const port = server.address().port;
    const get = (path, headers = {}) => new Promise((ok) => http.get({ port, path, headers }, (r) => { let b = ''; r.on('data', (c) => (b += c)); r.on('end', () => ok({ r, b })); }));
    (async () => {
      const a = await get(WIDGET_PATH);
      assert.strictEqual(a.r.statusCode, 200);
      assert.strictEqual(a.b, SESSION_SHIM + 'WIDGET_V1();');
      const ours = widgetEtag(Buffer.from(a.b));
      assert.strictEqual(a.r.headers.etag, ours);
      assert.notStrictEqual(a.r.headers.etag, '"up-1"');
      assert.strictEqual(a.r.headers['cache-control'], 'no-cache');
      assert.strictEqual(a.r.headers['last-modified'], undefined);
      assert.strictEqual(a.r.headers['content-type'], 'application/javascript');
      assert.strictEqual(Number(a.r.headers['content-length']), Buffer.byteLength(a.b));
      // a browser holding upstream's OLD etag gets our shimmed bytes, from cache
      const b = await get(WIDGET_PATH, { 'If-None-Match': '"up-1"' });
      assert.strictEqual(b.r.statusCode, 200);
      assert.strictEqual(b.b, a.b);
      // a browser holding OUR etag gets a 304, from cache
      const n = await get(WIDGET_PATH, { 'If-None-Match': ours });
      assert.strictEqual(n.r.statusCode, 304);
      assert.strictEqual(n.b, '');
      assert.strictEqual(n.r.headers.etag, ours);
      // three widget requests, ONE full upstream body; the other two were conditional
      assert.strictEqual(upFullBodies, 1);
      assert.deepStrictEqual(upConditionals, [null, '"up-1"', '"up-1"']);
      // AnythingLLM upgraded: the next request gets the new bytes under a new etag
      upVersion = 2;
      const u = await get(WIDGET_PATH, { 'If-None-Match': ours });
      assert.strictEqual(u.r.statusCode, 200);
      assert.strictEqual(u.b, SESSION_SHIM + 'WIDGET_V2();');
      assert.notStrictEqual(u.r.headers.etag, ours);
      assert.strictEqual(upFullBodies, 2);
      const c = await get('/api/embed/x/other');
      assert.strictEqual(c.b, '{"other":true}');

      // 21. the upstream HOST is fixed by ALLM_URL; a request supplies only the
      //     path and query. An absolute-form target (GET http://other/x), a
      //     scheme-relative one (//other/x) and "/\other/x" (which the URL parser
      //     reads as //other/x) used to be proxied to "other". Each is now a 400,
      //     and the other host never sees a request.
      let evilHits = 0;
      const evil = http.createServer((req, res) => { evilHits++; res.writeHead(200); res.end('EVIL'); });
      await new Promise((ok) => evil.listen(0, '127.0.0.1', ok));
      const evilHost = `127.0.0.1:${evil.address().port}`;
      for (const target of [`http://${evilHost}/api/embed/x/stream-chat`, `//${evilHost}/api/embed/x/stream-chat`, `/\\${evilHost}/api/embed/x/stream-chat`]) {
        const r = await get(target);
        assert.strictEqual(r.r.statusCode, 400, `target ${target} must be refused`);
        assert.strictEqual(r.b, '{"error":"bad request target"}');
      }
      assert.strictEqual(evilHits, 0, 'no request may reach a host the client named');
      // a normal origin-form target still reaches the configured upstream, query intact
      const q = await get('/api/embed/x/other?a=1&b=2');
      assert.strictEqual(q.b, '{"other":true}');
      evil.close();

      // 22. weown-fleet#95: the PUBLIC chat-history endpoint is JSON, not SSE.
      //     Stored replies keep their reasoning block, so it must be stripped
      //     here too; every other field is kept, and a reply whose block never
      //     closes loses the rest rather than leaking it.
      const h = await get('/api/embed/x/session-1');
      assert.strictEqual(h.r.statusCode, 200);
      assert.ok(!h.b.includes('SECRET RULES'), `history leaked reasoning: ${h.b}`);
      const hist = JSON.parse(h.b).history;
      assert.deepStrictEqual(hist.map((m) => m.content), ['What do you charge?', 'We charge $100.', '']);
      assert.deepStrictEqual(hist[1].sources, []);
      assert.strictEqual(hist[1].sentAt, 2);
      assert.strictEqual(Number(h.r.headers['content-length']), Buffer.byteLength(h.b));
      //     a body that is not JSON passes through verbatim
      assert.strictEqual((await get('/api/embed/x/not-json')).b, 'not json {');
      server.close(); upstream.close();
      console.log('embed-filter: all 29 assertion groups passed');
    })().catch((e) => { console.error(e); process.exit(1); });
  });
});
