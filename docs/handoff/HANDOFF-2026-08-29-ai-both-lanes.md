# ai worker hand-off — both streams (2026-08-29, fleet migration)

Supersedes `HANDOFF-2026-08-24-ai-both-lanes.md`. Pointer by design — substance lives in the
WeOwn vault (engagement custody; this repo is PUBLIC).

- **Live state:** `notes-weown/Projects/ai Lane - DASHBOARD.md`
- **Working hub** (accounts, identities, in-flight runs, hand-off state): `notes-weown/Projects/WeOwn.Chat - Working Hub (Handover Package).md`
- **Rotation addendum:** `notes-weown/Projects/ai Repo - Thread Hand-offs.md` → the **2026-08-29** section
- **Start a successor with:** `/worker ai`

**Headline:** the Larry white-label path is the top priority (Nik-stated). `#188` branding is
**deployed and verified**, but **Larry has no affiliate row** — the fix is one `create_affiliate`
command, blocked on an asset ask. A bare billing page shows WeOwn branding **by design**; the
deliverable to Larry is his `?ref=` link, verified through referral context.

**Also in flight:** the pilot dry-run with Nik as sample customer (ZDR OpenRouter account live and
funded; purchase reassigned to Tyler).

**Repo conventions (verified in this repo's own [`CLAUDE.md`](../../CLAUDE.md), not assumed):**
branch regex `^(feature|fix|docs|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$` — a
`merge/<agent>` branch **can never merge here**. PRs are hand-merged by Nik.

⛔ **Never deploy `keycloak-docker/sites/sso.weown.dev/`** — wrong volume prefix; it starts Keycloak
on empty volumes and every realm, client and user silently disappears behind green healthchecks.
Canonical render: `keycloak-docker/sites/sso/`.
