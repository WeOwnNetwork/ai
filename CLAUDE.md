# WeOwn AI Infrastructure — Claude Code Project Guide

## Critical: Read Existing Standards First

This project has comprehensive review and compliance standards in **`.github/copilot-instructions.md`** (780+ lines). Read it on your first task — it defines the security checklist, compliance frameworks (NIST CSF, CIS, ISO 27001, SOC 2, ISO 42001), and file-level patterns that every PR must satisfy.

Also read these on first session:

- `.github/CODEOWNERS` — who reviews what
- `.github/workflows/README.md` — CI/CD operations reference
- `docs/VERSIONING_WEOWNVER.md` — `#WeOwnVer` version numbering (`vSEASON.MONTH.WEEK.ITERATION`)
- `docs/COMPLIANCE_ROADMAP.md` — phased compliance program

## Branch Naming Convention (CI-enforced)

Pattern: `<type>/<dev>-<description>`

```
^(feature|fix|docs|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$
```

- **type**: `feature`, `fix`, `docs`, or `hotfix`
- **dev**: developer's lowercase handle (2+ chars) — e.g., `nik`, `shahid`, `mohammed`
- **description**: 3+ char first segment, optional `-word` groups after

Examples: `feature/nik-add-signoz-template`, `fix/shahid-otel-agent-config`

The `branch-name-check.yml` workflow rejects non-conforming branches. PRs from invalid branches cannot merge.

## Copier Template Pattern (`*-docker/`)

All Docker Compose deployments follow the copier template pattern. When creating a new service deployment, clone the structure from `keycloak-docker/` (simplest reference):

```
<service>-docker/
├── copier.yaml                          # _min_copier_version: "9.0.0", _subdirectory: template
└── template/
    ├── .gitignore
    ├── CHANGELOG.md.jinja
    ├── README.md.jinja
    ├── ansible/deploy.yml.jinja
    ├── docker/
    │   ├── Caddyfile.jinja
    │   ├── compose.prod.yaml.jinja      # Infisical runtime injection, healthchecks, resource limits
    │   └── <service-specific configs>
    ├── scripts/
    │   ├── backup.sh.jinja              # Skinny backup: volume tars + DO Spaces offload
    │   ├── deploy.sh.jinja              # SCP + SSH deploy
    │   └── restore.sh.jinja
    └── terraform/
        ├── backend.tf.jinja             # DO Spaces S3-compatible backend
        ├── main.tf.jinja                # Droplet + reserved IP + firewall
        ├── monitoring.tf.jinja          # CPU/memory/disk alerts
        ├── outputs.tf.jinja
        ├── variables.tf.jinja
        ├── versions.tf                  # DO provider ~> 2.36
        ├── terraform.tfvars.example.jinja
        └── templates/cloud-init.yaml.jinja
```

### Key patterns to follow exactly

- **cloud-init directive is `runcmd:` (singular)** — NOT `runcmds:`. This is a common typo.
- **Volume names**: use `{{ project_name | replace('-', '_') }}_<volume>` in Jinja templates.
- **Terraform templatefile `project_name`**: pass `{{ project_name | replace('-', '_') }}` (hyphens to underscores) to match volume names.
- **Secrets**: NEVER on disk. All via `infisical run` at container startup. Only Infisical Machine Identity (Client ID + Secret) stored in `terraform.tfvars`.
- **Docker `$$`**: In cloud-init templates (Terraform `templatefile()`), shell `$VAR` must be `$$VAR` to escape Terraform interpolation. Infisical-injected secrets use `$${SECRET_NAME}`.

## Secret Management (Infisical — mandatory)

- **Kubernetes**: `InfisicalSecret` CRD
- **Docker Compose**: `infisical run -- docker compose up -d`
- **Terraform**: variables for Machine Identity only; app secrets fetched at runtime
- **No `.env` files with real secrets** — ever. Use `.env.example` with placeholders.

## Public Repository Warning

This repo is **PUBLIC on github.com**. Never commit:

- API keys, tokens, passwords, private keys
- Private IPs (10.x, 172.16-31.x, 192.168.x), internal DNS names
- Real customer data, emails, PII
- Use RFC 5737 example IPs (192.0.2.x, 198.51.100.x, 203.0.113.x) in docs

## CHANGELOG and Versioning

- Update `/CHANGELOG.md` under `[Unreleased]` for repo-level changes (new templates, scripts, cross-cutting fixes).
- Per-app changes go in the app's own CHANGELOG.
- `#WeOwnVer` format: `vSEASON.MONTH.WEEK.ITERATION` — see `docs/VERSIONING_WEOWNVER.md`.

## Testing and Validation

- YAML: validate with `ruby -ryaml -e "YAML.safe_load(File.read('file.yaml'))"` or `yamllint`
- Bash: `bash -n script.sh` for syntax check
- Jinja templates: cannot be validated as raw YAML; verify structure by inspection
- Terraform: `tofu validate` if OpenTofu is available
- Ansible: `ansible-playbook --check --diff` for dry-run validation

## Fleet Management

- `scripts/manage-droplets.sh` — SSH/exec/deploy to all droplets by tag via `doctl`
- `scripts/deploy-otel-fleet.sh` — Deploy OTel agents across fleet
- `scripts/enable-do-agent.sh` — Enable free DO extended metrics
- Tags: `weown-ai` (all droplets), `anythingllm`, `wordpress`, `searxng`, `signoz`

## Docker Compose Hardening Checklist

Per `.github/copilot-instructions.md` §3.8, production compose files should include:

- `restart: unless-stopped`
- `healthcheck:` on all long-running services
- `deploy.resources.limits` (CPU + memory)
- Explicit `networks:` (no default bridge)
- Infisical for secrets (no real values in `environment:`)
