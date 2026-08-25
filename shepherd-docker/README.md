# Shepherd Docker — WeOwn POC wrapper

> #WeOwnVer: v4.3.5.1 · Status: ACTIVE · Ticket: PRJ-435 · Scope: `shepherd.weown.tools` POC

Self-host [Shepherd](https://github.com/shepherd-agents/shepherd) (reversible
agent-execution traces) on a DigitalOcean droplet behind Cloudflare + Caddy TLS.
`MOCK_PROVIDER=true` keeps the POC on the deterministic/offline lane — no live
LLM API keys.

Upstream ships **no published web image**. This directory builds a thin HTTP
surface (`shepherd-ai==0.3.0` + stdlib server on `:8080`) so Caddy can terminate
HTTPS the same way `buzz-docker/` does.

## Architecture

```
Internet → Cloudflare (DNS only / grey-cloud for first ACME) → Caddy :443 → shepherd :8080
                                                                      │
                                                                      ▼
                                                            shepherd_traces volume
```

## Ports

| Service | Container port | Host exposure |
| --- | --- | --- |
| `shepherd` (HTTP) | `8080` | none (Caddy only) |
| `caddy` | `80` / `443` | published |

## Quick deploy (droplet)

```bash
# 1) Host prep: Docker CE + Compose plugin, git, UFW 22/80/443, 4G swap
# 2) Copy this directory to the box
scp -r shepherd-docker root@<DROPLET_PUBLIC_IP>:/opt/shepherd-docker
ssh root@<DROPLET_PUBLIC_IP>
cd /opt/shepherd-docker
cp .env.example .env   # already matches POC values; no secrets
docker compose up -d --build

# 3) Verify
docker compose ps
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1/healthz || true
```

TLS (Let's Encrypt HTTP-01) succeeds only after DNS exists. Create a **DNS-only
(grey-cloud)** Cloudflare A record for `shepherd.weown.tools` → droplet public
IP **before** expecting `https://` to work. Orange-cloud can be turned on later
with SSL/TLS mode **Full (strict)**.

## Files in this directory

| Path | Purpose |
| --- | --- |
| `docker-compose.yml` | Shepherd + Caddy stack |
| `Dockerfile` | Pinned `shepherd-ai==0.3.0` + POC HTTP server |
| `app/server.py` | Health, status, trace listing on `:8080` |
| `Caddyfile` | TLS reverse proxy to `shepherd:8080` |
| `.env.example` | Placeholder env (no secrets) |

## Cloudflare

1. A record: `shepherd.weown.tools` → `<DROPLET_PUBLIC_IP>`
2. **DNS only (grey cloud)** until Caddy has issued the Let's Encrypt cert
3. Then optional: proxied (orange cloud) + SSL/TLS **Full (strict)**

## Related

- Runbook: [`docs/PRJ-435-shepherd-poc-deployment.md`](../docs/PRJ-435-shepherd-poc-deployment.md)
- Upstream: <https://github.com/shepherd-agents/shepherd>
