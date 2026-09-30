// Extract embed appearance / booking helpers from server.js and exercise them.
import { readFileSync, writeFileSync, renameSync, mkdirSync, rmSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

const src = readFileSync('server.js', 'utf8');

function extract(name, pattern) {
  const m = src.match(pattern);
  if (!m) {
    console.error(`FAIL: could not extract ${name}`);
    process.exit(1);
  }
  return m[0];
}
function asFn(name, pattern) {
  return eval(
    '(' + extract(name, pattern).replace(new RegExp('^const ' + name + ' = '), '').replace(/;$/, '') + ')'
  );
}

const validateBookingUrl = asFn('validateBookingUrl', /const validateBookingUrl = \(raw\) => \{[\s\S]*?\n\};/);
const isHexColor = asFn('isHexColor', /const isHexColor = \(s\) => [^;\n]+;/);
const svgLooksSafe = asFn('svgLooksSafe', /const svgLooksSafe = \(buf\) => \{[\s\S]*?\n\};/);

const themeBundle = new Function(
  extract('isHexColor', /const isHexColor = \(s\) => [^;\n]+;/) + '\n' +
  extract('CHAT_ICONS', /const CHAT_ICONS = new Set\(\[[^\]]+\]\);/) + '\n' +
  extract('EMBED_THEMES', /const EMBED_THEMES = \{[\s\S]*?\n\};/) + '\n' +
  extract('DEFAULT_THEME_ID', /const DEFAULT_THEME_ID = '[^']+';/) + '\n' +
  extract('resolveTheme', /const resolveTheme = \(app\) => \{[\s\S]*?\n\};/) + '\n' +
  'return { EMBED_THEMES, DEFAULT_THEME_ID, resolveTheme };'
)();
const { EMBED_THEMES, resolveTheme } = themeBundle;

const escAttr = (s) => String(s || '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
if (!src.includes('const escAttr')) {
  console.error('FAIL: escAttr missing from server.js');
  process.exit(1);
}

let bad = 0;
const check = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name}`);
  if (!ok) console.log('       got=', got, 'want=', want);
};

check('empty URL ok (clears CTA)', validateBookingUrl(''), { ok: true, url: '' });
check('https ok', validateBookingUrl('https://cal.com/practice'), { ok: true, url: 'https://cal.com/practice' });
check('http localhost ok', validateBookingUrl('http://localhost:3000/book'), { ok: true, url: 'http://localhost:3000/book' });
check('http 127.0.0.1 ok', validateBookingUrl('http://127.0.0.1/x'), { ok: true, url: 'http://127.0.0.1/x' });
check('http non-local rejected', validateBookingUrl('http://example.com').ok, false);
check('javascript: rejected', validateBookingUrl('javascript:alert(1)').ok, false);
check('garbage rejected', validateBookingUrl('not a url').ok, false);
check('data: rejected', validateBookingUrl('data:text/html,hi').ok, false);

check('hex valid', isHexColor('#00A3FF'), true);
check('hex invalid short', isHexColor('#fff'), false);
check('softlight present', !!EMBED_THEMES.softlight, true);
check('softlight assistant slate', EMBED_THEMES.softlight.assistantBgColor, '#f1f5f9');
check('five curated themes', Object.keys(EMBED_THEMES).sort(), ['forest', 'harbor', 'midnight', 'softlight', 'weown']);

const soft = resolveTheme({ themeId: 'softlight', accentOverride: '' });
check('resolve softlight id', soft.id, 'softlight');
check('resolve softlight assistant', soft.assistantBgColor, '#f1f5f9');
const accented = resolveTheme({ themeId: 'weown', accentOverride: '#112233' });
check('accent overrides button only', accented.buttonColor, '#112233');
check('accent leaves user bg', accented.userBgColor, EMBED_THEMES.weown.userBgColor);

check('plain svg safe', svgLooksSafe(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"></svg>')), true);
check('script svg unsafe', svgLooksSafe(Buffer.from('<svg><script>alert(1)</script></svg>')), false);
check('onclick svg unsafe', svgLooksSafe(Buffer.from('<svg><rect onclick="x"/></svg>')), false);
check('external href unsafe', svgLooksSafe(Buffer.from('<svg><a href="https://evil"></a></svg>')), false);

check('snippet injects booking companion', src.includes('weown-booking-cta') && src.includes('if (booking.url)'), true);
check('snippet keeps data-no-sponsor', src.includes('data-no-sponsor="true"'), true);
check('snippet injects brand image', src.includes('data-brand-image-url'), true);

function buildSnippet({ embedId, domain, booking, theme }) {
  const brandUrl = `https://${domain}/app/brand/weownchat-mark.svg`;
  let snippet =
    `<script data-embed-id="${escAttr(embedId)}"\n` +
    `  data-base-api-url="https://${escAttr(domain)}/api/embed"\n` +
    `  data-brand-image-url="${escAttr(brandUrl)}"\n` +
    `  data-button-color="${escAttr(theme.buttonColor)}"\n` +
    `  data-no-sponsor="true"\n` +
    `  src="https://${escAttr(domain)}/embed/anythingllm-chat-widget.min.js"><\/script>`;
  if (booking.url) {
    snippet += `\n<script>(function(){var u=${JSON.stringify(booking.url)};` +
      `/* weown-booking-cta */})();<\/script>`;
  }
  return snippet;
}

const theme = resolveTheme({ themeId: 'softlight', accentOverride: '' });
const withBooking = buildSnippet({
  embedId: 'emb_test', domain: 'chat.example.com',
  booking: { url: 'https://cal.com/x', label: 'Book a call' }, theme,
});
const withoutBooking = buildSnippet({
  embedId: 'emb_test', domain: 'chat.example.com',
  booking: { url: '', label: '' }, theme,
});
// Match the exact JS literal the companion script assigns (a bare substring
// test on a URL is what CodeQL js/incomplete-url-substring-sanitization flags).
check('snippet contains booking when set', withBooking.includes('weown-booking-cta') && /var u="https:\/\/cal\.com\/x";/.test(withBooking), true);
check('snippet omits booking when cleared', !withoutBooking.includes('weown-booking-cta'), true);
check('snippet softlight button color', withBooking.includes('#0369a1'), true);
check('snippet always no-sponsor', withBooking.includes('data-no-sponsor="true"') && withoutBooking.includes('data-no-sponsor="true"'), true);

const stateDir = mkdtempSync(path.join(tmpdir(), 'embed-app-'));
try {
  const APPEARANCE_FILE = path.join(stateDir, 'embed-appearance.json');
  const BOOKING_FILE = path.join(stateDir, 'booking.json');
  const writeAtomic = (file, payload) => {
    mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.${process.pid}.tmp`;
    writeFileSync(tmp, JSON.stringify(payload, null, 2));
    renameSync(tmp, file);
  };
  writeAtomic(APPEARANCE_FILE, { themeId: 'softlight', accentOverride: '', assistantName: 'Harbor', logo: null });
  writeAtomic(BOOKING_FILE, { url: 'https://cal.com/y', label: 'Book a call' });
  check('appearance persisted theme', JSON.parse(readFileSync(APPEARANCE_FILE, 'utf8')).themeId, 'softlight');
  check('booking persisted url', JSON.parse(readFileSync(BOOKING_FILE, 'utf8')).url, 'https://cal.com/y');
  writeAtomic(BOOKING_FILE, { url: '', label: '' });
  check('booking clear persists empty', JSON.parse(readFileSync(BOOKING_FILE, 'utf8')).url, '');
} finally {
  rmSync(stateDir, { recursive: true, force: true });
}

const html = readFileSync('public/index.html', 'utf8');
check('UI Soft Light / softlight present', html.includes('Soft Light') || html.includes('softlight'), true);
check('UI appearance card', html.includes('id="widget-appearance"'), true);
check('UI booking card', html.includes('id="booking-button"'), true);
check('UI hours sample', html.includes('What are your hours?'), true);
check('UI nav booking jump', html.includes('href="#booking-button"'), true);


// --- P1 follow-ups: Soft Light contrast, SVG harden, booking re-read ---
function relativeLuminance(hex){
  const h = String(hex||'').replace('#','');
  const toLin = (c) => { const v = parseInt(c,16)/255; return v<=0.03928 ? v/12.92 : ((v+0.055)/1.055)**2.4; };
  const r=toLin(h.slice(0,2)), g=toLin(h.slice(2,4)), b=toLin(h.slice(4,6));
  return 0.2126*r + 0.7152*g + 0.0722*b;
}
function contrastRatio(bg, fg){
  const L1 = relativeLuminance(bg), L2 = relativeLuminance(fg);
  const hi = Math.max(L1,L2), lo = Math.min(L1,L2);
  return (hi+0.05)/(lo+0.05);
}
{
  const m2 = src.match(/softlight:\s*\{[\s\S]*?buttonColor:\s*'([^']+)',\s*userBgColor:\s*'([^']+)',\s*assistantBgColor:\s*'([^']+)'/);
  if (!m2) { console.error('FAIL softlight theme block'); process.exit(1); }
  const [, btn, user, asst] = m2;
  check('softlight user contrast vs white ≥ 4.5', contrastRatio(user, '#ffffff') >= 4.5, true);
  check('softlight button contrast vs white ≥ 4.5', contrastRatio(btn, '#ffffff') >= 4.5, true);
  check('softlight assistant stays #f1f5f9', asst, '#f1f5f9');
}
check('svg rejects protocol-relative href', svgLooksSafe(Buffer.from('<svg><a href="//evil.com">x</a></svg>')), false);
check('svg rejects @import style', svgLooksSafe(Buffer.from('<svg><style>@import url(https://evil)</style></svg>')), false);
check('svg rejects SMIL set onclick', svgLooksSafe(Buffer.from('<svg><set attributeName="onclick" to="alert(1)"/></svg>')), false);

check('https userinfo rejected', validateBookingUrl('https://user:password@example.com/book').ok, false);
check('https user only rejected', validateBookingUrl('https://user@example.com/book').ok, false);
check('jsonForScript escapes < for script embed', src.includes('jsonForScript') && /jsonForScript[\s\S]{0,80}\\u003c/.test(src), true);
check('UI appearance dirty hooks use real field ids', /\['accent-hex','accent-color','assistant-name'\]/.test(html), true);
check('UI booking dirty hooks use real field ids', /\['booking-url','booking-label'\]/.test(html), true);

check('readBooking re-validates on read', src.includes('booking.json URL rejected on read') && src.includes('validateBookingUrl(rawUrl)'), true);


// --- review sweep (2026-09-29): booking ink, SVG sanitiser, per-card dirty flags ---

// contrastInk — the booking CTA label ink. Expected values are derived BY HAND
// from the WCAG 2.x formulas (sRGB linearise, L = .2126R + .7152G + .0722B,
// ratio = (L1 + .05) / (L2 + .05)); they are not read back from the code.
//   #0f172a (dark ink) L = 0.00882;  #ffffff L = 1.
//   Break-even: (L + .05)^2 = 1.05 x 0.05882  =>  L = 0.1985.
//   fill      name         L        white   dark    => ink
//   #c9a227   Harbor Gold  0.3841   2.42    7.38    => dark
//   #00A3FF   WeOwn        0.3342   2.73    6.53    => dark
//   #334155   Midnight     0.0514  10.36    1.72    => white
//   #0369a1   Soft Light   0.1269   5.93    3.01    => white
//   #2d6a4f   Forest       0.1143   6.39    2.79    => white
//   #767676   grey         0.1812   4.54    3.93    => white  (just below break-even)
//   #808080   grey         0.2159   3.95    4.52    => dark   (just above)
//   #ffffff / #000000                                => dark / white
const INK_CASES = [
  ['#c9a227', 'Harbor Gold', 2.42, 7.38, '#0f172a'],
  ['#00A3FF', 'WeOwn', 2.73, 6.53, '#0f172a'],
  ['#334155', 'Midnight', 10.36, 1.72, '#fff'],
  ['#0369a1', 'Soft Light', 5.93, 3.01, '#fff'],
  ['#2d6a4f', 'Forest', 6.39, 2.79, '#fff'],
  ['#767676', 'grey 76', 4.54, 3.93, '#fff'],
  ['#808080', 'grey 80', 3.95, 4.52, '#0f172a'],
  ['#ffffff', 'white', 1.0, 17.85, '#0f172a'],
  ['#000000', 'black', 21.0, 1.18, '#fff'],
];
// The hand numbers are checked against an independent implementation first,
// so a slip in the arithmetic above cannot pass silently.
for (const [hex, name, white, dark] of INK_CASES) {
  check(`hand ratio ${name} vs white = ${white}`, Math.abs(contrastRatio(hex, '#ffffff') - white) < 0.01, true);
  check(`hand ratio ${name} vs dark = ${dark}`, Math.abs(contrastRatio(hex, '#0f172a') - dark) < 0.01, true);
}
const contrastInk = new Function(
  extract('contrastInk', /const hexLuminance = [\s\S]*?(?=\n\/\/ Serialize appearance)/) + '\nreturn contrastInk;'
)();
const ink6 = (ink) => ({ '#fff': '#ffffff', '#000': '#000000' }[ink] || ink);
for (const [hex, name, , , want] of INK_CASES) check(`contrastInk ${name} ${hex}`, contrastInk(hex), want);
for (const t of Object.values(EMBED_THEMES)) {
  const ink = contrastInk(t.buttonColor);
  check(`booking CTA on ${t.name} meets 4.5:1`, contrastRatio(t.buttonColor, ink6(ink)) >= 4.5, true);
}

// Mid-tone gap (review PRRT_kwDOPOa9686nZ8DD): neither slate nor white reaches
// 4.5:1 when 0.1833 < L < 0.2147 (white >= 4.5 needs L + .05 <= 1.05/4.5;
// slate >= 4.5 needs L + .05 >= 4.5 x 0.05882). Pure black reaches 4.5:1 for
// L >= 0.175, so it covers the whole gap. Hand-derived:
//   fill      L        white  slate  black  => ink
//   #777777   0.1845   4.48   3.99   4.69   => black
//   #7a7a7a   0.1946   4.29   4.16   4.89   => black
//   #7f7f7f   0.2122   4.00   4.46   5.24   => black
// (#767676 -> white 4.54 and #808080 -> slate 4.52 sit just outside the gap.)
const GAP_CASES = [
  ['#777777', 4.48, 3.99, 4.69],
  ['#7a7a7a', 4.29, 4.16, 4.89],
  ['#7f7f7f', 4.00, 4.46, 5.24],
];
for (const [hex, white, slate, black] of GAP_CASES) {
  check(`hand ratios ${hex} white/slate/black = ${white}/${slate}/${black}`,
    [contrastRatio(hex, '#ffffff'), contrastRatio(hex, '#0f172a'), contrastRatio(hex, '#000000')]
      .map((v, i) => Math.abs(v - [white, slate, black][i]) < 0.01), [true, true, true]);
  check(`contrastInk ${hex} (mid-tone) = black`, contrastInk(hex), '#000');
}
{ // every grey, and every 17-step color, gets an ink at or above 4.5:1
  const low = [];
  const tryHex = (hex) => { if (contrastRatio(hex, ink6(contrastInk(hex))) < 4.5) low.push(hex); };
  for (let v = 0; v < 256; v++) tryHex('#' + v.toString(16).padStart(2, '0').repeat(3));
  for (let r = 0; r < 256; r += 17) for (let g = 0; g < 256; g += 17) for (let b = 0; b < 256; b += 17)
    tryHex('#' + [r, g, b].map((x) => x.toString(16).padStart(2, '0')).join(''));
  check('contrastInk >= 4.5:1 on all 256 greys + 4096 grid colors', low.slice(0, 5), []);
}

// SVG sanitiser: payloads the old raw-source regexes let through.
const svg = (body) => Buffer.from(body);
const SVG_NS = 'xmlns="http://www.w3.org/2000/svg"';
check('svg rejects entity-encoded javascript href',
  svgLooksSafe(svg(`<svg ${SVG_NS} xmlns:xlink="http://www.w3.org/1999/xlink"><a xlink:href="j&#x61;vascript:alert(1)"><rect width="9" height="9"/></a></svg>`)), false);
check('svg rejects decimal char ref',
  svgLooksSafe(svg(`<svg ${SVG_NS}><a href="&#106;avascript:alert(1)"><rect width="9" height="9"/></a></svg>`)), false);
check('svg rejects namespace-prefixed script',
  svgLooksSafe(svg(`<svg ${SVG_NS}><x:script xmlns:x="http://www.w3.org/2000/svg">alert(1)</x:script></svg>`)), false);
check('svg rejects DTD entity split across names',
  svgLooksSafe(svg(`<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY a "java"><!ENTITY b "script:alert(1)">]><svg ${SVG_NS}><a href="&a;&b;"><rect width="9" height="9"/></a></svg>`)), false);
check('svg rejects bare DOCTYPE', svgLooksSafe(svg(`<!DOCTYPE svg><svg ${SVG_NS}></svg>`)), false);
check('svg rejects xml-stylesheet PI', svgLooksSafe(svg(`<?xml-stylesheet href="/x.css"?><svg ${SVG_NS}></svg>`)), false);
check('svg rejects non-UTF-8 encoding', svgLooksSafe(svg(`<?xml version="1.0" encoding="UTF-7"?><svg ${SVG_NS}></svg>`)), false);
check('svg rejects backslash protocol-relative href', svgLooksSafe(svg(`<svg ${SVG_NS}><image href="\\\\evil.example/x.png"/></svg>`)), false);
check('svg rejects relative href', svgLooksSafe(svg(`<svg ${SVG_NS}><image href="/app/api/snippet"/></svg>`)), false);
check('svg rejects external url()', svgLooksSafe(svg(`<svg ${SVG_NS}><rect fill="url(https://evil.example/p.svg#g)"/></svg>`)), false);
check('svg rejects SMIL href retarget', svgLooksSafe(svg(`<svg ${SVG_NS}><a><animate attributeName="href" values="#a"/></a></svg>`)), false);
check('svg rejects self-closed script', svgLooksSafe(svg(`<svg ${SVG_NS}><script/></svg>`)), false);
check('svg rejects NUL byte', svgLooksSafe(svg(`<svg ${SVG_NS}><scr\u0000ipt>alert(1)</scr\u0000ipt></svg>`)), false);
// ...and a normal logo still passes: gradient, fragment refs, XML decl, &amp;.
check('svg allows ordinary logo', svgLooksSafe(svg(
  `<?xml version="1.0" encoding="UTF-8"?><svg ${SVG_NS} xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 64 64">` +
  `<defs><linearGradient id="g"><stop offset="0" stop-color="#00A3FF"/></linearGradient><path id="p" d="M0 0h8v8z"/></defs>` +
  `<rect width="64" height="64" rx="12" fill="url(#g)"/><use xlink:href="#p"/><use href="#p"/><text x="8" y="40">Harbor &amp; Co</text></svg>`)), true);

// ── dashboard UI, run for real: the appearance/booking/snippet section of
// public/index.html executed against a minimal fake DOM and stubbed API.
function uiHarness() {
  const start = html.indexOf('  // ── embed appearance + booking + snippet');
  const end = html.indexOf('  // ── identity (sidebar avatar');
  if (start < 0 || end < 0) { console.error('FAIL: could not slice the appearance UI'); process.exit(1); }
  const slice = html.slice(start, end);
  class El {
    constructor(tag, id) {
      this.tagName = tag; this.id = id; this.style = {}; this.dataset = {}; this.children = [];
      this.value = ''; this.textContent = ''; this.className = ''; this.listeners = {}; this.attrs = {}; this.files = null;
      const cls = new Set();
      this.classList = { add: (c) => cls.add(c), remove: (c) => cls.delete(c), contains: (c) => cls.has(c) };
    }
    get firstChild() { return this.children[0] || null; }
    appendChild(c) { this.children.push(c); return c; }
    removeChild(c) { this.children = this.children.filter((x) => x !== c); return c; }
    setAttribute(k, v) { this.attrs[k] = String(v); }
    addEventListener(t, f) { (this.listeners[t] ||= []).push(f); }
    closest() { return null; }
    click() { return this.fire('click'); }
    async fire(t, ev = {}) { for (const f of this.listeners[t] || []) await f.call(this, { target: this, ...ev }); }
  }
  const byId = new Map();
  const document = {
    getElementById: (id) => { if (!byId.has(id)) byId.set(id, new El('div', id)); return byId.get(id); },
    createElement: (t) => new El(t), createElementNS: (_ns, t) => new El(t),
  };
  const clipboard = [];
  const navigator = { clipboard: { writeText: async (t) => { clipboard.push(t); } } };
  const saved = { themeId: 'harbor', accentOverride: '', assistantName: '', bookingUrl: 'https://cal.com/saved', bookingLabel: 'Book a call' };
  const THEMES = [
    { id: 'harbor', name: 'Harbor Gold', blurb: '', buttonColor: '#c9a227', userBgColor: '#c9a227', assistantBgColor: '#1c1917', chatIcon: 'magic' },
    { id: 'midnight', name: 'Midnight', blurb: '', buttonColor: '#334155', userBgColor: '#475569', assistantBgColor: '#0f172a', chatIcon: 'chatBubble' },
  ];
  const appearanceResp = () => {
    const t = THEMES.find((x) => x.id === saved.themeId);
    return { themeId: saved.themeId, accentOverride: saved.accentOverride, assistantName: saved.assistantName,
      hasCustomLogo: false, logoUrl: '', themes: THEMES, persisted: true,
      resolved: { ...t, buttonColor: saved.accentOverride || t.buttonColor } };
  };
  const api = [];
  const holds = {}; // `${m} ${u}` -> promise the stub waits on (request in flight)
  const j = async (m, u, b) => {
    api.push(`${m} ${u}`);
    if (holds[`${m} ${u}`]) { const h = holds[`${m} ${u}`]; delete holds[`${m} ${u}`]; await h; }
    if (m === 'GET' && u === '/api/embed-appearance') return appearanceResp();
    if (m === 'GET' && u === '/api/booking') return { url: saved.bookingUrl, label: saved.bookingLabel };
    if (m === 'GET' && u === '/api/snippet') return { snippet: `SNIPPET theme=${saved.themeId} booking=${saved.bookingUrl}` };
    if (m === 'POST' && u === '/api/embed-appearance') { Object.assign(saved, { themeId: b.themeId, accentOverride: b.accentOverride, assistantName: b.assistantName }); return appearanceResp(); }
    if (m === 'POST' && u === '/api/booking') { saved.bookingUrl = b.url; saved.bookingLabel = b.label; return { ok: true, url: b.url, label: b.label, persisted: true }; }
    return { error: `unexpected ${m} ${u}` };
  };
  const fetch = async () => ({ status: 200, json: async () => ({ ok: true, logoUrl: '/app/brand/logo?v=1' }) });
  const clearEl = (n) => { while (n.firstChild) n.removeChild(n.firstChild); };
  const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; };
  const location = { pathname: '/app/', reload() {} };
  const api_ = new Function('document', 'navigator', 'window', 'location', 'fetch', 'setTimeout', 'j', 'B', 'clearEl', 'el',
    '"use strict";\n' + slice + '\nreturn { loadAppearance, loadBooking, loadSnippet };')(
    document, navigator, {}, location, fetch, () => 0, j, '/app', clearEl, el);
  const $ = (id) => document.getElementById(id);
  return {
    $, clipboard, saved, api,
    // Hold the next m+u response until release() is called.
    hold: (mu) => { let release; holds[mu] = new Promise((r) => { release = r; }); return release; },
    init: () => api_.loadAppearance().then(api_.loadBooking).then(api_.loadSnippet),
    type: async (id, v) => { $(id).value = v; await $(id).fire('input'); },
    copy: async () => { const before = clipboard.length; await $('copy-snippet').fire('click'); return { copied: clipboard.length > before, label: $('copy-label').textContent }; },
    pickTheme: (id) => $('theme-grid').fire('click', { target: { closest: () => ({ dataset: { themeId: id } }) } }),
  };
}

{ // preview booking ink follows the real CTA's rule
  const ui = uiHarness(); await ui.init();
  check('preview booking shown', ui.$('mini-book').style.display, '');
  check('preview booking fill = Harbor Gold', ui.$('mini-book').style.background, '#c9a227');
  check('preview booking ink on Harbor Gold = dark (7.38:1)', ui.$('mini-book').style.color, '#0f172a');
  await ui.pickTheme('midnight');
  check('preview booking ink on Midnight = white (10.36:1)', ui.$('mini-book').style.color, '#fff');
  ui.saved.accentOverride = '#7a7a7a'; await ui.init();
  check('preview booking ink on #7a7a7a = black (4.89:1)', ui.$('mini-book').style.color, '#000');
}
{ // the client copy of the rule agrees with the server on every 4-bit-per-channel color
  const ui = uiHarness(); await ui.init();
  const mismatches = [];
  for (let r = 0; r < 16; r++) for (let g = 0; g < 16; g++) for (let b = 0; b < 16; b++) {
    const hex = '#' + [r, g, b].map((v) => (v * 17).toString(16).padStart(2, '0')).join('');
    ui.saved.themeId = 'harbor'; ui.saved.accentOverride = hex;
    await ui.init();
    if (ui.$('mini-book').style.color !== contrastInk(hex)) mismatches.push(hex);
  }
  check('preview ink == server contrastInk on 4096 colors', mismatches.slice(0, 5), []);
}
{ // saving APPEARANCE must not clear an unsaved BOOKING edit
  const ui = uiHarness(); await ui.init();
  await ui.type('booking-url', 'https://cal.com/unsaved');
  await ui.$('appearance-save').fire('click');
  const r = await ui.copy();
  check('booking edited, appearance saved: copy blocked', r.copied, false);
  check('booking edited, appearance saved: says save booking', r.label, 'Save booking first');
  check('booking edit survives the appearance save', ui.$('booking-url').value, 'https://cal.com/unsaved');
  await ui.$('booking-save').fire('click');
  const r2 = await ui.copy();
  check('after booking saved: copy allowed', r2.copied, true);
  check('copied snippet carries the saved booking', ui.clipboard.at(-1), 'SNIPPET theme=harbor booking=https://cal.com/unsaved');
}
{ // saving BOOKING must not clear an unsaved APPEARANCE edit
  const ui = uiHarness(); await ui.init();
  await ui.type('assistant-name', 'Harbor helper');
  await ui.$('booking-save').fire('click');
  const r = await ui.copy();
  check('appearance edited, booking saved: copy blocked', r.copied, false);
  check('appearance edited, booking saved: says save appearance', r.label, 'Save appearance first');
}
{ // a logo upload saves the logo only; an unsaved theme pick stays dirty
  const ui = uiHarness(); await ui.init();
  await ui.pickTheme('midnight');
  ui.$('logo-file-input').files = [{ name: 'logo.png', type: 'image/png' }];
  await ui.$('logo-file-input').fire('change');
  check('theme picked, logo uploaded: copy blocked', (await ui.copy()).copied, false);
  await ui.$('appearance-save').fire('click');
  check('theme saved after upload: copy allowed', (await ui.copy()).copied, true);
}
{ // clearing the accent is an edit too
  const ui = uiHarness(); await ui.init();
  await ui.$('accent-clear').fire('click');
  check('accent cleared: copy blocked', (await ui.copy()).copied, false);
}
{ // BOOKING edited while its save is in flight: the newer edit survives, card stays dirty
  // (review PRRT_kwDOPOa9686nq_zw)
  const ui = uiHarness(); await ui.init();
  await ui.type('booking-url', 'https://cal.com/first');
  const release = ui.hold('POST /api/booking');
  const saving = ui.$('booking-save').fire('click');
  await ui.type('booking-url', 'https://cal.com/second');
  release(); await saving;
  check('booking in-flight edit: field keeps the newer value', ui.$('booking-url').value, 'https://cal.com/second');
  check('booking in-flight edit: server got the first value', ui.saved.bookingUrl, 'https://cal.com/first');
  const r = await ui.copy();
  check('booking in-flight edit: copy still blocked', [r.copied, r.label], [false, 'Save booking first']);
  check('booking in-flight edit: message says save again', ui.$('booking-msg').textContent.includes('save again'), true);
  await ui.$('booking-save').fire('click');
  check('booking saved again: copy allowed', (await ui.copy()).copied, true);
  check('booking saved again: snippet has the newer value', ui.clipboard.at(-1), 'SNIPPET theme=harbor booking=https://cal.com/second');
}
{ // APPEARANCE edited while its save is in flight (name, then a theme pick)
  const ui = uiHarness(); await ui.init();
  await ui.type('assistant-name', 'First name');
  let release = ui.hold('POST /api/embed-appearance');
  let saving = ui.$('appearance-save').fire('click');
  await ui.type('assistant-name', 'Second name');
  release(); await saving;
  check('appearance in-flight edit: field keeps the newer value', ui.$('assistant-name').value, 'Second name');
  check('appearance in-flight edit: copy still blocked', [(await ui.copy()).copied, ui.$('copy-label').textContent], [false, 'Save appearance first']);
  await ui.$('appearance-save').fire('click');
  check('appearance saved again: copy allowed', (await ui.copy()).copied, true);
  release = ui.hold('POST /api/embed-appearance');
  saving = ui.$('appearance-save').fire('click');
  await ui.pickTheme('midnight');
  release(); await saving;
  check('theme picked in flight: still midnight in the preview', ui.$('mini-launcher').style.background, '#334155');
  check('theme picked in flight: copy still blocked', (await ui.copy()).copied, false);
}
{ // no edit during the flight: saved values adopted, card clean
  const ui = uiHarness(); await ui.init();
  await ui.type('booking-label', '  Book now  ');
  const release = ui.hold('POST /api/booking');
  const saving = ui.$('booking-save').fire('click');
  release(); await saving;
  check('no in-flight edit: field shows the saved (trimmed) value', ui.$('booking-label').value, 'Book now');
  check('no in-flight edit: copy allowed', (await ui.copy()).copied, true);
}
{ // nothing edited: copy works straight away
  const ui = uiHarness(); await ui.init();
  check('clean form: copy allowed', (await ui.copy()).copied, true);
}


console.log(bad ? `\n${bad} FAILURES` : `\nall checks pass`);
process.exit(bad ? 1 : 0);
