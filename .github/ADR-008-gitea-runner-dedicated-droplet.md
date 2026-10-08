# ADR-008: Gitea Actions runner on a dedicated droplet, one Docker-in-Docker daemon per job

**Status**: Accepted (by Nik's merge of WeOwnNetwork/ai#302)
**Version**: v5.1.2.1 (#WeOwnVer — Season 5, month 1 (Oct), ISO-week offset 2 of Oct, iteration 1; per [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md): 2026-10-07 = ISO W41; first ISO week of October = W40; offset = 41 − 40 + 1 = 2)
**Date**: 2026-10-07
**Deciders**: Nik (option A, 2026-10-07; accepted by merging #302), openbao lane (author), ai lane (review)
**Related**: WeOwnCloud/openbao#8 (no CI runner); [ADR-006](ADR-006-in-container-infisical-injection.md) (in-container Infisical injection); `gitea-runner-docker/`; PR WeOwnNetwork/ai#302

---

## Context

No Gitea Actions run on git.weown.tools has ever executed. Every one is discarded with "No matching online runner with label: ubuntu-latest" (WeOwnCloud/openbao#8). A runner executes pull-request code, and the openbao workflow runs `docker` itself, so the runner needs a Docker daemon. A Docker daemon is root-equivalent on its host.

## Decision

1. **A dedicated droplet**, holding nothing else: no forge, no database, no other service's secrets. It has its own VPC (no private route to other droplets) and no inbound port except admin SSH, from CIDRs that are required tofu variables and never in git.
2. **Registered per repository**, never per org: only that repository's pull requests reach the box.
3. **Jobs run inside a privileged Docker-in-Docker sidecar**, never on the host's Docker. Each job gets a daemon **created for it and destroyed after it** (`runner-cycle.sh` under systemd: `down -v`, a fresh dind, the digest-pinned job image loaded, `act_runner --once`). Nothing a job leaves in its daemon reaches the next job.
4. **One credential boundary.** Only a one-shot `register` service mounts the Infisical CLI and the Machine Identity file, and only until `data/.runner` exists. The `runner` that handles jobs mounts neither. The registration token sits in the runner's own Infisical project and is deleted after registration.
5. **No metadata.** Container traffic to `169.254.169.254` is rejected, and the deploy proves it (BLOCKED, plus a forge REACHED control) before any job runs.
6. **Pinned inputs**: images by tag and digest; Docker from its signed apt repo with the key fingerprint checked and versions held; the Infisical CLI from a sha256-pinned release `.deb`.

## Threat model

- **Assumed:** a job can escape the privileged dind to root on the droplet. Point 3 removes persistence *inside* the daemon; it does not undo an escape. The other points bound what an escape reaches: one repository's runner registration, no other droplet over the VPC, no metadata, no Infisical credential in the job-handling container, and a bootstrap secret proven dead before deploy.
- **Outbound stays open**, because jobs fetch packages from hosts nobody can list in advance. An escaped job can therefore reach the internet.

## Alternatives considered

| Option | Why not (now) |
|---|---|
| A runner on the forge host | A job escape would reach the forge and its secrets |
| A droplet per job (full VM isolation) | Minutes of boot per job, plus cost; worth revisiting if escape risk outweighs the speed |
| Rootless Docker or sysbox instead of privileged dind | Less escape surface, but neither is proven with act_runner here; a later hardening step |
| A long-running dind with pruning | Leaves containers, volumes and images for the next job (rejected in review) |

## Consequences

- **Cost:** one `s-2vcpu-4gb-amd` droplet (about $24/month).
- Every job pays a fresh daemon start and a job-image load, a few seconds to a minute, and images a workflow pulls itself are pulled again in every job.
- Liveness comes from systemd (`Restart=always`) and `runner.timeout`. act_runner 0.6.1 has no health endpoint.

**Rollback:** stop the `<project>-runner` service, then `./itofu.sh plan -destroy`, review it, and `./itofu.sh apply`. Workflows go back to waiting for a runner, which is today's state.

**Ownership:** the ai lane owns the template; Nik owns the spend and the apply.

## Compliance

NIST CSF 2.0 PR.AA-05 (least privilege: per-repo registration, one credential boundary), PR.DS-01 (no secrets in git, the metadata block), PR.PS-01 (pinned, verified packages), DE.CM (the deploy proves the metadata block before any job runs).
