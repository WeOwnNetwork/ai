// embed-filter — strip model reasoning blocks out of the PUBLIC embed API.
//
// WHY THIS EXISTS (2026-09-01, WO-Disc-961):
// A reasoning model emits its chain-of-thought inline in `textResponse` as
// <think>…</think>, and AnythingLLM passes it straight through.
//
// ESTABLISHED, 100% reproducible: `POST /api/embed/<id>/stream-chat` is
// UNAUTHENTICATED, and any caller with the embed id (it is in the page source)
// plus an `Origin` header gets the raw reasoning block — quoting the workspace
// SYSTEM PROMPT verbatim. Two lanes reproduced this independently, every
// attempt. That is what this filter exists for.
//
// NOT established: whether the WIDGET ever renders it to a visitor. One
// persisted occurrence, then four clean renders (including a clean-session
// replay of the exact sequence that produced it) and mid-stream DOM polling
// that never caught it. 1 in 5, mechanism unknown, not reproducible on demand.
// The one occurrence was real — still in innerText and HTML minutes later, a
// finished turn — so it is not dismissable either. Do not restate it as a
// property in either direction; the number is the honest form.
//
// Method note, because it cost two lanes an evening: grepping the DOM for
// "<think>" is the WRONG PREDICATE. It returns CLEAN whether the leak is
// absent or merely untagged. Probe the API, and read a rendered transcript —
// never a tag search, and never a greeting (the fallback path emits no
// reasoning at all, so a greeting "proves" a fix on a path that never broke).
//
// The strip therefore happens SERVER-SIDE, in front of AnythingLLM: upstream
// of the widget (so the visible path is closed too) and upstream of every
// other consumer — curl, a third-party embed, a future mobile client.
//
// LIMIT, so this is not over-trusted: it catches TAGGED reasoning. Untagged
// reasoning prose is undetectable downstream. The durable fix is model-level
// (a non-reasoning model, or OpenRouter `reasoning: exclude`); this is
// defence-in-depth.
//
// WHY A SEPARATE CONTAINER, and not the dashboard:
// The dashboard boots through the secret-store entrypoint and holds
// credentials. Routing the customer's public widget through it would mean an
// internal AppRole failure takes down the customer's WEBSITE — exactly the
// coupling #213/#214/#216 were about. This process holds NO secret, reads no
// store, and has no dependency that can fail closed: if it dies, only the
// embed is affected, and it cannot be the thing that dies for a credential
// reason. Same zero-npm-dependency, bind-mounted, no-build shape as
// template/dashboard/server.js.
//
// Env: PORT (3002), ALLM_URL (http://anythingllm:3001),
//      STRIP_TAGS (comma list, default "think,thinking,reasoning").
'use strict';

const http = require('http');
const { URL } = require('url');

const PORT = parseInt(process.env.PORT || '3002', 10);
const ALLM_URL = process.env.ALLM_URL || 'http://anythingllm:3001';
// The upstream host and port are fixed here, once. A request only ever supplies
// the path and query: new URL(req.url, ALLM_URL) let an absolute-form target
// ("GET http://other/x") or a scheme-relative one ("//other/x") pick the host.
const UPSTREAM = new URL(ALLM_URL);
const TAGS = (process.env.STRIP_TAGS || 'think,thinking,reasoning')
  .split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);

const OPENERS = TAGS.map((t) => `<${t}>`);
const CLOSER_FOR = new Map(TAGS.map((t) => [`<${t}>`, `</${t}>`]));

// Longest k < needle.length such that s ends with needle.slice(0, k).
// This is what makes the filter safe across chunk boundaries: a chunk ending
// in "<thi" must not be emitted, because the next chunk may complete the tag.
function partialSuffixLen(s, needle) {
  const max = Math.min(s.length, needle.length - 1);
  for (let k = max; k > 0; k--) {
    if (s.endsWith(needle.slice(0, k))) return k;
  }
  return 0;
}

// One of these per response. Streaming state machine: text arrives in
// arbitrary pieces and a tag may straddle any number of them.
function makeStripper() {
  let mode = 'normal';      // 'normal' | 'inside'
  let closer = null;        // the closing tag we are hunting while inside
  let pending = '';         // held-back tail that may be a partial tag
  let emitted = false;      // has any visible text been emitted yet

  return {
    feed(text) {
      let buf = pending + text;
      pending = '';
      let out = '';

      for (;;) {
        if (mode === 'normal') {
          let at = -1;
          let hit = null;
          for (const open of OPENERS) {
            const i = buf.indexOf(open);
            if (i !== -1 && (at === -1 || i < at)) { at = i; hit = open; }
          }
          if (at !== -1) {
            out += buf.slice(0, at);
            buf = buf.slice(at + hit.length);
            closer = CLOSER_FOR.get(hit);
            mode = 'inside';
            continue;
          }
          // Hold back the longest tail that could still become an opener.
          let keep = 0;
          for (const open of OPENERS) keep = Math.max(keep, partialSuffixLen(buf, open));
          out += keep ? buf.slice(0, buf.length - keep) : buf;
          pending = keep ? buf.slice(buf.length - keep) : '';
          break;
        }

        // inside a reasoning block: everything is discarded until the closer
        const end = buf.indexOf(closer);
        if (end !== -1) {
          buf = buf.slice(end + closer.length);
          mode = 'normal';
          closer = null;
          continue;
        }
        pending = buf.slice(buf.length - partialSuffixLen(buf, closer));
        break;
      }

      // A stripped block usually leaves the answer starting with "\n\n".
      if (!emitted) {
        out = out.replace(/^\s+/, '');
        if (out) emitted = true;
      }
      return out;
    },
    // Anything still held back at end-of-stream was never completed into a
    // tag, so it was ordinary text. Emit it rather than silently eating it.
    flush() {
      const rest = mode === 'normal' ? pending : '';
      pending = '';
      return rest;
    },
  };
}

// Rewrite the textResponse of one SSE `data:` payload, leaving every other
// field (id, type, sources, close, error) untouched. Unparseable lines pass
// through verbatim — this filter must never be the reason a stream breaks.
function filterDataLine(line, strip) {
  if (!line.startsWith('data:')) return line;
  const raw = line.slice(5).trim();
  if (!raw || raw === '[DONE]') return line;
  let obj;
  try { obj = JSON.parse(raw); } catch { return line; }
  if (typeof obj.textResponse !== 'string') return line;
  obj.textResponse = strip.feed(obj.textResponse);
  return `data: ${JSON.stringify(obj)}`;
}

// ── JSON responses (weown-fleet#95) ─────────────────────────────────────────
// The embed chat-HISTORY endpoint (GET /api/embed/<id>/<session>) is public and
// returns stored replies as JSON, reasoning block included. Strip the same tags
// from every `content` / `textResponse` string, keep every other field. A
// block that never closes drops the rest of that string (fail closed). The
// body is buffered to re-serialise it, so it is capped; over the cap is a 502,
// never the unfiltered bytes.
const MAX_JSON_BYTES = 16 * 1024 * 1024;
const stripText = (s) => { const st = makeStripper(); return st.feed(s) + st.flush(); };
function stripJson(v, key) {
  if (typeof v === 'string') return key === 'content' || key === 'textResponse' ? stripText(v) : v;
  if (Array.isArray(v)) return v.map((x) => stripJson(x, key));
  if (v && typeof v === 'object') {
    const out = {};
    for (const [k, x] of Object.entries(v)) out[k] = stripJson(x, k);
    return out;
  }
  return v;
}

// ── widget session policy (weown-fleet#92) ───────────────────────────────────
// The stock widget resumes its session id from localStorage FOREVER
// (anythingllm-embed useSessionId.js, no setting to change it). On a CPA's public
// site that shows the next visitor on a shared browser the previous person's
// conversation. Each instance serves the widget script itself, so routing that
// one file through here and prepending this shim fixes every host page at once,
// with no snippet change. Policy: a fresh chat on a new tab, on a RELOAD, on
// ARRIVING from outside the site (a typed URL, a bookmark, a search result, a
// link from another site — even in the same tab), or after TTL idle minutes
// (default 30). Moving between pages OF THE SAME SITE, and back/forward, keep
// the conversation. A reload counts as "loaded the site new" — Tyler's words for
// what should clear it. A tab duplicated from this one (sessionStorage is
// copied) keeps it within the TTL: same person, same browser, minutes apart.
// If a site sends no referrer at all, every page arrival counts as external, so
// it resets toward privacy, never away from it. Per embed:
// data-weown-session-ttl-minutes. ES5 and fully guarded: storage can throw
// (private mode, blocked cookies), and the widget must load regardless.
// KNOWN LIMIT: the widget keeps ONE session id per origin in localStorage, so
// two tabs open at once share it. True per-tab isolation needs the widget to
// support it (weown-fleet#92).
const crypto = require('crypto');
const WIDGET_PATH = '/embed/anythingllm-chat-widget.min.js';
const SESSION_SHIM =
  '/* weown session policy (weown-fleet#92) */\n' +
  '(function(){try{var s=document.currentScript,id=s&&s.getAttribute("data-embed-id");if(!id)return;' +
  'var ttl=parseInt(s.getAttribute("data-weown-session-ttl-minutes")||"30",10);if(!(ttl>0))ttl=30;' +
  'var L=window.localStorage,S=window.sessionStorage,K="allm_"+id+"_session_id",T="allm_"+id+"_last_seen",M="weown_"+id+"_tab";' +
  'var P=window.performance,nav=P&&P.getEntriesByType&&P.getEntriesByType("navigation")[0];' +
  'var reload=nav?nav.type==="reload":!!(P&&P.navigation&&P.navigation.type===1);' +
  'var back=nav?nav.type==="back_forward":!!(P&&P.navigation&&P.navigation.type===2);' +
  'var o=location.origin||(location.protocol+"//"+location.host),r=document.referrer||"";' +
  'var inSite=r===o||r.indexOf(o+"/")===0;' +
  'var now=Date.now(),seen=parseInt(L.getItem(T)||"0",10);' +
  'if(reload||(!back&&!inSite)||!S.getItem(M)||!seen||now-seen>ttl*60000)L.removeItem(K);' +
  'S.setItem(M,"1");L.setItem(T,String(now));' +
  'var bump=function(){try{L.setItem(T,String(Date.now()))}catch(e){}};' +
  'document.addEventListener("click",bump,true);document.addEventListener("keydown",bump,true);window.addEventListener("pagehide",bump);' +
  '}catch(e){}})();\n';
const shimWidget = (body) => SESSION_SHIM + body;
// Our own validator for the shimmed bytes. Upstream's ETag describes different
// bytes, so it cannot be reused; dropping validation entirely would make every
// page load re-download the ~650 KB widget instead of a 304.
const widgetEtag = (buf) => `W/"weown-${crypto.createHash('sha256').update(buf).digest('hex').slice(0, 20)}"`;
// One cached shimmed copy, keyed by upstream's ETag. Every page load revalidates
// (no-cache), so without this each one would pull the full widget from
// AnythingLLM just to answer 304. With it, upstream is asked conditionally and
// answers 304 until the widget itself changes (an AnythingLLM upgrade), which
// replaces the entry. Nothing here is per-visitor: the bytes are public.
let widgetCache = null; // { upEtag, contentType, body, etag }
const serveWidget = (res, c, clientEtag) => {
  const h = { etag: c.etag, 'cache-control': 'no-cache' };
  if (clientEtag.split(',').map((t) => t.trim()).includes(c.etag)) {
    res.writeHead(304, h);
    return res.end();
  }
  res.writeHead(200, { ...h, 'content-type': c.contentType, 'content-length': String(c.body.length) });
  return res.end(c.body);
};

const server = http.createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end('{"ok":true,"service":"embed-filter"}');
  }

  // Origin-form targets only: one leading "/" not followed by another "/" or a
  // backslash (the URL parser reads "/\x" as "//x"). Anything else is refused.
  const rawUrl = String(req.url || '');
  if (!/^\/(?![/\\])/.test(rawUrl)) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    return res.end('{"error":"bad request target"}');
  }
  const target = new URL(rawUrl, 'http://embed-filter.invalid'); // path + query only
  const headers = { ...req.headers };
  headers.host = UPSTREAM.host;            // Origin/Referer stay verbatim —
  delete headers['accept-encoding'];       // ALLM's allowlist depends on them.
  const isWidget = req.method === 'GET' && target.pathname === WIDGET_PATH;
  const clientEtag = isWidget ? String(req.headers['if-none-match'] || '') : '';
  if (isWidget) {                          // the client's validators describe OUR
    delete headers['if-none-match'];       // bytes, not upstream's: ask upstream
    delete headers['if-modified-since'];   // only about the copy we hold
    if (widgetCache && widgetCache.upEtag) headers['if-none-match'] = widgetCache.upEtag;
  }

  const up = http.request(
    { hostname: UPSTREAM.hostname, port: UPSTREAM.port || 80, path: target.pathname + target.search, method: req.method, headers },
    (upRes) => {
      const ct = String(upRes.headers['content-type'] || '');
      const outHeaders = { ...upRes.headers };
      delete outHeaders['content-length'];  // we rewrite the body

      // Widget script: served from our cache on an upstream 304, rebuilt on a 200.
      // Headers are built fresh (serveWidget), never copied from upstream: its
      // ETag, Last-Modified, Transfer-Encoding and Cache-Control all describe
      // different bytes or a policy that would keep a stale unshimmed copy alive.
      if (isWidget && upRes.statusCode === 304 && widgetCache) {
        upRes.resume();
        return serveWidget(res, widgetCache, clientEtag);
      }
      if (isWidget && upRes.statusCode === 200) {
        const chunks = [];
        upRes.on('data', (c) => chunks.push(c));
        upRes.on('end', () => {
          const body = Buffer.from(shimWidget(Buffer.concat(chunks).toString('utf8')), 'utf8');
          widgetCache = {
            upEtag: upRes.headers.etag || null,
            contentType: ct || 'application/javascript',
            body,
            etag: widgetEtag(body),
          };
          serveWidget(res, widgetCache, clientEtag);
        });
        upRes.on('error', () => res.end());
        return;
      }

      if (/^application\/json/i.test(ct)) {
        const chunks = [];
        let size = 0;
        upRes.on('data', (c) => {
          size += c.length;
          if (size > MAX_JSON_BYTES) { upRes.destroy(); return; }
          chunks.push(c);
        });
        upRes.on('close', () => {
          if (res.headersSent) return;
          if (size > MAX_JSON_BYTES || !upRes.complete) {
            res.writeHead(502, { 'Content-Type': 'application/json' });
            return res.end('{"error":"embed upstream response too large or incomplete"}');
          }
          let body = Buffer.concat(chunks);
          try { body = Buffer.from(JSON.stringify(stripJson(JSON.parse(body.toString('utf8')))), 'utf8'); } catch { /* not JSON: verbatim */ }
          delete outHeaders['transfer-encoding'];
          res.writeHead(upRes.statusCode, { ...outHeaders, 'content-length': String(body.length) });
          res.end(body);
        });
        return;
      }

      if (!/text\/event-stream/i.test(ct)) {
        res.writeHead(upRes.statusCode, outHeaders);
        return upRes.pipe(res);
      }

      res.writeHead(upRes.statusCode, outHeaders);
      const strip = makeStripper();
      let carry = '';
      upRes.setEncoding('utf8');
      upRes.on('data', (chunk) => {
        carry += chunk;
        // Emit only whole lines; a split mid-JSON must not be parsed.
        const nl = carry.lastIndexOf('\n');
        if (nl === -1) return;
        const ready = carry.slice(0, nl + 1);
        carry = carry.slice(nl + 1);
        res.write(ready.split('\n').map((l) => filterDataLine(l, strip)).join('\n'));
      });
      upRes.on('end', () => {
        if (carry) res.write(filterDataLine(carry, strip));
        const tail = strip.flush();
        if (tail) res.write(`\ndata: ${JSON.stringify({ type: 'textResponseChunk', textResponse: tail, close: false, error: false })}\n\n`);
        res.end();
      });
      upRes.on('error', () => res.end());
    },
  );

  up.on('error', () => {
    if (!res.headersSent) res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end('{"error":"embed upstream unavailable"}');
  });

  req.pipe(up);
});

// Only listen when run as the entrypoint, so test.js can require the pure
// functions without starting a socket.
if (require.main === module) {
  server.listen(PORT, () => console.log(`embed-filter listening on ${PORT} -> ${ALLM_URL} (stripping ${OPENERS.join(' ')})`));
}

module.exports = { makeStripper, filterDataLine, stripJson, partialSuffixLen, shimWidget, widgetEtag, SESSION_SHIM, WIDGET_PATH, server };
