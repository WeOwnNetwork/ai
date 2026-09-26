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
const shim = ({ local = {}, session = {}, attrs = { 'data-embed-id': ID }, broken = false, nav = 'navigate' } = {}) => {
  const L = store(local, broken), S = store(session, broken);
  const script = { getAttribute: (a) => (a in attrs ? attrs[a] : null) };
  const performance = nav === null ? undefined : { getEntriesByType: (t) => (t === 'navigation' ? [{ type: nav }] : []) };
  const ctx = { window: { localStorage: L, sessionStorage: S, performance, addEventListener() {} }, document: { currentScript: script, addEventListener() {} }, Date: { now: () => NOW }, parseInt, String };
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
//     - other paths pass through byte for byte.
const http = require('http');
const upstream = http.createServer((req, res) => {
  if (req.url === WIDGET_PATH) {
    if (req.headers['if-none-match']) { res.writeHead(304); return res.end(); }
    res.writeHead(200, { 'Content-Type': 'application/javascript', ETag: '"up-1"', 'Last-Modified': 'Mon, 01 Jan 2026 00:00:00 GMT' });
    return res.end('WIDGET();');
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
      assert.strictEqual(a.b, SESSION_SHIM + 'WIDGET();');
      const ours = widgetEtag(Buffer.from(a.b));
      assert.strictEqual(a.r.headers.etag, ours);
      assert.notStrictEqual(a.r.headers.etag, '"up-1"');
      assert.strictEqual(a.r.headers['cache-control'], 'no-cache');
      assert.strictEqual(a.r.headers['last-modified'], undefined);
      assert.strictEqual(Number(a.r.headers['content-length']), Buffer.byteLength(a.b));
      const b = await get(WIDGET_PATH, { 'If-None-Match': '"up-1"' });
      assert.strictEqual(b.r.statusCode, 200);
      assert.ok(b.b.startsWith('/* weown session policy'));
      const n = await get(WIDGET_PATH, { 'If-None-Match': ours });
      assert.strictEqual(n.r.statusCode, 304);
      assert.strictEqual(n.b, '');
      assert.strictEqual(n.r.headers.etag, ours);
      const c = await get('/api/embed/x/other');
      assert.strictEqual(c.b, '{"other":true}');
      server.close(); upstream.close();
      console.log('embed-filter: all 23 assertion groups passed');
    })().catch((e) => { console.error(e); process.exit(1); });
  });
});
