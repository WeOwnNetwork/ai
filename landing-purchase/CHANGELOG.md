# Landing/Purchase — Changelog

Changes specific to `landing-purchase/` (the WeOwn Chat Landing/Purchase page). Repo-wide changes are tracked in [`/CHANGELOG.md`](../CHANGELOG.md).

**Format**: [Keep a Changelog 1.1](https://keepachangelog.com/en/1.1.0/)
**Versioning**: Per [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md) — `vSEASON.MONTH.WEEK.ITERATION`

---

## [Unreleased]

### Changed

- **Rewritten on Astro, replacing the Next.js build (2026-08-06)** — per direct direction to match the framework used elsewhere in the WeOwn ecosystem (a repo-wide search turned up no existing Astro usage in *this* repo to match conventions against, so the setup is this project's own reasonable defaults: Astro 7 + `@tailwindcss/vite`, static output). Every section carried over content-for-content: nav (mobile menu now vanilla JS instead of a React client component), hero's animated chat preview (now a small vanilla-JS state machine driving the DOM directly), the real-dashboard iframe showcase, how-it-works, the two-tab explainer, value pillars, pricing, FAQ (now native `<details>`/`<summary>` with `name="faq-accordion"` for an exclusive accordion — zero JS, and incidentally the same pattern the real dashboard's own `.doc-strip` already uses), footer. `npm audit` goes from 3 high-severity findings (nested inside Next.js's own `postcss`/`sharp`) to 0 — not the reason for the rewrite, but a real side benefit of the newer, leaner dependency tree.
- **Hardened the scroll-reveal system while porting it** — the Next.js version hid `[data-reveal]` content at `opacity:0` unconditionally, dependent on React + `IntersectionObserver` to ever make it visible again. Testing the Astro port surfaced a real gap: `IntersectionObserver` was observed to sometimes not fire its callback at all, even for an element plainly sitting in the viewport, in the specific automated-browser environment used for testing (cause unconfirmed — real browsers are presumably fine, this is an extremely well-supported API — but unconfirmed is not the same as ruled out). Fixed properly rather than dismissed: elements are now visible by default and only *opt into* the hidden-then-reveal transition once the script runs (`.reveal-armed`), and a 2.5s timeout force-reveals anything the observer never fires for. Nothing on the page can end up permanently invisible because one animation mechanism didn't fire.

### Added (superseded, kept for history)

- **Initial project scaffold and first full page build (2026-08-06)** — Next.js 15 (App Router) + TypeScript + Tailwind v4. Design tokens sourced from the real dashboard/Keycloak theme via the `weownchat-design` skill (`.claude/skills/weownchat-design/` at the repo root) rather than invented independently. Superseded by the Astro rewrite above — kept here only as build history, not as a description of the current codebase.
- **`public/_demo/dashboard-preview.html`** — an unmodified copy of `anythingllm-docker/template/dashboard/public/index.html` with one addition: a `window.fetch` mock feeding it realistic fictional demo content, so the real app shell can be embedded live (via iframe) instead of screenshotted. See the file's own header comment for the maintenance contract: edit this file to match the real template, never the reverse. Unaffected by the framework rewrite — this file was always framework-agnostic static HTML and just moved from `public/` to `public/` (no change).

### Known gaps

- Hosting/deployment target not yet decided (Docker Compose + droplet, matching sibling services, vs. a static host — Astro's static output makes either path easy).
- No legal/privacy pages, no analytics, no real Stripe/billing wiring beyond a link to `billing.weown.dev`.
