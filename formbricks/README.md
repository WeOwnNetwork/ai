# Formbricks (`forms.weown.tools`)

> #WeOwnVer: v4.2.1.1 · Status: ACTIVE

Self-hosted [Formbricks](https://formbricks.com/) on DigitalOcean behind Cloudflare.

## Stack

| Service | Image | Role |
| --- | --- | --- |
| formbricks | `ghcr.io/formbricks/formbricks:latest` | Web app (`:3000`) |
| postgres | `pgvector/pgvector:pg16` | Primary DB (pgvector required) |
| redis | `redis:alpine` | Cache / rate limits (AOF volume) |
| hub | `ghcr.io/formbricks/hub:latest` | Formbricks Hub (v5 baseline) |
| cube | `cubejs/cube:v1.6.6` | Analytics semantic layer |
| caddy | `caddy:2-alpine` | Origin reverse proxy `:80` / `:443` |

Formbricks **v5** requires Hub + Cube in addition to App + Postgres + Redis. Secrets live only in `/opt/formbricks/.env` on the droplet (never in git).

A **2 GB** droplet needs a swapfile (created by `deploy.sh`) and the compose mem limits below — without `NODE_OPTIONS=--max-old-space-size=1024` the app OOMs under Next.js 16.

## Deploy

```bash
# From this directory (WSL/Git Bash). Replace host with the droplet address.
chmod +x scripts/deploy.sh
./scripts/deploy.sh root@<INGRESS_LB_IP>
```

The deploy script:

1. Installs Docker Engine + Compose if missing
2. Adds a 2G swapfile (needed on 2 GB droplets)
3. Syncs compose/Caddy/cube files to `/opt/formbricks`
4. Generates `.env` **on the server** with `openssl rand` (values never echoed)
5. Runs `docker compose up -d` and checks `http://127.0.0.1:3000`

## Cloudflare

- DNS: proxied A/AAAA for `forms.weown.tools` → droplet
- SSL/TLS mode: **Full** (Caddy uses `tls internal` origin cert)
- For **Full (Strict)**: install a [Cloudflare Origin CA](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/) cert and update `Caddyfile`

## Local `.env`

Copy `.env.example` → `.env` for local bring-up only. Do not commit `.env`.

## Verify

```bash
ssh root@<INGRESS_LB_IP> 'cd /opt/formbricks && docker compose ps && curl -sI http://127.0.0.1:3000'
curl -sI https://forms.weown.tools
```

First visit opens Formbricks onboarding (create the initial admin user).
