# supabase/terraform

Terraform (OpenTofu) module for deploying the [supabase helm chart](../helm/) to a Kubernetes cluster with full IaC parity — matches the `<app>-docker/terraform/` convention used across the WeOwn droplet fleet.

## What this manages

1. **Infisical Secrets Operator** — cluster-wide install (provides the `InfisicalSecret` CRD)
2. **Namespace** for supabase workloads (default: `supabase`)
3. **Bootstrap secret** `infisical-universal-auth` — credential for the operator to authenticate to Infisical Cloud
4. **Helm release** — the supabase chart with `values-<instance>.yaml` overrides (e.g. `values-weown-tools.yaml` for the ecosystem backbone)

Not managed (pre-existing cluster utilities): `cert-manager`, `nginx-ingress`.

## Prerequisites

- OpenTofu (or Terraform >= 1.5.0)
- Infisical CLI (`brew install infisical/get-cli/infisical`)
- kubectl context configured for the target cluster
- Two Infisical projects (per-deployment):
  - **Runtime project** — holds the 12 supabase runtime secrets (POSTGRES_PASSWORD, JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY, DASHBOARD_PASSWORD_BCRYPT, etc.)
  - **Bootstrap project** — holds the TF_VARs this module needs

## Bootstrap tfvars flow

Values injected at `tofu apply` time via `infisical run`. This module never reads secrets from disk.

Populated in the bootstrap Infisical project (per env):

| Key | Value |
|-----|-------|
| `TF_VAR_infisical_client_id` | Universal-auth Client ID for a Viewer-role machine identity scoped to the runtime project |
| `TF_VAR_infisical_client_secret` | Universal-auth Client Secret for the same machine identity |
| `TF_VAR_infisical_project_id` | Slug of the runtime Infisical project |
| `TF_VAR_infisical_environment` | Env slug within the runtime project (e.g. `prod`) |

## Deploy

```bash
# From this directory:
tofu init

infisical run --projectId <bootstrap-project-slug> --env <env> -- tofu plan
infisical run --projectId <bootstrap-project-slug> --env <env> -- tofu apply
```

## Verify

```bash
kubectl -n supabase get pods
kubectl -n supabase get infisicalsecret
curl -sI https://<your-supabase-host>/rest/v1/  # expect HTTP 200
```

## Destroy

```bash
infisical run --projectId <bootstrap-project-slug> --env <env> -- tofu destroy
```

Note: `tofu destroy` removes the helm release + namespace + bootstrap secret, but **does NOT delete the postgres PVC** (`postgres-data-supabase-postgres-0`) — StatefulSet volumeClaimTemplates persist by design. Delete manually if you need a truly clean slate:

```bash
kubectl -n supabase delete pvc postgres-data-supabase-postgres-0
```

## Fleet retrofit reference

This module is the reference pattern for the fleet IaC parity initiative. Other cluster apps (anythingllm, matomo, n8n, vaultwarden) can adopt the same shape:

```
ai/<app>/
├── helm/                    # Existing helm chart
└── terraform/               # New sibling — mirrors this module
    ├── versions.tf
    ├── providers.tf
    ├── variables.tf
    ├── main.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    ├── .gitignore
    └── README.md
```

## Backlog

- Remote state via DO Spaces backend (matches `<app>-docker/terraform/backend.tf` pattern) — currently local state
- Pull secret values from Infisical directly via [`terraform-provider-infisical`](https://registry.terraform.io/providers/Infisical/infisical) instead of `infisical run` wrapper
- Manage `cert-manager` + `nginx-ingress` cluster utilities (currently out of scope — pre-existing)
