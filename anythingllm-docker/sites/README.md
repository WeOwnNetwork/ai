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
    ├── CHANGELOG.md                 # site-level changelog (rendered + appended)
    ├── README.md                    # site overview (rendered)
    ├── MIGRATION_RUNBOOK.md         # optional — only when a migration is in flight
    ├── docker/                      # compose.prod.yaml + Caddyfile
    ├── terraform/                   # OpenTofu — main.tf, vars, tfvars.example, cloud-init
    └── scripts/                     # deploy.sh, backup.sh, restore.sh, (site-specific tools)
```

## Current deployments

| Site | Domain | Project name | Notes |
|---|---|---|---|
| [`ai.weown.agency/`](ai.weown.agency/) | `ai.weown.agency` | `int-p01` | DOKS → Docker migration in flight — see [`ai.weown.agency/MIGRATION_RUNBOOK.md`](ai.weown.agency/MIGRATION_RUNBOOK.md) and decision record [`ADR-005`](../../.github/ADR-005-int-p01-doks-retirement.md) |

## Creating a new site

```bash
cd anythingllm-docker

copier copy . sites/<domain> \
  --data project_name=<short-slug> \
  --data domain=<domain> \
  --data anythingllm_image=reg.mini.dev/anythingllm:latest \
  --defaults --trust
```

Then fill in `sites/<domain>/terraform/terraform.tfvars` from
`terraform.tfvars.example` — this file is gitignored and must never be
committed.

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

Per the [`keycloak-docker/sites/README.md`](../../keycloak-docker/sites/README.md#state-file-management)
conventions, production state lives in DigitalOcean Spaces (`s3://weown-terraform-state/`)
with object locking. Per-site `terraform/backend.tf` files are generated from the
template (when present) and committed; the operator runs `tofu init` to pull state
on first checkout. Local-dev state (no `backend.tf`) is gitignored.

## Related

- [`../README.md`](../README.md) — the `anythingllm-docker` template itself.
- [`../template/CHANGELOG.md.jinja`](../template/CHANGELOG.md.jinja) — the
  changelog stub rendered into each new site.
- [`../../keycloak-docker/sites/README.md`](../../keycloak-docker/sites/README.md) —
  reference implementation of this pattern.
