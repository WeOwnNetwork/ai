---
name: weownchat-design
description: Authoritative visual design system for WeOwn Chat — derived directly from the real dashboard and Keycloak login theme already in production (anythingllm-docker/template/dashboard/public/*.html, keycloak-docker/.../theme/weown), not invented separately. Apply whenever building or reviewing any WeOwn Chat frontend surface: the Landing/Purchase page, pricing, checkout, marketing components, email templates, or any color/typography/spacing decision for anything customer-facing. Trigger on: landing page, purchase page, pricing page, checkout, marketing site, hero section, CTA, Tailwind config, brand colors, typography choices. Existing to prevent a second, drifted color/type system from ever being invented alongside the real one again.
---

# WeOwn Chat — Design System

Exact tokens (hex values, radius scale, shadows, font stacks, ready-to-paste CSS and Tailwind v4 theme) live in [`references/tokens.md`](references/tokens.md). This file is the reasoning and the rules for applying them.

**Status: v2 — corrected against the real product.** v1 of this skill invented a palette (warm cream, slate-blue, serif headlines) from three unrelated reference sites before anyone had checked whether WeOwn already had a brand. It did — a complete, mature one, already live in the dashboard app shell (`anythingllm-docker/template/dashboard/public/index.html` and `login.html`) and the Keycloak login theme (`keycloak-docker/.../theme/weown/login/resources/css/weown.css`). Every token in this file now traces back to one of those two files. **Do not hand-pick a new value that "looks close enough" — read the source file and copy the exact value, the same way the Keycloak theme's own header comment insists on for itself.**

## The one rule that matters most

**This is not a fresh design system — it's a transcription.** The dashboard is the source of truth; the Keycloak login theme is a derived copy of it (its own header comment says so explicitly); this skill is a second derived copy, for marketing surfaces. If the dashboard's tokens ever change, this file and its reference doc are the ones that are stale, not the other way around. When in doubt, go re-read the dashboard source rather than trust this document's memory of it.

## Why it looks the way it does

WeOwn Chat's actual product — the dashboard a customer lives in every day — is a **dark, navy, focused workspace**, not a bright marketing-site palette. It reads as serious infrastructure software (a hardened server, a private assistant) rather than a consumer app. The landing/purchase page is often a customer's *first* screen and the dashboard is their *very next* one, seconds later, after clicking "Get started" — those two screens should feel like the same product, not like a bright brochure bolted onto a dark tool. That single continuity concern overrides any general marketing-site convention (light backgrounds, editorial serif type, generic warmth) this skill's v1 leaned on.

**There is no light theme anywhere in WeOwn Chat, and this skill doesn't introduce one.** The Keycloak theme's own CSS comment says it plainly: *"WeOwn has no light theme anywhere else, so this page shouldn't grow one."* Marketing surfaces follow the same rule.

## Design principles (the non-negotiables)

1. **Match the source exactly, don't approximate it.** A color, radius, or font that's "close to" the dashboard's is wrong. Copy the literal value from `references/tokens.md` (or the source files themselves if this doc is ever stale).
2. **Dark by default, everywhere.** No light-themed page, section, or component. If a surface needs to feel "lighter," reach for a higher `surface-*` step, not a white background.
3. **System fonts, not webfonts.** The dashboard loads zero webfonts — `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif` for everything, plus a system monospace stack for code-like content. No serif, anywhere, at any size. A landing-page hero headline is the same font stack at hero scale, not a different, more "editorial" typeface.
4. **Radius is contextual, not universal.** The dashboard uses a *four*-step radius scale (`8px / 10px / 16px / 999px`) and reserves full-pill (`999px`) specifically for badges, tags, avatars, and small circular icon buttons — most buttons, inputs, and cards use `8–16px`. Do not make every interactive element a pill; that was v1's mistake.
5. **Green means private, red means public — never anything else.** This is the single most load-bearing color rule in the whole product (see below). Don't reach for orange, yellow, or any other hue to distinguish the two tabs.

## The private/public color rule

The dashboard's own tab-status pills are unambiguous:

```css
.pill-ok   { background: var(--ok-dim);   color: var(--ok);   border: 1px solid var(--ok-border); }   /* Private */
.pill-warn { background: var(--warn-dim); color: #ff8f8f;     border: 1px solid var(--warn-border); } /* Public */
```

**Private = `ok` (green). Public = `warn` (red).** This isn't a marketing-site color choice — it's the literal implementation of the PRD's "green tab / red tab" naming (§5.1 of the PRD: *"if you would not print it on a flyer, it does not go on the red tab"*). Public is deliberately the *warning* color, not a neutral or playful one — the product wants a visitor to feel the exposure, not just note a category. Any UI on any WeOwn Chat surface that represents the private/public distinction — a mockup, a status dot, an explainer graphic — uses exactly these two colors. Orange, amber, or any third hue for "public" is a regression, not a stylistic variant.

## Color

Full tokens in the reference file. The shape of the system:

- **A five-step dark elevation scale**: `bg` (the deepest, base layer) through `surface-1` → `surface-2` → `surface-3` → `surface-4` (each a step lighter navy). Use elevation, not color, to separate content from chrome — exactly how the dashboard separates its sidebar (`surface-1`) from its main pane (`bg`) from a card (`surface-2`) from an open menu (`surface-3`/`surface-4`). A marketing page reproduces the same logic at section level: alternate `bg` and `surface-1` between sections for rhythm, put cards on `surface-2`.
- **One accent, `#00A3FF`**, with a `-strong` hover/active step and a `-dim` translucent step for tinted backgrounds. This is the brand color — full stop. It's used for primary actions, focus rings, links, and the brand mark. Don't introduce a second "marketing" accent alongside it.
- **Two semantic colors**, `ok` (green) and `warn` (red) — status only, never decorative. `ok` = private/safe/success. `warn` = public/error/destructive.
- **Borders are translucent white**, not a solid gray — `rgba(255,255,255,.10)` default, `.20` for emphasis. This is what gives the dark surfaces their edges without needing a lighter fill color.

## Typography

One font family, one monospace family, no exceptions:

| Role | Stack | Notes |
|---|---|---|
| Everything — headlines, body, UI, buttons | `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif` | Zero webfont loading. A hero headline is this same stack at a much larger size and bold weight — not a different typeface. |
| Code, technical labels, the trust-label strip | `ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace` | Matches the dashboard's `--mono` exactly. |

The dashboard's own large-text moments (`#kc-page-title`, `.empty-state h3`) are modest in size (~1.15–1.2rem) because they're app UI, not marketing copy — but they share a consistent personality worth carrying up to hero scale: **bold weight (700), tight negative letter-spacing (-0.01 to -0.02em)**. A landing-page H1 should feel like those headings scaled up, not like a different design system's headline.

## Shape

Four radius steps, used contextually — this is a real scale, not a suggestion:

| Token | Value | Use for |
|---|---|---|
| `r-sm` | 8px | Inputs, small buttons, list rows, tags |
| `r-md` | 10px | Primary buttons, form controls, small cards |
| `r-lg` | 16px | Cards, panels, the login/hero container |
| `r-full` | 999px | Badges/pills, chips, avatars, circular icon buttons only |

If you catch yourself reaching for `r-full` on a primary CTA button, stop — check `references/tokens.md`, the dashboard's own `.btn-solid` is `r-sm`.

## Shadows & motion

Two shadow steps exist in the tokens (`shadow-md`, `shadow-lg`) and are accurate to the real dashboard, which does use them for elevation (menus, the login card). **The Landing/Purchase page itself deliberately uses neither — it runs shadow-free throughout, by explicit direction, not oversight.** Depth on that page comes from the surface-elevation scale and borders alone. If a future surface needs real elevation (a modal, a dropdown, anything genuinely floating above other content), the tokens are there and correct to reach for — just don't reintroduce ambient shadows on cards/buttons/brand marks on the marketing page without checking first.

Motion: `cubic-bezier(.16, 1, .3, 1)` is the dashboard's own easing curve for basically everything (sidebar collapse, card entrance, hover lifts) — reuse it verbatim for consistency, don't invent a different curve.

## The signature background treatment

Both the dashboard's login page and the Keycloak login theme use the exact same background formula — a soft blue glow emanating from top-center over the base navy:

```css
background: radial-gradient(ellipse 900px 560px at 50% -10%, rgba(0, 163, 255, .16), transparent 60%), var(--bg);
```

Use this verbatim for the landing page's hero (and any other full-bleed "first impression" section) instead of inventing a different gradient treatment. It's already the product's signature entrance moment on two other surfaces — the landing page should be the third, not a fourth, different one.

## The brand mark

The literal WeOwn mark, used identically in the dashboard sidebar and the Keycloak login header: a filled square, `background: var(--accent)`, radius scaling with size (~28% of the square's width), a bold white "W," a subtle `rgba(255,255,255,.16)` border, and a soft drop shadow (`0 2px 6px rgba(0,0,0,.4)`). Use this exact mark next to the wordmark in the landing page's nav and footer — don't invent a different lockup or drop the mark and go text-only.

## The trust-label pattern

Still a good, ownable device from v1 — small uppercase monospace labels stating a plain fact near the primary CTA, pulled from the Branding guide's proof-points list, never inventing a new claim. Recolored: `text-faint` on `bg`/`surface-1`, using the real `--mono` stack. The "spec sheet, not copywriting" reasoning from v1 still holds — it works even better on a dark, technical-feeling surface than it did on the old warm palette.

## Applying this to the Landing/Purchase page

Section rhythm: alternate `bg` and `surface-1` for large sections (mirroring the dashboard's own chrome/content alternation), cards and panels sit on `surface-2` with a `border` outline and `r-lg`, buttons follow the radius table above (primary CTAs are `r-md`, not pills). The private/public explainer section is the one place this page must get exactly right — green for private, red for public, no exceptions (see above).

## Change log

| Date | Change |
|---|---|
| 2026-08-06 | v1 — initial design system, built from external reference-site research (no real brand existed to check against at the time) |
| 2026-08-06 | v2 — corrected wholesale against the real dashboard + Keycloak theme tokens after the mismatch was caught. Dropped serif typography, dropped universal-pill radius, dropped the invented light palette, fixed private/public to green/red. |
