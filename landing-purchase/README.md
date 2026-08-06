# WeOwn Chat — Landing / Purchase Page

**Status:** First full build complete — running locally, not yet deployed anywhere.
**Tracks:** PRD §9 Roadmap, "Landing + marketing site" (the top-of-funnel piece; the transactional purchase/checkout flow itself already lives at `billing.weown.dev` and is separately live in test-mode).

## What this project is

The public-facing page that sends outside traffic toward the self-serve signup/purchase flow — today, only Agent Operators (partners) manually drive prospects there; nothing exists yet to do that for organic/direct traffic. This is that build: Next.js 15 (App Router) + TypeScript + Tailwind v4.

## Running it locally

```bash
npm install
npm run dev
```

If the dev server ever throws stale-chunk errors (`Cannot find module './NN.js'`, `__webpack_modules__[moduleId] is not a function`) after a long editing session, it's a corrupted `.next/` build cache, not a code bug — stop the server, `rm -rf .next`, restart.

## What's built

- Nav, hero (a live, looping recreation of the real chat UI — not a static mockup), a "Live preview" section that embeds the actual dashboard HTML in an iframe with seeded demo content, how-it-works, the two-tab (private/public) explainer, value pillars, pricing (no dollar figure — see guardrails below), FAQ, footer.
- Design tokens sourced from the real product, not invented: see [`.claude/skills/weownchat-design/`](../.claude/skills/weownchat-design/SKILL.md) at the repo root. Colors, typography, and the radius scale are copied verbatim from `anythingllm-docker/template/dashboard/public/index.html` and the Keycloak `weown` login theme.
- `public/_demo/dashboard-preview.html` — an unmodified copy of the real dashboard HTML, with a `window.fetch` mock added on top so it renders with realistic fictional content (`Harborview CPA`) instead of hitting a live backend. See its own header comment for the maintenance rule: this file follows the real template, never the reverse.

See [`CHANGELOG.md`](CHANGELOG.md) for the detailed build history and known gaps (hosting decision still open, `npm audit` issue nested in Next.js's own dependencies, no legal/analytics/real billing wiring yet).

## Related documents

Outside this repo (kept off the public repo — draft pricing, security-gap status, and internal ownership details): the WeOwn Chat PRD and Branding & Marketing guide on the Desktop, alongside the original full-context briefing. Page copy was written against the Branding guide's messaging guardrails (nothing about pricing, ZDR routing, or the first live customer is overstated).
