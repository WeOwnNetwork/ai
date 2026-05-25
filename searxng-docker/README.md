# searxng-docker

Copier template for SearXNG private search deployments on DigitalOcean droplets.

> **MIGRATION PENDING:** this template still uses the heavy-cloud-init pattern.
> The repo-wide canonical pattern is Path C (thin cloud-init + ansible app
> layer) plus Layer 2 (bootstrap-secret rotation). See
> [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for
> the migration checklist. Reference implementation:
> [`s004-deployment/`](../s004-deployment/).
>
> Note: this template already uses the `init.sh` + DO Spaces backend pattern
> from PR #26 (Layer 1). The remaining migration work is the cloud-init slim
> down (Path C) + Layer 2 bootstrap-secret rotation.

## Usage

```bash
copier copy . ../searxng-<sitename> --data-file answers.yaml
```

See [`copier.yaml`](copier.yaml) for available template variables. The
rendered output's README (`template/README.md.jinja` → `<rendered>/README.md`)
contains deployment instructions.
