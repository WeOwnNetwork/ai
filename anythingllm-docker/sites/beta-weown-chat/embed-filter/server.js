// embed-filter — strip model reasoning blocks out of the PUBLIC embed API.
//
// WHY THIS EXISTS (2026-09-01, WO-Disc-961):
// A reasoning model emits its chain-of-thought inline in `textResponse` as
// <think>…</think>, and AnythingLLM passes it straight through. The chat
// WIDGET hides it, so on a rendered page everything looks fine — but
// `POST /api/embed/<id>/stream-chat` is UNAUTHENTICATED, and a plain curl
// against a customer's public bot returned 898 chars of private reasoning
// ahead of a 277-char answer, quoting the workspace SYSTEM PROMPT verbatim.
// That is system-prompt disclosure on a client's own website, not cosmetic
// noise, and "the widget strips it" is not a defence: the API is a consumer.
//
// So the strip happens SERVER-SIDE, in front of AnythingLLM, where every
// consumer benefits — curl, a third-party embed, a future mobile client.
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

const server = http.createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end('{"ok":true,"service":"embed-filter"}');
  }

  const target = new URL(req.url, ALLM_URL);
  const headers = { ...req.headers };
  headers.host = target.host;              // Origin/Referer stay verbatim —
  delete headers['accept-encoding'];       // ALLM's allowlist depends on them.

  const up = http.request(
    { hostname: target.hostname, port: target.port || 80, path: target.pathname + target.search, method: req.method, headers },
    (upRes) => {
      const ct = String(upRes.headers['content-type'] || '');
      const outHeaders = { ...upRes.headers };
      delete outHeaders['content-length'];  // we rewrite the body

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

module.exports = { makeStripper, filterDataLine, partialSuffixLen };
