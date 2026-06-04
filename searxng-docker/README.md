# searxng-docker

Copier template for SearXNG private search deployments on DigitalOcean droplets.

## Migration status (bootstrap pattern)

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for
the shared pattern + 6-step migration checklist. This project's state today:

| Layer | Status | Notes |
|---|---|---|
| Layer 1 (DO Spaces remote state) | **Done** | [`template/terraform/backend.tf.jinja`](template/terraform/backend.tf.jinja) + [`init.sh.jinja`](template/terraform/init.sh.jinja) (PR #26). |
| Layer 2 (bootstrap-secret rotation) | **Pending** | No `rotate-bootstrap-secret.sh`. Reference: [`anythingllm-docker/sites/s004/terraform/templates/cloud-init.yaml`](../anythingllm-docker/sites/s004/terraform/templates/cloud-init.yaml). |
| Path C (thin cloud-init + ansible) | **Partial** | [`template/ansible/deploy.yml.jinja`](template/ansible/deploy.yml.jinja) already uploads compose + runs `docker compose up`, BUT [`template/terraform/templates/cloud-init.yaml.jinja`](template/terraform/templates/cloud-init.yaml.jinja) ALSO embeds the app layer. **Slim the cloud-init.** |
| Infisical CLI install | **Legacy** — `install-cli.sh` (capped at v0.38). Switch to artifacts-cli apt repo. |

## Usage

```bash
copier copy . ../searxng-<sitename> --data-file answers.yaml
```

See [`copier.yaml`](copier.yaml) for available template variables. The
rendered output's README (`template/README.md.jinja` → `<rendered>/README.md`)
contains deployment instructions.

---

## Secret injection pattern

Secrets reach this service at runtime via Infisical. The standard is documented in
[`docs/INFRA_BOOTSTRAP_PATTERN.md` → Runtime secret injection](../docs/INFRA_BOOTSTRAP_PATTERN.md#runtime-secret-injection)
and [`.github/ADR-006-in-container-infisical-injection.md`](../.github/ADR-006-in-container-infisical-injection.md):
host-side `infisical run` wrap today (refresh on **redeploy**, not on a bare `docker restart`) →
moving toward **in-container `infisical run`** for bounce-to-refresh, with auto-reload, automatic
rotation, single-use tokens, and a clean K8s/K3s migration. No app secrets on disk or in git
(D247); only the project-scoped Machine Identity lives on the node.
