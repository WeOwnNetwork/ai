# ♾️ WeOwn AI - Enterprise AI & Automation Infrastructure

🚀 **WeOwn AI Infrastructure** - Production-grade deployment templates and Kubernetes platform delivering secure, scalable AI and automation services with enterprise security, zero-trust networking, and SOC2/ISO42001 compliance.

This README is the **map**: one line per feature, each linking to the doc that is the **manual** for that one thing. A newcomer should be able to answer *"what does this repo do, and where is X?"* from this page alone.

## 📦 Droplet Deployment Templates (`*-docker/`)

Copier templates for single-droplet Docker Compose deployments — each renders a per-site deployment under `sites/` with Terraform (DigitalOcean), Ansible deploy, Infisical runtime secrets, hardened Compose, and skinny backups. Pattern reference: [`keycloak-docker/`](keycloak-docker/README.md) (simplest); conventions: [CLAUDE.md](CLAUDE.md).

| Template | Deploys |
|---|---|
| [anythingllm-docker](anythingllm-docker/README.md) | AnythingLLM private AI chat / RAG — the WeOwn.Chat product instances |
| [billing-docker](billing-docker/DEVELOPING.md) | Stripe billing + affiliate/white-label portal for WeOwn.Chat |
| [buzz-docker](buzz-docker/README.md) | Buzz (Nostr-based) team comms relay |
| [devbox-docker](devbox-docker/) | Remote development box |
| [gitea-docker](gitea-docker/README.md) | Gitea git forge (git.weown.tools) |
| [keycloak-docker](keycloak-docker/README.md) | Keycloak SSO (sso.weown.dev) — canonical render: `sites/sso/` |
| [openclaw-docker](openclaw-docker/README.md) | OpenClaw agent gateway |
| [owncloud-docker](owncloud-docker/README.md) | ownCloud file sync/share |
| [sandbox-docker](sandbox-docker/README.md) | Disposable sandbox environment |
| [searxng-docker](searxng-docker/README.md) | SearXNG private metasearch |
| [signoz-docker](signoz-docker/README.md) | SigNoz observability backend (traces/metrics/logs) |
| [supabase-docker](supabase-docker/README.md) | Supabase (Postgres + auth + API) |
| [wordpress-docker](wordpress-docker/README.md) | WordPress sites |

## ☸️ Kubernetes Platform (DOKS)

| Component | Purpose |
|---|---|
| [anythingllm](anythingllm/README.md) | AnythingLLM Helm deployment (cluster tenant) |
| [n8n](n8n/README.md) | Visual workflow automation — Helm chart + Docker variant with custom extensions |
| [vaultwarden](vaultwarden/README.md) | Bitwarden-compatible password manager |
| [nextcloud](nextcloud/README.md) · [matomo](matomo/README.md) · [wordpress](wordpress/README.md) | File collaboration · privacy-first analytics · WP on k8s |
| [cluster-backup](cluster-backup/README.md) | Cluster-wide backup to DO Spaces |
| [k8s](k8s/) | Cluster-level docs and monitoring config |
| [llm-d](llm-d/) | LLM deployment pools/workers/models config |
| Cluster runbook & inventory | [WEOWN-APP-CLUSTER-RUNBOOK](docs/WEOWN-APP-CLUSTER-RUNBOOK.md) · [WEOWN-APP-CLUSTER-INVENTORY](docs/WEOWN-APP-CLUSTER-INVENTORY.md) |

## 🛰️ Fleet Operations

| Tool | Does |
|---|---|
| [scripts/manage-droplets.sh](scripts/manage-droplets.sh) | SSH/exec/deploy across all droplets by DO tag (`doctl`) |
| [scripts/deploy-otel-fleet.sh](scripts/deploy-otel-fleet.sh) · [otel-agent](otel-agent/README.md) | Roll OTel collection agents across the fleet |
| [scripts/tag-droplet.sh](scripts/tag-droplet.sh) | Feature/commit tagging for droplet inventory |
| [scripts/enable-do-agent.sh](scripts/enable-do-agent.sh) | Enable free DO extended metrics |
| Smoke tests | [scripts/README-smoke-test.md](scripts/README-smoke-test.md) |
| Fleet design | [docs/FLEET_OPERATIONS_DESIGN.md](docs/FLEET_OPERATIONS_DESIGN.md) |

## 🧩 Product & Integration Components

| Component | Purpose |
|---|---|
| [landing-purchase](landing-purchase/README.md) | WeOwn.Chat landing / purchase page |
| [braintrust-proxy](braintrust-proxy/README.md) | LLM eval/proxy layer |
| [cli](cli/) | `weown` CLI utilities |
| [wordpress-dev](wordpress-dev/docs/README.md) | WordPress local development environment |
| [diagrams](diagrams/README.md) | Architecture diagrams |

## 🔐 Security, Compliance & CI

| Area | Doc |
|---|---|
| Review & compliance standards (every PR) | [.github/copilot-instructions.md](.github/copilot-instructions.md) |
| Agent secrets hygiene (authoritative) | [AGENTS.md](AGENTS.md) |
| CI/CD workflows & `weown-bot` PAT ops | [.github/workflows/README.md](.github/workflows/README.md) |
| Secrets management (Infisical, runtime injection) | [docs/INFRA_BOOTSTRAP_PATTERN.md](docs/INFRA_BOOTSTRAP_PATTERN.md) · [docs/INFISICAL_OUTAGE_RUNBOOK.md](docs/INFISICAL_OUTAGE_RUNBOOK.md) |
| Compliance program (NIST CSF · CIS · ISO 27001 · SOC 2 · ISO 42001) | [docs/COMPLIANCE_ROADMAP.md](docs/COMPLIANCE_ROADMAP.md) |
| Versioning (`#WeOwnVer`) | [docs/VERSIONING_WEOWNVER.md](docs/VERSIONING_WEOWNVER.md) |
| Pre-commit gates | [docs/PRECOMMIT.md](docs/PRECOMMIT.md) |
| Customer instance provisioning | [docs/CUSTOMER_INSTANCE_PROVISIONING.md](docs/CUSTOMER_INSTANCE_PROVISIONING.md) |

## 🤝 Contributing

Branch naming is CI-enforced: `^(feature|fix|docs|hotfix)/<dev>-<description>` — see [CLAUDE.md](CLAUDE.md). Changes land via PR to `main`; update [CHANGELOG.md](CHANGELOG.md) under `[Unreleased]`. README link integrity is tested by [tests/readme-links.test.sh](tests/readme-links.test.sh).
