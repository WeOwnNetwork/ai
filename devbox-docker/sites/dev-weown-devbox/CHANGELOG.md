# dev-weown-devbox - Changelog

All notable changes to this shared developer machine will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [#WeOwnVer](https://github.com/WeOwnNetwork/ai/blob/main/docs/VERSIONING_WEOWNVER.md) (calendar-driven `vSEASON.MONTH.WEEK.ITERATION`).

---

## [Unreleased]

### Added

-

---

## [v3.4.5.1] — 2026-05-30

### Added

- Initial `dev-weown-devbox` devbox copier template — a shared multi-user
  developer machine on a single DigitalOcean droplet (no web app: no Caddy, no
  Docker Compose service, no inbound 80/443; SSH on port 22 only).
- Per-user Linux accounts driven by `ansible/members.yml` (login = CCC Short ID,
  lowercased). Each member's SSH key opens ONLY their own account
  (`authorized_keys` is exclusive). Members get NO sudo.
- No shared team root: a single break-glass admin key
  (`var.ssh_key_fingerprint`, DO-registered) is the only root access
  (`PermitRootLogin prohibit-password`).
- Opt-in `docker`-group membership per member (`docker: true` in `members.yml`).
  Documented as root-equivalent — granted only to members who need local
  containers.
- Zed Remote Development workflow: the member's LOCAL Zed connects over SSH and
  auto-provisions its remote server (no Zed binary pre-installed on the box).
  Team-standard `zed-settings.json` is shipped to each home, `/etc/skel`, and a
  canonical copy under `/etc/dev_weown_devbox/`.
- `setup-zed` helper (`/usr/local/bin/setup-zed`): each member pastes their OWN
  OpenRouter API key (read securely, never echoed/logged), stored only in
  `~/.config/dev_weown_devbox/openrouter.env` (chmod 600)
  and wired into Zed as an OpenAI-compatible `openrouter` provider.
- Optional per-user Infisical path for OpenRouter keys (`infisical run`-based
  Zed launcher + login helper), shipped when `enable_per_user_infisical` is
  true. The simple prompt-based setup works with zero Infisical configuration.
- Dev toolchain provisioned idempotently by `ansible/deploy.yml`: git,
  build-essential, jq, ripgrep, fd-find, Python (+ pip/venv/pipx), Node.js LTS
  (NodeSource), OpenTofu, doctl, copier, ansible-lint, yamllint, and the LSPs
  Zed uses for YAML/Ansible/Python.
- Layer 1 + Layer 2 + Path C bootstrap pattern (see
  `docs/INFRA_BOOTSTRAP_PATTERN.md`):
  - Layer 1: DigitalOcean Spaces remote tfstate (SSE-C) via `backend.tf` +
    `init.sh`.
  - Layer 2: bootstrap-secret rotation at first boot — the Infisical Machine
    Identity client secret in terraform state + droplet metadata is invalidated
    within minutes of provisioning.
  - Path C: thin first-boot cloud-init + `ansible/deploy.yml` owns the app layer
    (accounts, SSH membership, Zed, toolchain, backups). Onboarding/offboarding
    is just an edit of `members.yml` + re-run of ansible — never a `tofu taint`.
- Terraform/OpenTofu infrastructure: droplet, reserved IP (stable SSH endpoint),
  firewall (inbound TCP 22 only, source-pinned via `ssh_source_cidrs`), and
  DigitalOcean monitoring alerts (CPU / memory / disk).
- Skinny backup system (`scripts/backup.sh`) of member homes + key configs with
  daily `cron.daily` job wrapped in `infisical run`, offloaded to DO Spaces;
  logrotate for the backup log.
- End-user onboarding guide: `docs/CONNECTING-WITH-ZED.md`.

### Security

- No per-user secrets and no application secrets in git or on droplet disk.
  OpenRouter keys live only with each member; infrastructure secrets (DO Spaces
  backup keys) are fetched from Infisical at runtime via the droplet's Machine
  Identity.
- SSH is key-only (`PasswordAuthentication no`), root reachable only via the
  break-glass key, and `AllowGroups devs root` gates every session.
- `terraform.tfvars` and `ansible/members.yml` are gitignored by default;
  immutable image tags only (no `:latest`).

### Compliance

- NIST CSF 2.0: PR.AC (least-privilege per-user access, no shared root), PR.DS
  (secrets off disk), DE.CM (monitoring).
- CIS Controls v8 IG1: CIS 4.1 (secure configuration), CIS 5.x (account
  management via `members.yml`), CIS 6.x (access control — key-only, group-gated
  SSH).
- ISO 27001-ready: A.5.15 (access control), A.5.17 (authentication information),
  A.8.24 (use of cryptography).

---

## Template Parameters Used

| Parameter | Value |
|-----------|-------|
| `project_name` | dev-weown-devbox |
| `domain` | dev.weown.tools |
| `do_region` | atl1 |
| `droplet_size` | s-4vcpu-8gb-amd |
| `default_shell` | bash |
| `zed_release_channel` | stable |
| `enable_per_user_infisical` | True |
| `infisical_project_id` |  |
| `infisical_environment` | prod |
| `enable_skinny_backups` | True |
| `backup_remote_storage` | do-spaces |
| `enable_monitoring` | True |

---

## Onboarding / Offboarding Notes

This box is reconciled with Ansible, not re-rendered. To add or remove a
developer:

1. **Onboard**: add the member to `ansible/members.yml` (login = CCC Short ID,
   unique `uid` >= 1000, their public SSH keys), then re-run
   `./scripts/deploy.sh root@<droplet-ip>`. They connect with Zed
   (`docs/CONNECTING-WITH-ZED.md`) and run `setup-zed` once.
2. **Offboard**: set `state: absent` on the member in `ansible/members.yml` and
   re-run the deploy — the account, its `authorized_keys`, and its cron are
   removed. Keep their `uid` stable so any restored files re-own correctly.

No `tofu taint` is ever needed for roster changes — the droplet and everyone's
work on it stay intact.
