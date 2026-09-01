// Extract entitlementDenied from server.js and exercise every claim shape.
import { readFileSync } from 'node:fs';
const src = readFileSync('server.js', 'utf8');
const m = src.match(/const entitlementDenied = \(claims\) => \{[\s\S]*?\n\};/);
if (!m) { console.error('FAIL: could not extract entitlementDenied'); process.exit(1); }
const entitlementDenied = eval(`(${m[0].replace(/^const entitlementDenied = /, '').replace(/;$/, '')})`);

const cases = [
  ['claim absent entirely (every user today)',        {groups:['t']},                      false],
  ['null claims object',                              null,                                false],
  ['string "true"',                                   {subscription_active:'true'},        false],
  ['string "false"  → DENY',                          {subscription_active:'false'},       true ],
  ['array ["false"] → DENY (multivalued attr)',       {subscription_active:['false']},     true ],
  ['array ["true"]',                                  {subscription_active:['true']},      false],
  ['real boolean false → DENY (JSON-typed mapper)',   {subscription_active:false},         true ],
  ['real boolean true',                               {subscription_active:true},          false],
  ['"FALSE" uppercase → DENY',                        {subscription_active:'FALSE'},       true ],
  ['" false " padded → DENY',                         {subscription_active:' false '},     true ],
  ['empty string (attr cleared, not set false)',      {subscription_active:''},            false],
  ['unexpected value',                                {subscription_active:'maybe'},       false],
];
let bad = 0;
for (const [name, claims, want] of cases) {
  const got = entitlementDenied(claims);
  const ok = got === want;
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name}  → denied=${got}`);
}
console.log(bad ? `\n${bad} FAILURES` : `\nall ${cases.length} cases pass`);
process.exit(bad ? 1 : 0);
