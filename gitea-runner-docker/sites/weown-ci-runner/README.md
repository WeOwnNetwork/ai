# weown-ci-runner

A Gitea Actions runner for **WeOwnCloud** on https://git.weown.tools, on its own
DigitalOcean droplet. Jobs labelled `ubuntu-latest` run in `node:20.18.1-bookworm`, inside a
Docker-in-Docker sidecar (`docker:27.5.1-dind`), driven by `gitea/act_runner:0.6.1`.
Capacity: 1 job at a time.

**Security model.** This host runs pull-request code with a Docker daemon, so it holds
nothing else:

- The only inbound rule is admin SSH, from a CIDR that never enters git.
- The only secret is the registration token, in a dedicated Infisical project that
  the forge's secrets are not in.
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

3. **Gitea: the registration token, stored blind.** On https://git.weown.tools, open
   WeOwnCloud → Settings → Actions → Runners → *Create new runner*, and copy the token.
   Then paste it into this hidden prompt. It goes to Infisical as a file on stdin, never
   on argv:

   ```bash
   read -rs T && infisical secrets set --projectId=<runner project id> --env=prod --file <(printf 'GITEA_RUNNER_REGISTRATION_TOKEN=%s\n' "$T"); unset T
   ```

4. **Provision** (from `terraform/`):

   ```bash
   export WEOWN_TOFU_PROJECT_ID=<weown-tofu project id> && ./itofu.sh init && ./itofu.sh plan && ./itofu.sh apply
   ```

   Wait about 5 minutes for cloud-init. On the droplet,
   `/var/log/weown_ci_runner-rotation.log` should end with
   `===== Rotation complete =====`.

5. **Deploy the runner:**

   ```bash
   ./scripts/deploy.sh root@$(cd terraform && ./itofu.sh output -raw droplet_ip)
   ```

   The playbook fails unless `data/.runner` appears, which proves the runner registered.

6. **Verify, then remove the token.** The runner shows as *Idle* under WeOwnCloud →
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
