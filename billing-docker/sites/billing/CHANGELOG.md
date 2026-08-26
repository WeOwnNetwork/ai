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

- **White-label affiliate branding on the signup funnel** — `Affiliate` gains `display_name`, `logo_url`, `primary_color` and `support_email` (migration `0011`), and `core.context_processors.branding` puts `brand` on every template. Resolution order is `?ref=` → session → the signed-in customer's `referred_by`; the last step is load-bearing, because `subscribe()` pops the session key once it is recorded, so without it the page reverts to WeOwn at the success/portal step *after* payment. Only **active** affiliates may brand a page. Blank fields fall back per-field, so existing affiliates are unchanged. `primary_color` is re-validated at render — it lands in a CSS custom property, where HTML autoescaping does not protect, and model validators do not run on a bare `.save()`; non-`https://` logos are dropped.

- Initial WeOwn billing service (Django + Stripe Connect + Keycloak SSO) template
- Docker Compose setup with Caddy, Keycloak, and PostgreSQL
- OpenTofu infrastructure configuration for DigitalOcean droplets
- Ansible playbooks for server configuration
- Infisical secrets management integration
- Backup and restore scripts
- Local development support

### Fixed

- **This render was 3 migrations behind `template/app` — and it is what the droplet runs.** Verified live: `/agreement/` returned **404** while `/instances/new/` returned 302. Missing from production as a result: the customer-agreement gate on checkout, the free-trial lifecycle (`TRIALING`, `trial_end`), transactional lifecycle email (`core/mail.py` + templates), `customer_agreement.html`, `tests.py`, and migrations `0008`–`0010`. The render also hardcoded `$1,000/month` on the checkout button, which `template/` had deliberately removed so one image serves both the $5 drill product and the $1,000 live product via `STRIPE_PRICE_ID` — so **the $5 pilot could not have run on this render**. `app/` is now byte-identical to `template/app/`; `docker/`, `site.conf` and `terraform/` were deliberately left untouched because they carry this render's `app_dir` and volume-name identity. ⚠️ **Code only — the droplet keeps serving the old image until `scripts/deploy.sh` runs.**

### Security

- Non-root container users
- Secrets managed via Infisical (not in git)
- Automatic TLS via Caddy/Let's Encrypt
- Firewall with restricted port access
- PostgreSQL VPC-only access

## [] -
