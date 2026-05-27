# otel-agent — fleet observability agent (SigNoz Cloud destination)

`otel-agent/` deploys an OpenTelemetry Collector to every WeOwn droplet
(`burnedout-xyz`, `anythingllm-*`, `wordpress-*`, `searxng-*`, …). The agent
collects host metrics, container metrics, and logs, then ships them to **SigNoz
Cloud** (Yonks' managed account) over OTLP/HTTP.

This is the primary observability path. The self-hosted SigNoz stack in
[`signoz-docker/`](../signoz-docker/) is preserved as an optional, future
self-hosting fallback only — it is NOT deployed.

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  burnedout-xyz droplet (also: wordpress, anythingllm)│
│  ┌──────────────────────────────────────────────┐    │
│  │  otel-agent (this directory)                 │    │
│  │  - hostmetrics  (CPU/mem/disk/net/load)      │    │
│  │  - docker_stats (per-container metrics)      │    │
│  │  - filelog      (docker, caddy, syslog)      │    │
│  │  256MB cap • host net • read-only mounts     │    │
│  └────────────────────┬─────────────────────────┘    │
└───────────────────────┼──────────────────────────────┘
                        │ OTLP/HTTP + TLS
                        │ header: signoz-access-token
                        ▼
            https://ingest.us2.signoz.cloud
                  (SigNoz Cloud)
```

Region is **us2** (NOT `us`) — that's the region of Yonks' SigNoz Cloud account.
The exporter is **OTLP/HTTP** so `OTEL_URL` must be a full URL with a scheme,
e.g. `https://ingest.us2.signoz.cloud` (SigNoz Cloud **us2**). If Infisical
stores only `ingest.us2.signoz.cloud:443`, the deploy script prepends `https://`
automatically before `docker compose up`.

---

## Secrets model (Infisical, runtime injection only)

- **`OTEL_URL`** — Infisical **otel** project, env **dev** ("Development" in UI). Used by the OTel exporter `endpoint`. **Not on disk.**
- **`OTEL_KEY`** — Infisical **otel** project, env **dev**. Sent as the `signoz-access-token` header. **Not on disk.**
- **Machine Identity** — Client ID, Client Secret, Project ID, and env slug live in `<otel_agent_dir>/.infisical-auth.env` (0600 root) for `infisical login` on the droplet. Root-only; never in the repo.

Notes:

- The Infisical environment slug defaults to **`dev`** because that's where the
  current values live ("Development" in the UI). Override with `--env-slug prod`
  if/when the secrets are promoted to a production environment.
- `<otel_agent_dir>` defaults to `/opt/otel-agent` for new droplets. The legacy
  `burnedout-xyz` droplet already has the directory at
  `/root/observability/otel-agent` (created during earlier work with Gemini), so
  pass `--dir /root/observability/otel-agent` for that one host.

Every `docker compose up -d` is wrapped in `infisical run --projectId=<otel-pid> --env=<slug> -- ...`,
so `OTEL_URL` and `OTEL_KEY` are fetched fresh and only exist as environment
variables of the running `otel-agent` container. **Bouncing the container picks
up rotated values automatically** — which is exactly what Nik asked for.

---

## Safety on existing droplets

Adding `otel-agent` to an existing droplet (WordPress, AnythingLLM, etc.) is
designed to be **non-disruptive** (filesystem-wise). For the security caveats
on the Docker socket mount, see "Threat model" below.

- Host filesystem mounts are bind-mounted **read-only**
  (`/var/lib/docker/containers:ro`, `/var/log:ro`, `/proc:ro`, `/sys:ro`, `/:ro`).
  The collector cannot tamper with host data through these mounts.
- The Docker socket is also mounted `:ro`, but `:ro` is a bind-mount flag, not
  a Docker API permission — anything that can `connect(2)` to the socket can
  issue write API calls. See the Threat model section.
- Health endpoint is bound to **`127.0.0.1:13133`** (loopback only), never
  exposed on the public host interface even though `network_mode: host`.
- Memory is **capped at 256MB** so the agent cannot starve your existing apps.
- The agent is a **single container** in its own compose project — it does not
  touch your app's compose stack, networks, or volumes.
- Roll back at any time:

  ```bash
  ssh root@<droplet-ip> 'cd /opt/otel-agent && docker compose down'
  ```

---

## Threat model — host-level access by design

The agent runs as **`user: 0:0`** (root inside the container) with `network_mode: host`,
the Docker socket mounted, and the host root filesystem mounted at `/hostfs`. This is
the standard topology required by the OpenTelemetry hostmetrics + docker_stats
receivers — every receiver in `config.yaml` needs at least one of these. The
collector itself does not modify host state, but **anyone with code execution
inside the agent container has full root on the host**. The mount mode flags do
not change this:

- **`/var/run/docker.sock:ro`** — the `:ro` is a **bind-mount** flag, NOT a Docker
  API permission. The mode prevents writing to the *socket inode*, but any
  process that can `connect(2)` to the socket can issue **any** Docker API call —
  `containers/create`, `exec`, `start` with `--privileged`, etc. So an attacker
  with code execution can launch a privileged container, mount `/`, and own the
  host. **`:ro` here gives almost no security; it is preserved only to make
  intent obvious in `docker inspect`.**
- **`/:/hostfs:ro`** — the host root mounted read-only. An attacker can READ
  any file on the host (including `/etc/shadow`, SSH keys, anything Infisical
  has written to disk on this droplet). Cannot write through this mount.
- **`network_mode: host`** — the collector binds `127.0.0.1:13133` (health) by
  default. With host network, any other bind in `config.yaml` lands on the host's
  network namespace — review additions carefully.

**What we actually rely on:**

1. The image is pinned (`otel/opentelemetry-collector-contrib:0.114.0`), not `:latest`,
   so a supply-chain compromise has to land a new SHA and break detection.
2. The collector binary is the official upstream — Trivy + Renovate flag CVEs
   and feed Dependabot.
3. The compose memory cap (256MB) limits exfiltration throughput, but only
   bounds it — does not prevent slow leakage.
4. The host does not store unencrypted application secrets at rest (Infisical →
   process env via `infisical run`). `.infisical-auth.env` is the one
   exception (`0600 root`) and is read by `infisical login` only.

**If you need stricter isolation** (future work, not in this PR):

- A docker-socket proxy (`tecnativa/docker-socket-proxy`) restricted to
  `CONTAINERS=1, GET only`, then point the docker_stats receiver at the proxy
  instead of the raw socket. This actually constrains what the collector can do
  via the Docker API.
- Split the collector: one rootless sidecar for hostmetrics (no socket needed),
  one for docker_stats (proxy-restricted socket only), one for filelog (no
  docker access). Each gets a smaller blast radius than the current monolith.

---

## First-time setup per droplet

### 0a. Create a Machine Identity in Infisical (one-time, very important)

The Infisical CLI on the droplet needs to log in non-interactively. That
requires a **Machine Identity** (Universal Auth) — NOT a personal user token /
JWT. Personal tokens are tied to a user and expire; Machine Identities are
scoped, long-lived, and revocable.

In the Infisical UI:

1. Go to project **otel** → **Access Control** → **Machine Identities** → **Create Identity**.
2. Name it `otel-agent-droplets` (or similar). Auth method = **Universal Auth**.
3. After creation, open the identity → **Client Secrets** → **Create Client Secret**.
   The Client Secret is shown **ONCE** — copy it immediately.
4. Still inside the identity, click **Add Project** → select **otel** → role
   **Viewer** (read-only on env `dev`, the secrets `OTEL_URL` + `OTEL_KEY`).
5. From the project URL `app.infisical.com/projects/<project-id>/...`, copy
   the `<project-id>`.

You now have three values: Client ID, Client Secret, Project ID.

### 0b. Export them on YOUR local machine

Export as env vars only — NEVER paste into a script or commit:

```bash
export INFISICAL_OTEL_PROJECT_ID="<project-id>"
export INFISICAL_OTEL_CLIENT_ID="<machine-identity-client-id>"
export INFISICAL_OTEL_CLIENT_SECRET="<machine-identity-client-secret>"
```

### 1. Bootstrap the droplet (once per droplet)

Installs the Infisical CLI (if missing) and writes
`<dir>/.infisical-auth.env` (0600 root) with the Machine Identity credentials.
Verifies the login works before exiting.

For the existing `burnedout-xyz` droplet (legacy Gemini path + Development env):

```bash
./scripts/bootstrap-otel-agent.sh \
  --droplet burnedout-xyz \
  --dir /root/observability/otel-agent \
  --env-slug dev
```

For any new droplet (uses the repo's standard `/opt/otel-agent` path):

```bash
./scripts/bootstrap-otel-agent.sh --droplet <name>
./scripts/bootstrap-otel-agent.sh --tag weown-ai           # whole tag
./scripts/bootstrap-otel-agent.sh --host root@198.51.100.42  # direct SSH
```

### 2. Deploy the agent

For `burnedout-xyz`:

```bash
./scripts/deploy-otel-fleet.sh \
  --droplet burnedout-xyz \
  --dir /root/observability/otel-agent
```

For any new droplet at the default path:

```bash
./scripts/deploy-otel-fleet.sh --droplet <name>
```

This copies `compose.yaml` + `config.yaml` to `<dir>/`, then runs
`infisical run -- docker compose up -d`. Telemetry should appear in SigNoz
Cloud within ~60s.

### Alternative: Ansible playbook (same result, declarative)

```bash
# burnedout-xyz
ansible-playbook otel-agent/deploy.yml \
  -i 'root@<burnedout-ip>,' \
  -e otel_agent_dir=/root/observability/otel-agent \
  -e infisical_env=dev

# new droplet at default path
ansible-playbook otel-agent/deploy.yml \
  -i 'root@<droplet-ip>,'
```

---

## Verifying it works

In the SigNoz Cloud UI:

- **Infrastructure → Hosts** → filter by `host.name=<droplet-hostname>` →
  CPU/mem/disk metrics should appear within 60s.
- **Infrastructure → Docker** → per-container CPU/mem for every container on
  the droplet (including all existing app containers).
- **Logs Explorer** → filter by `deployment.environment=production` AND
  `host.name=<droplet>` → docker container stdout/stderr streams.

On the droplet itself:

```bash
ssh root@<droplet-ip>
docker ps --filter name=otel-agent
docker logs --tail 50 otel-agent
curl -sf http://127.0.0.1:13133/health && echo OK
```

---

## Rotating the SigNoz ingestion key

1. In SigNoz Cloud UI: **Settings → Ingestion** → revoke the old key, create a
   new one, copy the value.
2. In Infisical project **otel** (env Development), update `OTEL_KEY` to the
   new value. Click commit.
3. On every droplet running the agent, force-recreate the container so it
   picks up the rotated value. Easiest:

   ```bash
   ./scripts/deploy-otel-fleet.sh --droplet <name>            # default path
   ./scripts/deploy-otel-fleet.sh --droplet burnedout-xyz \
       --dir /root/observability/otel-agent                   # legacy path
   ```

   Or manually on a single droplet:

   ```bash
   cd <otel_agent_dir>
   set -a; source .infisical-auth.env; set +a
   infisical login --method=universal-auth \
     --client-id="$INFISICAL_CLIENT_ID" \
     --client-secret="$INFISICAL_CLIENT_SECRET" --silent --plain
   HOSTNAME=$(hostname) infisical run \
     --projectId="$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENV_SLUG" \
     -- docker compose up -d --force-recreate
   ```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `OTEL_URL must be set by infisical run …` at startup | Bootstrap missing or wrong project ID | Re-run `bootstrap-otel-agent.sh` |
| Auth error on Infisical login | Machine Identity revoked or wrong client secret | Recreate Machine Identity in Infisical, re-bootstrap |
| Telemetry not in SigNoz UI after 2 min | Wrong region in `OTEL_URL` or invalid `OTEL_KEY` | Confirm both values in Infisical |
| `unsupported protocol scheme "ingest…"` | `OTEL_URL` missing `https://` | Use `https://ingest.us2.signoz.cloud` in Infisical, or redeploy (script normalizes) |
| `permission denied` on `docker.sock` | Collector runs as non-root | `compose.yaml` sets `user: "0:0"` — redeploy |
| `client version 1.25 is too old` | Collector image too old and/or `resourcedetection` `docker` detector | Use image `0.114.0+`, set `api_version: "1.44"`, omit `docker` from resourcedetection detectors |
| Agent OOMing | Too many containers/log volume on droplet | Bump memory cap in `compose.yaml` (`limits.memory`) |
| 13133 health check fails | Collector startup error | `docker logs otel-agent` |

---

## Compliance

- **NIST CSF 2.0**: DE.CM (continuous monitoring), DE.AE (event analysis),
  PR.DS (data security — secrets never on disk in plain text)
- **CIS Controls v8**: 8.5 (centralized log collection), 8.2 (log management),
  3.11 (encrypt sensitive data at rest)
- **ISO 27001:2022**: A.8.15 (logging), A.8.16 (monitoring activities)
