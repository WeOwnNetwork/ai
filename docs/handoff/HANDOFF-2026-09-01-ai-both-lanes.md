# ai worker hand-off — both streams (2026-09-01, post-clear re-seat)

Supersedes `HANDOFF-2026-08-29-ai-both-lanes.md`. Pointer by design — substance lives in the
WeOwn vault (engagement custody; this repo is PUBLIC).

- **Live state:** `notes-weown/Projects/ai Lane - DASHBOARD.md`
- **Working hub** (accounts, identities, in-flight runs): `notes-weown/Projects/WeOwn.Chat - Working Hub (Handover Package).md`
- **Rotation addendum:** `notes-weown/Projects/ai Repo - Thread Hand-offs.md` → the **2026-09-01** section
- **Start a successor with:** `/worker ai`

**Headline:** the WeOwn Chat bot is **live** — the ocpa.group embed does real inference with no 402
(measured 2026-09-01). **Taking money is not live** — A637 (the WeOwn business Stripe account) is
Tyler-gated and console-only, so no agent can verify or unblock it. Larry still has **no affiliate row**.

**Two traps that make a working bot look broken**, both measured: the embed rejects any `Origin`
other than `https://ocpa.group`, and `sessionId` **must be a UUID** — a readable id returns
`{"error":"Invalid session ID."}`.

**New landmine:** `create_affiliate` writes `active=False` and the renderer filters `active=True`, so a
brand-new affiliate row renders **WeOwn** branding until activated — indistinguishable from "row
missing". See `RUNBOOK-affiliate-branding-verify.md` §1b.

**Repo conventions (verified in this repo's own [`CLAUDE.md`](../../CLAUDE.md), not assumed):** branch
regex `^(feature|fix|docs|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$` — `merge/<agent>` can never
merge here. **Issues are DISABLED and the repo is public**: defects go to `WeOwnDev/weown-fleet`
(private, issues on). PRs are hand-merged by Nik.

⛔ **Never deploy `keycloak-docker/sites/sso.weown.dev/`** — wrong volume prefix; it starts Keycloak on
empty volumes and every realm, client and user silently disappears behind green healthchecks.
Canonical render: `keycloak-docker/sites/sso/`.
