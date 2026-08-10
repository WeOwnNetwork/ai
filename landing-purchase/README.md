# WeOwn Chat — Landing / Purchase Page

**Status:** Rebuilt on Astro — running locally, not yet deployed anywhere.
**Tracks:** PRD §9 Roadmap, "Landing + marketing site" (the top-of-funnel piece; the transactional purchase/checkout flow itself already lives at `billing.weown.dev` and is separately live in test-mode).

## What this project is

The public-facing page that sends outside traffic toward the self-serve signup/purchase flow — today, only Agent Operators (partners) manually drive prospects there; nothing exists yet to do that for organic/direct traffic. Astro + Tailwind CSS v4, static output (plain HTML/CSS, JS only where something genuinely needs it).

**Previously built on Next.js** — rewritten on Astro per direct direction (matching the framework used elsewhere in the WeOwn ecosystem, outside this repo; a repo-wide search here turned up no existing Astro usage to match conventions against, so the setup choices below are this project's own).

## Running it locally

```bash
npm install
npm run dev      # http://localhost:4321
npm run build    # astro check && astro build -> dist/
npm run preview  # serve the production build locally
```

## What's built

- Nav (with a real, working mobile menu — vanilla JS, no framework), hero (a live, looping recreation of the real chat UI — not a static mockup, vanilla JS state machine), a "Live preview" section that embeds the actual dashboard HTML in an iframe with seeded demo content, how-it-works, the two-tab (private/public) explainer, value pillars, pricing (no dollar figure — see guardrails below), FAQ (native `<details>`/`<summary>` with `name="faq-accordion"` for an exclusive-open accordion — zero JavaScript), footer.
- Design tokens sourced from the real product, not invented: see [`.claude/skills/weownchat-design/`](../.claude/skills/weownchat-design/SKILL.md) at the repo root. Colors, typography, and the radius scale are copied verbatim from `anythingllm-docker/template/dashboard/public/index.html` and the Keycloak `weown` login theme.
- `public/_demo/dashboard-preview.html` — an unmodified copy of the real dashboard HTML, with a `window.fetch` mock added on top so it renders with realistic fictional content (`Harborview CPA`) instead of hitting a live backend. See its own header comment for the maintenance rule: this file follows the real template, never the reverse.
- Scroll-reveal animations (`src/scripts/reveal.ts`) are **progressive enhancement, not a hard dependency on JS working**: elements are fully visible by default in the CSS and only opt into the hidden-then-reveal transition once the script runs, and there's a 2.5s timeout fallback that force-reveals anything the `IntersectionObserver` never fires for. Worth knowing if you touch this file: during development, `IntersectionObserver` was observed to sometimes not fire at all even for elements plainly within the viewport, in the specific automated-browser environment used to test this — cause unconfirmed (real browsers are presumably fine; this is an extremely well-supported API), but the fix holds regardless of cause, so it was kept.

See [`CHANGELOG.md`](CHANGELOG.md) for the detailed build history and known gaps (hosting decision still open, no legal/analytics/real billing wiring yet).

## Related documents

Outside this repo (kept off the public repo — draft pricing, security-gap status, and internal ownership details): the WeOwn Chat PRD and Branding & Marketing guide on the Desktop, alongside the original full-context briefing. Page copy was written against the Branding guide's messaging guardrails (nothing about pricing, ZDR routing, or the first live customer is overstated).
