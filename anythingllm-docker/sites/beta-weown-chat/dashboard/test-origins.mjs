// Embed-allowlist origins: normOrigin() refuses userinfo (user:pw@ / trusted@evil) origins, and
// the /api/embed-domains POST names a rejected entry by POSITION, never echoing it (an entry can
// carry a password). Runs the REAL code from server.js (extracted, not copied). #272/#276 review.
// Usage (from this directory): node test-origins.mjs
import { readFileSync } from 'node:fs';
const src = readFileSync('server.js', 'utf8');
const grab = (re) => { const m = src.match(re); return m ? m[0] : ''; };
let fail = 0;
const ok = (m) => console.log(`ok   ${m}`);
const bad = (m) => { console.log(`FAIL ${m}`); fail = 1; };

const norm = grab(/const normOrigin = \(raw\) => \{[\s\S]*?\n\};/);
if (!norm) { console.log('FAIL: normOrigin not found in server.js'); process.exit(1); }
const normOrigin = new Function(`${norm}; return normOrigin;`)();
// Hand-derived: the scheme and host are kept, a path is dropped, localhost and any userinfo are refused.
for (const [inp, want] of [
  ['a.example.test', 'https://a.example.test'],
  ['HTTPS://B.Example.Test/some/page', 'https://b.example.test'],
  ['http://a.example.test:8080', 'http://a.example.test:8080'],
  ['localhost', null],
  ['https://trusted.example@evil.example', null],
  ['trusted.example@evil.example', null],
  ['https://user:pw@a.example.test', null],
]) {
  const got = normOrigin(inp);
  got === want ? ok(`normOrigin ${JSON.stringify(inp)} -> ${JSON.stringify(got)}`)
    : bad(`normOrigin ${JSON.stringify(inp)} -> ${JSON.stringify(got)} (want ${JSON.stringify(want)})`);
}

// The POST handler's validation lines, from `const input =` through its 400 `send`, with a stub send().
const helper = grab(/const unusableDomainsError = \(input\) => \{[\s\S]*?\n\};/);
const post = src.indexOf("if (p === '/api/embed-domains' && req.method === 'POST')");
const from = src.indexOf('const input = Array.isArray(body.domains)', post);
const to = src.indexOf('\n', src.indexOf('send(res, 400', from));
if (post < 0 || from < 0 || to < 0) { console.log('FAIL: /api/embed-domains POST validation not found'); process.exit(1); }
const handler = new Function('body', 'send', 'res', `${norm}\n${helper}\n${src.slice(from, to)}\nreturn null;`);
const run = (domains) => { let out = null; handler({ domains }, (_r, code, obj) => { out = { code, ...obj }; return out; }, {}); return out; };
const r1 = run(['a.example.test', 'https://user:SECRETPW@evil.example']);
if (!r1 || r1.code !== 400) bad(`userinfo entry not rejected: ${JSON.stringify(r1)}`);
else if (r1.error.includes('SECRETPW') || r1.error.includes('evil.example')) bad(`400 echoes the rejected entry: ${r1.error}`);
else ok('400 without echoing the rejected entry');
r1 && /entry 2\b/.test(r1.error) ? ok('400 names the rejected entry by position (entry 2)') : bad(`position missing: ${r1 && r1.error}`);
run(['a.example.test', 'b.example.test']) === null ? ok('usable entries pass') : bad('usable entries rejected');

if (fail) process.exit(1);
console.log('all checks pass');
