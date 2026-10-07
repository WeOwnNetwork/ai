# weown-ci-runner

A Gitea Actions runner for **WeOwnCloud/openbao** on https://git.weown.tools, on its own
DigitalOcean droplet. Jobs labelled `ubuntu-latest` run in `node:24.21.0-bookworm@sha256:3d27e5c11e5786e309ec3e03f93ae536eb36e6e5eb3714d5eb3300a36157add0`, inside a
Docker-in-Docker sidecar (`docker:27.5.1-dind@sha256:aa3df78ecf320f5fafdce71c659f1629e96e9de0968305fe1de670e0ca9176ce`), driven by `gitea/act_runner:0.6.1@sha256:b5c35d6bdbb9bb25e531230bfc7cc663cb751406cbec90a2a891b85fea54de86`.
Capacity: 1 job at a time.

**Security model.** This host runs pull-request code, and the dind sidecar is
**privileged**. Assume any job can escape to root on this droplet. Everything below
limits what such a job can reach:

- **One repository.** The runner is registered for `WeOwnCloud/openbao` only, never an
  org, so only that repo's PRs run here. Keep that repo's approval requirement for
  fork pull-request workflows on.
- **Its own VPC.** It has no private route to other droplets; some of them admit the
  whole private range (WeOwnDev/weown-fleet#159).
- **No metadata.** Container traffic to `169.254.169.254` is rejected, so jobs can't
  read this droplet's user_data or identity. The deploy proves it.
- **No inbound** except admin SSH, from a CIDR that never enters git.
- **One secret,** the registration token, in a dedicated Infisical project that the
  forge's secrets are not in. It is deleted after registration.
- Jobs reach the **dind** daemon (they can run `docker`), never the host's.

## First deploy (operator)

Placeholders in `<angle brackets>` are values you look up. Nothing secret is typed on
a command line.

1. **Infisical: the runner's own project.** Create a project (e.g. `weown-ci-runner`) with
   env `prod`. Create a Machine Identity (Universal Auth) with read
   access to it and permission to manage its own client secrets (Layer-2 rotation needs
   that). Put its project id in `site.conf`.

2. **weown-tofu: this site's provisioning values.** In the `weown-tofu` project, env
   `prod`, folder `/infra/sites/weown-ci-runner/`, set:
   - `TF_VAR_infisical_client_id`, `TF_VAR_infisical_client_secret` and
     `TF_VAR_infisical_project_id` (from step 1);
   - `TF_VAR_ssh_source_cidrs`: a JSON list of your admin IP/32 or VPN range. This is
     the only inbound rule, and terraform refuses `0.0.0.0/0`.

   The shared values (`TF_VAR_do_token`, the Spaces keys, `TF_VAR_ssh_key_fingerprints`,
   `TF_VAR_alert_email`) are already in `/infra/shared`.

3. **Gitea: the registration token, stored blind.** On https://git.weown.tools, open the
   **repository** WeOwnCloud/openbao → Settings → Actions → Runners → *Create new runner*,
   and copy the token. Use the repository, not the org.
   Then paste it into this hidden prompt. It goes to Infisical as a file on stdin, never
   on argv:

   ```bash
   read -rs T && infisical secrets set --projectId=<runner project id> --env=prod --file <(printf 'GITEA_RUNNER_REGISTRATION_TOKEN=%s\n' "$T"); unset T
   ```

4. **Provision** (from `terraform/`):

   ```bash
   export WEOWN_TOFU_PROJECT_ID=<weown-tofu project id> && ./itofu.sh init && ./itofu.sh plan && ./itofu.sh apply
   ```

   Wait about 5 minutes for cloud-init.

5. **Rotate the bootstrap secret (required).** The v1 Infisical secret is in terraform
   state and in the droplet's metadata, and the deploy refuses to run until it is
   rotated. If `/var/log/weown_ci_runner-rotation.log` ends with
   `===== Rotation complete =====`, skip to step 6. If it says `ROTATION FAILED` (the
   identity may not manage its own secrets), create a v2 client secret in Infisical, run
   the script below, then **revoke v1** in Infisical:

   ```bash
   ./scripts/rotate-mi-manual.sh root@$(cd terraform && ./itofu.sh output -raw droplet_ip)
   ```

6. **Deploy the runner:**

   ```bash
   ./scripts/deploy.sh root@$(cd terraform && ./itofu.sh output -raw droplet_ip)
   ```

   The playbook fails unless rotation is done, a container is refused at the metadata
   service, and `data/.runner` appears, which proves the runner registered.

7. **Verify, then remove the token.** The runner shows as *Idle* under WeOwnCloud/openbao →
   Settings → Actions → Runners. Re-run a queued workflow and confirm the run has a
   start time. Then delete `GITEA_RUNNER_REGISTRATION_TOKEN` from the runner's Infisical
   project: after registration, act_runner authenticates from `data/.runner`.

## Operations

- **Change config or images:** edit the copier answers, re-render, then run `scripts/deploy.sh`.
  Images are exact pins; bump them on purpose.
- **Re-register** (new token, or a lost `data/.runner`): delete the old runner in Gitea, store
  a new token (step 3), delete `/opt/weown_ci_runner/data/.runner`, then
  `docker compose up -d --force-recreate runner`.
- **Disk:** job images accumulate inside dind. A weekly cron prunes anything unused for 7 days.
  The disk alert is at 80%.
- **Logs:** `docker compose -f /opt/weown_ci_runner/compose.yaml logs -f runner`.
