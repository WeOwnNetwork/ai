# anythingllm-docker/sites

This directory holds **deployed site instances** generated from the
[`anythingllm-docker`](../) copier template. Each subdirectory is a complete,
independently deployed AnythingLLM instance — its own droplet, DNS record,
TLS cert, Infisical Machine Identity, Docker volumes, and backup retention.

The convention mirrors [`keycloak-docker/sites/`](../../keycloak-docker/sites/).

## Directory layout

```text
sites/
├── .gitignore                       # never commit terraform state, real tfvars, backups, .env
├── README.md                        # this file
└── <domain>/                        # one directory per deployment, named by primary domain
    ├── .gitignore                   # site-specific overrides
    ├── CHANGELOG.md                 # site-level changelog
    ├── README.md                    # site overview
    ├── MIGRATION_RUNBOOK.md         # optional — only when a migration is in flight
    ├── ansible/                     # Path C app layer (deploy.yml — see INFRA_BOOTSTRAP_PATTERN.md)
    ├── docker/                      # compose.prod.yaml + Caddyfile (uploaded by ansible)
    ├── terraform/                   # Layer 1 — droplet, firewall, DO Spaces state backend
    │   ├── backend.tf + init.sh     # DO Spaces remote state (SSE-C)
    │   └── templates/cloud-init.yaml # SLIM bootstrap: Docker + Infisical CLI + Layer 2 rotation
    └── scripts/                     # deploy.sh (ansible wrapper), backup.sh, restore.sh, site-specific tools
```

All sites adopt the **Path C + Layer 2 bootstrap pattern** documented in
[`../../docs/INFRA_BOOTSTRAP_PATTERN.md`](../../docs/INFRA_BOOTSTRAP_PATTERN.md).
Cloud-init handles only first-boot bootstrap; ongoing changes go through
`ansible-playbook ansible/deploy.yml` so no `tofu taint` is needed.

## Current deployments

| Site | Domain(s) | Project name | Pattern | Notes |
|---|---|---|---|---|
| [`s004/`](s004/) | `s004.ccc.bot` | `s004-anythingllm` | Path C + Layer 2 | ⚠️ **Retired** — the locked-out old box (JWT_SECRET dropped on a restart; no backups). Superseded by [`s004.ccc.bot/`](s004.ccc.bot/). Do not deploy. |
| [`s004.ccc.bot/`](s004.ccc.bot/) | `s004.ccc.bot` | `int-s004-anythingllm` | Path C + Layer 2, single-host | INT-S004 recovery rebuild (same hostname), re-rendered from the template — see [`MIGRATION_RUNBOOK.md`](s004.ccc.bot/MIGRATION_RUNBOOK.md). |
| [`ai.weown.agency/`](ai.weown.agency/) | `ai-stage.weown.agency` (staging) → `ai.weown.agency` (cutover) | `int-p01-anythingllm` | Path C + Layer 2, dual-hostname Caddyfile | DOKS → Docker migration in flight — see [`MIGRATION_RUNBOOK.md`](ai.weown.agency/MIGRATION_RUNBOOK.md) and [`ADR-005`](../../.github/ADR-005-int-p01-doks-retirement.md). |

## Creating a new site

```bash
cd anythingllm-docker

copier copy . sites/<domain> \
  --data project_name=<short-slug> \
  --data domain=<domain> \
  --data anythingllm_image=reg.mini.dev/anythingllm:1.7.2 \
  --defaults --trust
```

Then fill in `sites/<domain>/terraform/terraform.tfvars` from
`terraform.tfvars.example` — this file is gitignored and must never be
committed. Once the template carries Path C + Layer 2 by default
(currently being upstreamed from `s004/` and `ai.weown.agency/`), the
generated site will already include `ansible/`, `backend.tf`, and
`init.sh`. Until then, copy those from `s004/` and adjust paths.

## What's gitignored (and why)

- `**/terraform/.terraform/`, `*.tfstate*` — state files contain droplet IPs,
  reserved IPs, and resource IDs that leak internal topology.
- `**/terraform/terraform.tfvars`, `*.auto.tfvars` — contain the DigitalOcean
  API token and Infisical Machine Identity Client Secret. The
  `terraform.tfvars.example` is the only tfvars file tracked.
- `**/backups/` — backup tarballs may include workspace contents, embeddings,
  and sqlite databases with user data. These belong on the droplet or in DO
  Spaces, never in git.
- `**/.env*` — we don't use `.env` files at runtime (Infisical injects secrets),
  but the gitignore catches accidental local-only env files.

## State file management

Following the object-locked DO Spaces state pattern (as in
[`keycloak-docker/sites/README.md`](../../keycloak-docker/sites/README.md#state-file-management)),
AnythingLLM production state lives in DigitalOcean Spaces at `s3://weown-prod-state/`.
(Other services may still reference the older shared `weown-terraform-state` bucket —
that's a separate, coordinated migration; the bucket name here is what AnythingLLM uses.) Per-site `terraform/backend.tf` files are generated from the
template (when present) and committed; the operator runs `tofu init` to pull state
on first checkout. Local-dev state (no `backend.tf`) is gitignored.

## Related

- [`../README.md`](../README.md) — the `anythingllm-docker` template itself.
- [`../template/CHANGELOG.md.jinja`](../template/CHANGELOG.md.jinja) — the
  changelog stub rendered into each new site.
- [`../../keycloak-docker/sites/README.md`](../../keycloak-docker/sites/README.md) —
  reference implementation of this pattern.
