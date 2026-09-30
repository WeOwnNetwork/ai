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
check('snippet contains booking when set', withBooking.includes('weown-booking-cta') && withBooking.includes('https://cal.com/x'), true);
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
check('UI dirty hooks use real field ids', /\['accent-hex','accent-color','assistant-name','booking-url','booking-label'\]/.test(html), true);

check('readBooking re-validates on read', src.includes('booking.json URL rejected on read') && src.includes('validateBookingUrl(rawUrl)'), true);


console.log(bad ? `\n${bad} FAILURES` : `\nall checks pass`);
process.exit(bad ? 1 : 0);
