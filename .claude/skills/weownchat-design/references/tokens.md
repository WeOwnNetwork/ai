# WeOwn Chat — Design Tokens (reference)

Companion to [`../SKILL.md`](../SKILL.md). **Every value below is copied verbatim from the real product** — `anythingllm-docker/template/dashboard/public/index.html`'s `:root` block (primary source) and `keycloak-docker/.../theme/weown/login/resources/css/weown.css` (a derived subset, confirmed identical). If this file and the dashboard source ever disagree, the dashboard source wins — re-copy from there, don't split the difference.

## Color

| Token | Value | Usage |
|---|---|---|
| `bg` | `#0e1726` | Base page background — the deepest layer |
| `surface-1` | `#111c30` | Chrome: sidebar, nav, header bars, footer |
| `surface-2` | `#16213a` | Cards, panels, composer, raised content |
| `surface-3` | `#1b2740` | Open menus, active/selected tiles |
| `surface-4` | `#213256` | Hover states on top of surface-3 elements |
| `border` | `rgba(255,255,255,.10)` | Default hairline border |
| `border-strong` | `rgba(255,255,255,.20)` | Emphasized border (inputs, focus-adjacent) |
| `text` | `#eef2f7` | Primary text |
| `text-mut` | `#a9b6c9` | Secondary text |
| `text-faint` | `#66748d` | Tertiary/faint text, placeholders, mono labels |
| `accent` | `#00A3FF` | The brand color — primary actions, links, focus, brand mark |
| `accent-dim` | `rgba(0,163,255,.14)` | Tinted backgrounds for accent-colored elements |
| `accent-strong` | `#4db8ff` | Hover/active state of `accent` |
| `ok` | `#2fbf71` | **Private.** Success/safe status |
| `ok-dim` | `rgba(47,191,113,.13)` | `ok` tinted background |
| `ok-border` | `rgba(47,191,113,.38)` | `ok` border |
| `warn` | `#e53e3e` | **Public.** Error/destructive/exposure status |
| `warn-dim` | `rgba(229,62,62,.14)` | `warn` tinted background |
| `warn-border` | `rgba(229,62,62,.42)` | `warn` border |
| `bubble-user-bg` | `#173257` | (Chat-specific — reference only, not typically needed on marketing pages) |
| `bubble-user-border` | `rgba(0,163,255,.38)` | (Chat-specific — reference only) |

**Never used:** any light/white background as a page or section base, pure black, orange/amber/yellow for the public-tab distinction (it's `warn` red — see SKILL.md).

## Typography

Font stacks — **exact match to the dashboard, no webfonts**:

```css
--font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
--font-mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
```

There is no separate display/serif font. Headlines are `--font-sans` at larger size and bold weight.

Suggested marketing-page scale (the dashboard itself has no hero-sized text to copy from, since it's app UI — this extrapolates its actual heading personality, bold + tight tracking, up to hero scale):

| Style | Size (desktop) | Size (mobile) | Weight | Line-height | Tracking |
|---|---|---|---|---|---|
| Hero / H1 | 56px | 34px | 700 | 1.08 | -0.02em |
| H2 | 36px | 26px | 700 | 1.15 | -0.015em |
| H3 | 20px | 18px | 700 | 1.3 | -0.01em |
| Body large | 18px | 17px | 400 | 1.6 | normal |
| Body | 15px | 15px | 400 | 1.6 | normal — matches the dashboard's own body font-size exactly |
| Small / caption | 13px | 13px | 500 | 1.4 | normal |
| Mono label | 12px | 11px | 500 | 1.4 | 0.02em, uppercase |

## Shape

```css
--r-sm: 8px;    /* inputs, small buttons, list rows, tags */
--r-md: 10px;   /* primary buttons, form controls, small cards */
--r-lg: 16px;   /* cards, panels, hero/login containers */
--r-full: 999px; /* badges, chips, avatars, circular icon buttons ONLY */
```

## Shadows & motion

```css
--shadow-md: 0 8px 20px rgba(0,0,0,.38), 0 2px 6px rgba(0,0,0,.28);
--shadow-lg: 0 20px 48px rgba(0,0,0,.5), 0 6px 16px rgba(0,0,0,.35);
--ease: cubic-bezier(.16, 1, .3, 1);
```

## The signature background glow

```css
background: radial-gradient(ellipse 900px 560px at 50% -10%, rgba(0, 163, 255, .16), transparent 60%), var(--bg);
```

## The brand mark (verbatim)

```css
.brand-mark {
  width: 40px; height: 40px; border-radius: 11px;
  background: var(--accent);
  border: 1px solid rgba(255,255,255,.16);
  display: flex; align-items: center; justify-content: center;
  font-weight: 800; font-size: 17px; color: #fff; letter-spacing: -.02em;
  box-shadow: 0 2px 6px rgba(0,0,0,.4);
}
```

Content: the literal letter "W". Scale the whole block proportionally for smaller placements (e.g. 30px/13px/8px-radius in a compact nav).

## Ready-to-paste: CSS custom properties

```css
:root {
  --bg: #0e1726;
  --surface-1: #111c30;
  --surface-2: #16213a;
  --surface-3: #1b2740;
  --surface-4: #213256;
  --border: rgba(255, 255, 255, .10);
  --border-strong: rgba(255, 255, 255, .20);
  --text: #eef2f7;
  --text-mut: #a9b6c9;
  --text-faint: #66748d;
  --accent: #00A3FF;
  --accent-dim: rgba(0, 163, 255, .14);
  --accent-strong: #4db8ff;
  --ok: #2fbf71;
  --ok-dim: rgba(47, 191, 113, .13);
  --ok-border: rgba(47, 191, 113, .38);
  --warn: #e53e3e;
  --warn-dim: rgba(229, 62, 62, .14);
  --warn-border: rgba(229, 62, 62, .42);

  --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  --font-mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;

  --r-sm: 8px;
  --r-md: 10px;
  --r-lg: 16px;
  --r-full: 999px;

  --shadow-md: 0 8px 20px rgba(0,0,0,.38), 0 2px 6px rgba(0,0,0,.28);
  --shadow-lg: 0 20px 48px rgba(0,0,0,.5), 0 6px 16px rgba(0,0,0,.35);
  --ease: cubic-bezier(.16, 1, .3, 1);
}
```

## Ready-to-paste: Tailwind v4 theme (CSS-first `@theme`)

```css
@import "tailwindcss";

@theme {
  --color-bg: #0e1726;
  --color-surface-1: #111c30;
  --color-surface-2: #16213a;
  --color-surface-3: #1b2740;
  --color-surface-4: #213256;
  --color-text: #eef2f7;
  --color-text-mut: #a9b6c9;
  --color-text-faint: #66748d;
  --color-accent: #00A3FF;
  --color-accent-strong: #4db8ff;
  --color-ok: #2fbf71;
  --color-warn: #e53e3e;

  --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  --font-mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;

  --radius-sm: 8px;
  --radius-md: 10px;
  --radius-lg: 16px;
  --radius-full: 999px;
}
```

Border colors use Tailwind's arbitrary-value syntax directly (`border-white/10`, `border-white/20`) rather than a named token, since they're translucent whites over a variable background, not a fixed hex.

## Change log

| Date | Change |
|---|---|
| 2026-08-06 | v1 — initial token set, built from external reference-site research |
| 2026-08-06 | v2 — replaced wholesale with the real dashboard/Keycloak tokens |
