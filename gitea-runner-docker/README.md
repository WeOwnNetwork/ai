# gitea-runner-docker

> #WeOwnVer: v5.1.2.1 · Status: ACTIVE · Scope: the `gitea-runner-docker` copier template and its sites

Copier template for a **Gitea Actions runner** (`act_runner`) on its own
DigitalOcean droplet. CI jobs run inside a **Docker-in-Docker** sidecar, never on
the host, and every job gets a daemon created for it and destroyed after it
(`runner-cycle.sh`). The registration token is read from **Infisical** once, at
registration (ADR-006). The bootstrap is the same Path C as [`gitea-docker/`](../gitea-docker/):
thin cloud-init with Layer-2 bootstrap-secret rotation, an ansible app layer, and
DO Spaces remote state through `terraform/itofu.sh`.

**Why its own droplet.** A runner executes pull-request code with a Docker
daemon, which is root-equivalent on its host. It must not share a box with the
forge or any service that holds secrets. The decision record is
[ADR-008](../.github/ADR-008-gitea-runner-dedicated-droplet.md) (Accepted). The decision is WeOwnCloud/openbao#8,
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
job image (node, apt, the docker CLI against dind), act_runner's parse of `config.yaml`,
the deploy's own job-image save step and the per-job cycle on its output (a fresh
daemon, the saved image loaded under its tag), the credential boundary (only the one-shot
`register` service mounts the Infisical file, and it hands the token over on stdin), the
metadata probe's classification, and the token gate. `tests/install-check.sh <site>` and
`tests/itofu-check.sh <site>` cover the pinned installs and the plan/apply rules;
`tests/deploy-check.sh <site>` the deploy's registration and token gate (ansible), and
`tests/manual-rotation-check.sh <site>` the two-phase manual rotation.

The first-boot rotation (cloud-init's `rotate-bootstrap-secret.sh`, rendered by tofu) has
its own test against a stand-in Infisical; it needs `tofu` and Docker:

```bash
gitea-runner-docker/tests/rotation-check.sh gitea-runner-docker/sites/<name>   # from the repo root
```

## What differs from gitea-docker

| | gitea-docker | gitea-runner-docker |
|---|---|---|
| Services | caddy, gitea, postgres | dind (privileged), runner |
| Inbound ports | admin SSH, 80, 443, git-SSH | **admin SSH only**; the runner polls the forge outbound |
| Admin SSH CIDR | copier answer | **required tofu var, never in git** (`TF_VAR_ssh_source_cidrs`), each entry /24 or narrower |
| VPC | default | its **own** VPC, range a required tofu var (`TF_VAR_vpc_ip_range`), never in git |
| Secrets | DB, Gitea keys, registry, Spaces | `GITEA_RUNNER_REGISTRATION_TOKEN` only, in the runner's **own** Infisical project |
| Backups | skinny backups to Spaces | none (stateless; re-registering is one token) |
| Images | `image_registry` mirror | exact pins: `act_runner_image`, `dind_image`, `job_image` (digest) |
| Docker, Infisical CLI | `get.docker.com`, `curl \| bash` | Docker's signed apt repo (fingerprint checked, versions held); the CLI `.deb` sha256-pinned |
| Bootstrap rotation | marker after best-effort revoke | marker only once a login with v1 is refused (401) |
| Process | long-running `docker compose up` | a systemd cycle: one job per fresh dind |

## Sites

- `sites/weown-ci-runner/`: the runner for one repository, `WeOwnCloud/openbao`, on
  git.weown.tools (a repository token, never an org one).
