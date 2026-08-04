# Morning brief — getting the demo to the team (2026-08-04)

## Where the pipeline stands

Paid signup → running instance is **one command** now:
`weown-fleet/scripts/provision-from-billing.sh --apply`

| Step | State |
|---|---|
| Register (SSO + email verify), claim subdomain, pay | automatic |
| Subscription, affiliate attribution frozen, instance queued | automatic |
| Tenant row (carries customer email + billing instance id) | automatic |
| Infisical folder + fleet-shared secrets (MINIMUS_TOKEN, Spaces backup keys) | automatic |
| Per-instance Machine Identity | **one command** — `provision-instance-mi.sh <slug>` (deliberate: org-level credential minting stays human) |
| Droplet, volume, firewall, monitors, reserved IP, app deploy, TLS | automatic |
| **DNS A record** | **manual** — DO token lacks DNS write (see §1) |
| ALLM admin + multi-user + Developer API key | automatic (`allm-bootstrap-admin.sh`, wired in) |
| Dashboard break-glass password + scrypt hash + customer email | automatic (same script) |
| Workspaces, prompts, embed widget | automatic |
| Billing flips to active, customer sees the link | automatic |
| Backup cron proven on the new instance | **unverified** (see §4) |

## What needs Nik (nothing else is blocked on you)

### 1. DNS — two options

- **Now:** DO console → Networking → Domains → `weown.dev` → A record
  `chattest` → `129.212.240.71`. TLS issues within a minute; that finishes the
  chattest instance.
- **Durable:** issue a DO token with **DNS write** scope so provisioning creates
  records itself. Today's token 403s on `/v2/domains/...` (and on
  `spaces/keys`, `reserved_ips`), which is why several steps still need you.
  This is the single highest-leverage fix for tomorrow's demo.

### 2. support@weown.net

The instance admin is now `support@weown.net` by default (password generated
into Infisical, never displayed). **Confirm the mailbox exists** — password
resets and customer replies land there. If it should be something else, say so
and it is a one-line default change (`ALLM_ADMIN_USER`).

### 3. OpenRouter ZDR account

Not started; needs your OpenRouter account access. What it involves:
create/settle the dedicated WeOwn account, **Settings → Privacy → restrict
routing to Zero-Data-Retention endpoints** (account-wide — every per-customer
key inherits it), then move `OPENROUTER_PROVISIONING_KEY` to that account and
re-mint per-instance keys. The provisioning script already prints the ZDR
reminder on every mint; the guardrail itself is an account setting only you can
flip.

### 4. Leftovers I could not do

- `PROBE_DELETE_ME` secret in Infisical `/sites/chattest` — delete in the UI
  (my endpoint probe; harmless, non-secret).
- Narrow `chattest-prod`'s project role to `/sites/chattest` (D-ISO path scope).
- Backup cron on chattest reported "not configured" by the smoke test — worth a
  look before the demo, given this morning's backup work.

## Suggested order tomorrow

1. DNS record (or the scoped token) → chattest goes live end-to-end.
2. Confirm the support mailbox.
3. Full clean test run: destroy chattest, sign up fresh through the portal with
   a `?ref=` link, pay, and watch it provision — that is the demo rehearsal and
   it exercises referral → attribution → splits → instance in one pass.
4. ZDR account, then re-mint keys.
5. Hand the team the tester guide + the link.

## Docs that exist for the team

- `docs/handoff/TESTER-GUIDE-billing-flow.md` — for the testing team.
- `docs/handoff/OWNER-GUIDE-stripe-connect-and-splits.md` — money model, COGS,
  attribution rules, tax questions.
- `docs/handoff/OWNER-GUIDE-stripe-dashboard.md` — reading payments in Stripe.

## Open PRs

ai: #147/#148/#149/#152/#153/#154/#155 merged; **#156, #157, #158** open.
weown-fleet: `feature/nik-provision-from-billing` (provisioning pipeline, MI
script, ALLM bootstrap) — needs a PR opened when you want it reviewed.

## The pattern worth remembering from tonight

Six failures, one family: **a check that reported success it had not earned** —
`folders get` exiting 0 on a missing folder, `secrets get` exiting 0 on a
nonexistent secret, a host key assumed present, a 60-second wait assumed
sufficient, an unauthenticated window assumed still open. Same shape as the
backups that reported green while uploading nothing. Every fix is committed
rather than hand-carried, and each one now asserts the real contract.
