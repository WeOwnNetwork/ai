# searxng-docker

Copier template for SearXNG private search deployments on DigitalOcean droplets.

## Migration status (bootstrap pattern)

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for
the shared pattern + 6-step migration checklist. This project's state today:

| Layer | Status | Notes |
|---|---|---|
| Layer 1 (DO Spaces remote state) | **Done** | [`template/terraform/backend.tf.jinja`](template/terraform/backend.tf.jinja) + [`init.sh.jinja`](template/terraform/init.sh.jinja) (PR #26). |
| Layer 2 (bootstrap-secret rotation) | **Done** | `rotate-bootstrap-secret.sh` embedded in [`template/terraform/templates/cloud-init.yaml.jinja`](template/terraform/templates/cloud-init.yaml.jinja). Logs in with v1, mints v2 via Infisical API, atomically swaps the auth file, revokes v1. |
| Path C (thin cloud-init + ansible) | **Partial** | Cloud-init now handles only first-boot bootstrap. [`template/ansible/deploy.yml.jinja`](template/ansible/deploy.yml.jinja) needs overhaul (pre-tasks, backup upload, cron, DO tagging, health checks). [`template/scripts/deploy.sh.jinja`](template/scripts/deploy.sh.jinja) needs rewriting as thin ansible-playbook wrapper. |
| ADR-006 (in-container Infisical entrypoint) | **Done** | [`template/docker/compose.prod.yaml.jinja`](template/docker/compose.prod.yaml.jinja) — `infisical run` is the container entrypoint; bounce-to-refresh via `docker restart`. |
| Infisical CLI install | **Current** — uses `artifacts-cli.infisical.com` apt repo. |

## Usage

```bash
copier copy . ../searxng-<sitename> --data-file answers.yaml
```

See [`copier.yaml`](copier.yaml) for available template variables. The
rendered output's README (`template/README.md.jinja` → `<rendered>/README.md`)
contains deployment instructions.

### Infisical Outage Procedures

If Infisical Cloud becomes unavailable, deployments and backups will fail. See [INFISICAL_OUTAGE_RUNBOOK.md](../docs/INFISICAL_OUTAGE_RUNBOOK.md) for emergency procedures including:

- Manual deployment without Infisical
- Local-only backup creation
- Emergency restore procedures
- Recovery steps when Infisical comes back online

---

## Secret injection pattern

Secrets reach this service at runtime via Infisical. The standard is documented in
[`docs/INFRA_BOOTSTRAP_PATTERN.md` → Runtime secret injection](../docs/INFRA_BOOTSTRAP_PATTERN.md#runtime-secret-injection)
and [`.github/ADR-006-in-container-infisical-injection.md`](../.github/ADR-006-in-container-infisical-injection.md):
host-side `infisical run` wrap today (refresh on **redeploy**, not on a bare `docker restart`) →
moving toward **in-container `infisical run`** for bounce-to-refresh, with auto-reload, automatic
rotation, single-use tokens, and a clean K8s/K3s migration. No app secrets on disk or in git
(D247); only the project-scoped Machine Identity lives on the node.
