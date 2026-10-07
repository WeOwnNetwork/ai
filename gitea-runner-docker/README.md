# gitea-runner-docker

Copier template for a **Gitea Actions runner** (`act_runner`) on its own
DigitalOcean droplet. CI jobs run inside a **Docker-in-Docker** sidecar, never on
the host. The registration token is read from **Infisical** at container start
(ADR-006). The bootstrap is the same Path C as [`gitea-docker/`](../gitea-docker/):
thin cloud-init with Layer-2 bootstrap-secret rotation, an ansible app layer, and
DO Spaces remote state through `terraform/itofu.sh`.

**Why its own droplet.** A runner executes pull-request code with a Docker
daemon, which is root-equivalent on its host. It must not share a box with the
forge or any service that holds secrets. The decision is WeOwnCloud/openbao#8,
option A (2026-10-07). The runner design (DinD, a pinned dind hostname for TLS,
the cache off) follows the Gitea runners already in service for
perpetuator/mcp.

## Usage

```bash
copier copy . sites/<name> --data-file answers.yaml --trust
```

The rendered site's `README.md` has the full flow: the Infisical project and
token, `itofu.sh` apply, the ansible deploy, and deleting the token afterwards.

Before deploying, and after any image-pin bump, run the stack on local Docker:

```bash
gitea-runner-docker/tests/live-check.sh gitea-runner-docker/sites/<name>   # from the repo root
```

It checks dind health, the runner's TLS path, job docker access with a control, the
job image, and act_runner's parse of `config.yaml`.

## What differs from gitea-docker

| | gitea-docker | gitea-runner-docker |
|---|---|---|
| Services | caddy, gitea, postgres | dind (privileged), runner |
| Inbound ports | admin SSH, 80, 443, git-SSH | **admin SSH only**; the runner polls the forge outbound |
| Admin SSH CIDR | copier answer | **required tofu var, never in git** (`TF_VAR_ssh_source_cidrs`), world refused |
| Secrets | DB, Gitea keys, registry, Spaces | `GITEA_RUNNER_REGISTRATION_TOKEN` only, in the runner's **own** Infisical project |
| Backups | skinny backups to Spaces | none (stateless; re-registering is one token) |
| Images | `image_registry` mirror | exact pins: `act_runner_image`, `dind_image`, `job_image` |

## Sites

- `sites/weown-ci-runner/`: the runner for the `WeOwnCloud` org on git.weown.tools.
