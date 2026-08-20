# Buzz Docker — WeOwn deployment wrapper

> #WeOwnVer: v4.3.2.4 · Status: ACTIVE · Scope: `buzz.weown.tools` single-node relay

Self-host [Block Buzz](https://github.com/block/buzz) (agentic chat / Nostr relay workspace)
on a DigitalOcean droplet behind Cloudflare + Caddy TLS.

## Architecture

```
Internet → Cloudflare (proxied DNS) → Caddy :443 → buzz-relay :3000
                                         │
                    ┌────────────────────┼────────────────────┐
                    ▼                    ▼                    ▼
               Postgres 17            Redis 7              MinIO (S3)
```

Production path uses Block's upstream bundle at `deploy/compose/` (image pull from
`ghcr.io/block/buzz`, not a local build). This directory mirrors that shape for
repo review and documents the WeOwn host layout.

## Ports (internal)

| Service | Container port | Host exposure |
| --- | --- | --- |
| `relay` (HTTP/WS) | `3000` | none when TLS on (Caddy only) |
| `relay` health | `8080` | internal (`/_liveness`, `/_readiness`) |
| `relay` metrics | `9102` | internal |
| `postgres` | `5432` | none |
| `redis` | `6379` | none |
| `minio` | `9000` / `9001` | none |
| `caddy` | `80` / `443` | published |

## Quick deploy (droplet)

Pin both the **git ref** and the **container digest** (§3.8 / §3.13). Never deploy
floating `:main` / `:latest`.

```bash
# Pins used by the initial buzz.weown.tools deploy — bump deliberately.
BUZZ_GIT_SHA=6df7eba24d49b6a2c7f0188b19e24f3df999678c
BUZZ_IMAGE=ghcr.io/block/buzz@sha256:815e8e57bd09efb6a6857e9e635bbcdbb4411f5a8f6b3595ef4eb636c4620163

# 1) Host prep: Docker CE + Compose plugin, 4G swap, UFW 22/80/443
# 2) Clone + checkout pinned upstream commit
mkdir -p /opt/buzz-weown-tools
git clone https://github.com/block/buzz.git /opt/buzz-weown-tools/buzz
git -C /opt/buzz-weown-tools/buzz checkout "$BUZZ_GIT_SHA"

# 3) Secrets on host only (never paste into chat / agent context)
cd /opt/buzz-weown-tools/buzz/deploy/compose
# from this repo:
#   scp buzz-docker/scripts/bootstrap-host-env.sh root@<DROPLET_IP>:/tmp/
BUZZ_DOMAIN=buzz.weown.tools BUZZ_IMAGE="$BUZZ_IMAGE" \
  /tmp/bootstrap-host-env.sh "$(pwd)"

# 4) Start with automatic HTTPS (Let's Encrypt via Caddy)
BUZZ_COMPOSE_TLS=true ./run.sh start

# 5) Verify
BUZZ_COMPOSE_TLS=true ./run.sh status
curl -fsS -o /dev/null -w '%{http_code}\n' https://buzz.weown.tools/
curl -fsS -o /dev/null -w '%{http_code}\n' https://buzz.weown.tools/_liveness
```

Owner private key is written to `/root/buzz-owner-keypair.txt` (`0600`) by the
bootstrap script. Retrieve it yourself over SSH — do not ask an agent to `cat` it.

## Cloudflare

- DNS: proxied (orange-cloud) `A` record for `buzz.weown.tools` → droplet public IP
- SSL/TLS mode: **Full (strict)** once Caddy has a Let's Encrypt cert
- HTTP-01 ACME works through Cloudflare proxy when origin `:80` is open

## Files in this directory

| Path | Purpose |
| --- | --- |
| `docker/compose.prod.yaml` | WeOwn-mirrored prod stack (relay + deps + Caddy) |
| `docker/.env.example` | Placeholder env (no secrets; pinned image digest) |
| `docker/Caddyfile` | TLS reverse proxy to `relay:3000` |
| `scripts/bootstrap-host-env.sh` | Host-side secret generation (requires `BUZZ_IMAGE`) |

## Ops notes

- Prefer upstream `BUZZ_COMPOSE_TLS=true ./run.sh …` on the live box so you stay
  aligned with Block's `compose.yml` + `compose.caddy.yml`.
- `BUZZ_IMAGE` is required and must be an immutable digest/tag (compose fails loud otherwise).
- Closed membership: add members with `./run.sh add-member <64_HEX> --role member` (or `--role admin`).
- Mobile QR pairing: run `scripts/enable-pairing-relay.sh` (or ship `pairing-relay` + Caddy `/pair` + `BUZZ_PAIRING_RELAY_URL` as in `compose.prod.yaml`). Confirm NIP-11 has `pairing_relay_url`.
- **Windows Desktop notifications (DMs / @mentions):** Buzz on Windows false-denies toast permission at every start ([block/buzz#2445](https://github.com/block/buzz/issues/2445)), then turns off Desktop alerts so real events never toast. Do **not** fire test toasts. On each Windows machine run once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\buzz-docker\scripts\windows-fix-desktop-notifications.ps1
```

  After that, open Buzz from Start Menu / Desktop (those shortcuts go through the silent interceptor). Settings → Notifications → Desktop alerts = ON. Requires Python on PATH.
- Backup checklist: `./run.sh backup-hint` (`.env`, Postgres, MinIO, git volume, Caddy data).

## Related

- Runbook: [`docs/PRJ-432.2-buzz-deployment.md`](../docs/PRJ-432.2-buzz-deployment.md)
- Upstream compose README: <https://github.com/block/buzz/blob/main/deploy/compose/README.md>
