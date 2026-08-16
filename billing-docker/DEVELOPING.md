# billing-docker — implementation notes

Facts an implementer needs before touching this component. Commercial and
organisational context (rates, partners, priorities) lives in the WeOwn vault
and is deliberately **not** duplicated here — this file is about the code.

## 1. Edit the TEMPLATE, never the render

Work happens in **`template/app/`**. `sites/billing/app/` is a *render* — the
next `copier` run overwrites it, silently reverting anything edited there.

Same rule with teeth elsewhere in this repo: a render's `app_dir` and
volume-name prefix are its **identity**. Never re-render a live site to pick up
a template change without first confirming the render matches the box
(`ssh <host> 'ls /opt; docker volume ls'` vs `grep "name: " docker/compose.prod.yaml`).
A mismatched render starts the app on fresh empty volumes — green healthchecks,
no data. See the repo `CLAUDE.md` for the full rule and the tombstone convention.

## 2. Running the tests

The suite needs **no Postgres, no Infisical, no network**. Point
`DJANGO_SETTINGS_MODULE` at a sqlite override and run:

```bash
cd template/app
python -m django test core --settings=<your_sqlite_settings>
```

A minimal override: import `billing.settings`, then replace `DATABASES` with
sqlite `:memory:`, set `AUTHENTICATION_BACKENDS` to Django's ModelBackend (the
real one is OIDC), and give the Stripe settings dummy values. Stripe is mocked
throughout — the tests assert *our* logic, never Stripe's behaviour.

26 tests as of the trial/agreement work. Also run
`python -m django makemigrations --check --dry-run` — a model change without a
migration passes tests and breaks deploy.

## 3. ⚠️ The money path — read before touching splits

**`pay_affiliate_splits` RETURNS failures. It must never raise.**

The caller runs inside `@transaction.atomic`. Raising rolls back the audit rows
for transfers that have *already left Stripe*, and the webhook replay then sees
an unrecorded leg and **sends the money again**. That is exactly how an
affiliate was paid twice on 2026-08-04. Money that has moved must never be
un-recorded by a rollback; the caller reports failures after the rows commit.

Anything touching this path — refunds, clawbacks, retries — preserves that shape
and ships as **its own isolated commit and PR**, reviewable alone. If a WeOwn
reviewer comments on a money-path PR, surface it; do not self-merge.

Related invariant: commission is owed on **money collected**. A zero-amount
invoice (the normal case at the start of a free trial) must return before the
split maths and before the charge lookup — there is a regression test for this
and it must not be weakened.

## 4. ⚠️ Signature evidence depends on the proxy topology

`signer_ip` on customer/affiliate agreements is the **rightmost**
`X-Forwarded-For` hop — trustworthy only while Caddy is the outermost proxy.
Put a CDN in front and every signature silently records an edge IP with nothing
erroring. Full reasoning, the detection heuristic, and what has to change:
`template/app/core/views._signer_origin` and the `CustomerContract` docstring.

## 5. Repo conventions that bite

- **This repo is PUBLIC.** No secrets, no private IPs, no internal ssh aliases,
  no real emails — in code, comments, docs or test fixtures.
- **Branch names are CI-enforced**: `^(feature|fix|docs|hotfix)/<dev>-<desc>$`.
  "Validate Branch Name" is a required check, so a non-conforming branch can
  never merge. `auto-pr-to-main.yml` opens one PR per conformant branch —
  **one PR per feature** is the designed flow here, not drift.
- **Issues are DISABLED** on this repo, so the work queue lives in the WeOwn
  vault rather than a tracker.

## 6. Known gaps (not bugs — unbuilt)

| Gap | What an implementer needs to know |
| --- | --- |
| Refund/chargeback → affiliate clawback | No `charge.refunded` / `charge.dispute.*` handler. A reversal must claw back **proportionally from every leg**, reusing the `SplitPayout` ledger. See §3 before writing a line. |
| Entitlement not enforced on the instance | Billing writes the Keycloak attribute `subscription_active`; the ALLM dashboard authorizes on the `groups` claim only, so a cancelled customer keeps a working instance. Verify the **read** path end-to-end, not just the write. |
| No provisioning worker | `views.py` says "the provisioning worker polls" — there isn't one; `weown-fleet/scripts/provision-from-billing.sh` is run by hand. Propose the design first: the billing droplet holds **no fleet credentials by design**, and a worker must not undo that boundary. |
| No transactional email | Minimum: welcome/instance-ready, trial-ending (the `customer.subscription.trial_will_end` handler is the hook), payment-failed, suspended. DigitalOcean blocks outbound 587 — use 2525. Mind the SendGrid DKIM history. |

## 7. Before a real-money test

`docs/handoff/DRILL-billing-end-to-end-real-money.md` (repo root `docs/`) is the
end-to-end drill: buy → trial → charge → split → refund, with per-step expected
values. It refuses to start until the `SplitConfig` row is set, deliberately.
