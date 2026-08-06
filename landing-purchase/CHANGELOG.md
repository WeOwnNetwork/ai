# Landing/Purchase — Changelog

Changes specific to `landing-purchase/` (the WeOwn Chat Landing/Purchase page). Repo-wide changes are tracked in [`/CHANGELOG.md`](../CHANGELOG.md).

**Format**: [Keep a Changelog 1.1](https://keepachangelog.com/en/1.1.0/)
**Versioning**: Per [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md) — `vSEASON.MONTH.WEEK.ITERATION`

---

## [Unreleased]

### Added

- **Initial project scaffold and first full page build (2026-08-06)** — Next.js 15 (App Router) + TypeScript + Tailwind v4. All sections built: nav, hero (animated live-chat preview), a real-dashboard iframe showcase, how-it-works, the two-tab (private/public) explainer, value pillars, pricing (no dollar figure — draft/unsigned commercial terms), FAQ, footer. Design tokens sourced from the real dashboard/Keycloak theme via the `weownchat-design` Claude Code skill (`.claude/skills/weownchat-design/` at the repo root) rather than invented independently.
- **`public/_demo/dashboard-preview.html`** — an unmodified copy of `anythingllm-docker/template/dashboard/public/index.html` with one addition: a `window.fetch` mock feeding it realistic fictional demo content, so the real app shell can be embedded live (via iframe) instead of screenshotted. See the file's own header comment for the maintenance contract: edit this file to match the real template, never the reverse.

### Known gaps

- Hosting/deployment target not yet decided (Docker Compose + droplet, matching sibling services, vs. a static host).
- `npm audit`: 3 high-severity issues nested inside Next.js's own `postcss`/`sharp`; fix requires a Next 16 major-version bump, not taken yet.
- No legal/privacy pages, no analytics, no real Stripe/billing wiring beyond a link to `billing.weown.dev`.
