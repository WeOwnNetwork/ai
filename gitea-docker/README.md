# gitea-docker

Copier template for deploying **Gitea** (self-hosted git) on DigitalOcean
droplets, with **Keycloak SSO (OIDC)** and **Infisical** runtime secret
injection (ADR-006). Cloned from [`keycloak-docker/`](../keycloak-docker/) —
same Path C bootstrap (thin cloud-init + ansible app layer), Layer-2
bootstrap-secret rotation, skinny backups, and DO Spaces remote state.

## Usage

```bash
copier copy . sites/<your-domain> --data-file answers.yaml --trust
```

See the rendered site's `README.md` for the full deploy flow, including the
one-time Keycloak OIDC client + Gitea auth-source bootstrap.

## What differs from keycloak-docker

| | keycloak-docker | gitea-docker |
|---|---|---|
| App service | `keycloak` (:8080) | `gitea` (:3000 HTTP, :22→host `gitea_ssh_port` SSH) |
| Auth | is the IdP | OIDC client of the Keycloak realm (`keycloak_realm_url`) |
| Registration | n/a | disabled; SSO auto-registration only |
| Extra firewall port | — | `gitea_ssh_port` (git-over-SSH, default 2222) |
| Admin vhost | `admin.<domain>` | none |

## Sites

Rendered deployments live under `sites/<domain>/` (none committed yet).
