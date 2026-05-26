# searxng-docker

Copier template for SearXNG private search deployments on DigitalOcean droplets.

## Migration status (bootstrap pattern)

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for
the shared pattern + 6-step migration checklist. This project's state today:

| Layer | Status | Notes |
|---|---|---|
| Layer 1 (DO Spaces remote state) | **Done** | [`template/terraform/backend.tf.jinja`](template/terraform/backend.tf.jinja) + [`init.sh.jinja`](template/terraform/init.sh.jinja) (PR #26). |
| Layer 2 (bootstrap-secret rotation) | **Pending** | No `rotate-bootstrap-secret.sh`. Reference: [`s004-deployment/terraform/templates/cloud-init.yaml`](../s004-deployment/terraform/templates/cloud-init.yaml). |
| Path C (thin cloud-init + ansible) | **Partial** | [`template/ansible/deploy.yml.jinja`](template/ansible/deploy.yml.jinja) already uploads compose + runs `docker compose up`, BUT [`template/terraform/templates/cloud-init.yaml.jinja`](template/terraform/templates/cloud-init.yaml.jinja) ALSO embeds the app layer. **Slim the cloud-init.** |
| Infisical CLI install | **Legacy** — `install-cli.sh` (capped at v0.38). Switch to artifacts-cli apt repo. |

## Usage

```bash
copier copy . ../searxng-<sitename> --data-file answers.yaml
```

See [`copier.yaml`](copier.yaml) for available template variables. The
rendered output's README (`template/README.md.jinja` → `<rendered>/README.md`)
contains deployment instructions.
