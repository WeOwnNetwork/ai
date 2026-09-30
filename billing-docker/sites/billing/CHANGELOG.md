# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [#WeOwnVer](../docs/VERSIONING_WEOWNVER.md).

## [v4.1.1.3] — 2026-06-05

### Added

- **Layer 1 — DO Spaces Remote State**: Fixed `backend.tf.jinja` (removed var references), added `init.sh.jinja` to pass credentials via `-backend-config` flags
- **Layer 2 — Bootstrap-Secret Rotation**: `rotate-bootstrap-secret.sh` embedded in cloud-init (v1 → v2 auto-rotation)
- **Path C — Thin Cloud-Init + Ansible**: Cloud-init handles only first-boot bootstrap; ansible playbook owns all app-layer state
- **Ansible playbook overhaul**: `deploy.yml.jinja` with pre-tasks for bootstrap verification, backup script + cron upload, DO droplet tagging, Keycloak health checks
- **Deploy script rewrite**: Thin `ansible-playbook` wrapper requiring `INFISICAL_PROJECT_ID` env var
- **Backup script remote mode**: Invokes droplet-local backup.sh inside `infisical run` (heredoc pattern)
- **SSH CIDR restriction**: `ssh_source_cidrs` variable for firewall SSH rule

### Changed

- **Infisical CLI install**: Switched from legacy `install-cli.sh` (capped at v0.38) to current `artifacts-cli.infisical.com` apt repo
- **Auth file format**: Replaced `infisical-auth.sh` shell script with `.infisical-auth.env` key-value file (0600)
- **Cloud-init slimmed**: Removed all app-layer content (compose, Caddyfile, backup, cron, `docker compose up`)
- **Terraform main.tf.jinja**: Added `ignore_changes = [tags]` for runtime-added tags, slimmed `user_data` templatefile vars
- **Monitoring alerts**: Switched from Jinja conditionals to `count =` pattern
- **.gitignore.jinja**: Renamed from `.gitignore`, un-ignored `.terraform.lock.hcl` (commit for reproducibility)

### Security

- Bootstrap-secret rotation invalidates v1 Machine Identity secret within minutes of provisioning
- `.infisical-auth.env` written with 0600 permissions (root-only)
- SSH firewall now restricts access via `ssh_source_cidrs` variable
- Docker daemon config added (log rotation, overlay2)

## [Unreleased]

### Added

- **`manage.py stalled_signups`: a read-only report of where every sign-up stopped (2026-09-26)**. It places each Customer created since `--since` (default `2026-09-10`) at the first funnel step it has not passed: `no_agreement`, `signed_no_checkout`, `checkout_unfinished`, `lapsed`, `paid_no_instance`, `provisioning_stuck`, `instance_inactive`, `live`. It prints counts only, no personal data; `--ids` adds Customer primary keys. It writes nothing. "Checkout started" is detected from the Instance row that `new_instance` creates before redirecting to Stripe, because the Stripe customer id only arrives with `checkout.session.completed`. An abandoned checkout through the legacy `/subscribe/` route leaves no row (that door opens Checkout without an Instance), so it lands in `signed_no_checkout`: the agreement signature both doors require bounds the gap, and the report prints a note saying so. A signature counts only on the ACTIVE customer template, the same test the checkout gate applies, so publishing a new agreement version moves unsigned customers back to `no_agreement`. Keycloak registrations that never reached billing are out of scope. weown-fleet#66.

- **Dummy-proof onboarding: Keycloak register vs sign-in + no-instance paywall (2026-09-15)** — Landing Create account hits `/register/` (alias to `oidc_registration_init` → Keycloak `/protocol/openid-connect/registrations`); Sign in stays on `/oidc/authenticate/`. After login with no instance, billing home shows a non-modal blocking overlay into `new_instance` (agreement → Stripe). Trial copy follows `STRIPE_TRIAL_DAYS` (compose sets `14`). **Deploy:** ship billing before landing; enable Keycloak user registration for the `billing` client; redirect URI `https://billing.weown.dev/oidc/callback/`. **Infisical:** do not set a conflicting `STRIPE_TRIAL_DAYS` secret — `infisical run` can override compose and desync marketing from Stripe. See `.github/ADR-007-billing-keycloak-registration-onboarding.md`.

- **White-label affiliate branding on the signup funnel** — `Affiliate` gains `display_name`, `logo_url`, `primary_color` and `support_email` (migration `0011`), and `core.context_processors.branding` puts `brand` on every template. Resolution order is `?ref=` → session → the signed-in customer's `referred_by`; the last step is load-bearing, because `subscribe()` pops the session key once it is recorded, so without it the page reverts to WeOwn at the success/portal step *after* payment. Only **active** affiliates may brand a page. Blank fields fall back per-field, so existing affiliates are unchanged. `primary_color` is re-validated at render — it lands in a CSS custom property, where HTML autoescaping does not protect, and model validators do not run on a bare `.save()`; non-`https://` logos are dropped.

- Initial WeOwn billing service (Django + Stripe Connect + Keycloak SSO) template
- Docker Compose setup with Caddy, Keycloak, and PostgreSQL
- OpenTofu infrastructure configuration for DigitalOcean droplets
- Ansible playbooks for server configuration
- Infisical secrets management integration
- Backup and restore scripts
- Local development support

### Fixed

- **Deploy helpers pinned (2026-09-30).** The purge and owner-check tasks run `alpine:3.24@sha256:294b683c…` with `--network none`, not the end-of-life floating `alpine:3.19`.

- **The provisioning state volume is really separate now (2026-09-30).** The live compose named `ops_state` `weown_billing_static_data` (the web-served static volume); it is now `weown_billing_ops_state`. The deploy (1) removes `provisioning.json` / `provisioning.json.tmp` from the static volume before `up`, (2) chowns the new state volume's root to uid 1000 if a cron run on the previous image created it root-owned, and (3) fails unless `/static/provisioning.json` and `.tmp` answer 404 from the app. Expect `/ops/provisioning/` to read STALE for up to 5 minutes after the deploy, and at most one repeat alert.

- **Review sweep of findings on merged PRs #236, #239, #240, #242 and #252 (2026-09-30)**.
  - `prune_demo_data --restore` no longer re-activates a code that has referred customers: the referral guard now applies in both directions, as the docstring says. The closing "active affiliates now: (none)" line now prints (`+` bound tighter than `or`).
  - The app image creates `/app/state` owned by `appuser`. Docker copies that ownership into a NEW named volume; without it a fresh `ops_state` volume is `root:root` and `provisioning_watch` cannot write its state (measured: `PermissionError` on the old image, a clean save on the new one).
  - The provisioning-watch cron log gets a logrotate rule (daily, 14 kept, compressed, recreated `0640`): its ALERT lines name customer e-mails. The deploy also creates or corrects the log itself as `root:root 0640` (an existing `0644` log is fixed on the next deploy), and the cron line runs under `umask 027`, so a log it recreates is never world-readable.
  - The unclosed-template-comment test checks every comment opener on a line, closes its files, and reports paths relative to the app.
  - Settings comment for `OPS_*` moved back above those settings; duplicate `settings` import (`models.py`) and unused `os` import (`views.py`) removed; README says user registration is a realm setting.
  - ⚠️ **Not changed here: this render's compose volume names.** With compose project `weown_billing`, `static_data` and `ops_state` both resolve to `weown_billing_static_data`, so renaming `ops_state` would start its state on an empty volume and leave the old state file behind in the static volume. The template carries the fix; applying it to this live render is a planned migration (image with `/app/state` first, then the rename, then remove the orphaned state file and restart `web`).

- **This render was 3 migrations behind `template/app` — and it is what the droplet runs.** Verified live: `/agreement/` returned **404** while `/instances/new/` returned 302. Missing from production as a result: the customer-agreement gate on checkout, the free-trial lifecycle (`TRIALING`, `trial_end`), transactional lifecycle email (`core/mail.py` + templates), `customer_agreement.html`, `tests.py`, and migrations `0008`–`0010`. The render also hardcoded `$1,000/month` on the checkout button, which `template/` had deliberately removed so one image serves both the $5 drill product and the $1,000 live product via `STRIPE_PRICE_ID` — so **the $5 pilot could not have run on this render**. `app/` is now byte-identical to `template/app/`; `docker/`, `site.conf` and `terraform/` were deliberately left untouched because they carry this render's `app_dir` and volume-name identity. ⚠️ **Code only — the droplet keeps serving the old image until `scripts/deploy.sh` runs.**

### Security

- Non-root container users
- Secrets managed via Infisical (not in git)
- Automatic TLS via Caddy/Let's Encrypt
- Firewall with restricted port access
- PostgreSQL VPC-only access

## [] -
