# PRJ-435 — Shepherd POC deployment (`shepherd.weown.tools`)

> #WeOwnVer: v4.3.5.1 · Status: ACTIVE · Ticket: PRJ-435

## Summary

Deploy Shepherd (reversible agent traces) on a DigitalOcean droplet for
`shepherd.weown.tools`, with Caddy TLS and Cloudflare DNS in front. Repo wrapper
lives under [`shepherd-docker/`](../shepherd-docker/).

## Target

| Field | Value |
| --- | --- |
| Domain | `shepherd.weown.tools` |
| Droplet label | `shepherd-poc` |
| Droplet IP | `<DROPLET_PUBLIC_IP>` (placeholder in git; live value is ops-only) |
| SSH | `root@<DROPLET_PUBLIC_IP>` |
| App root | `/opt/shepherd-docker` |
| Region / size | `atl1` / `s-2vcpu-4gb-amd` (2 vCPU / 4 GB; Basic `s-2vcpu-4gb` is not offered in atl1) |
| Image | `ubuntu-24-04-x64` |
| Shepherd pin | `shepherd-ai==0.3.0` |
| Caddy pin | `caddy:2.10.2-alpine` |

## Decisions

1. **Same DigitalOcean team as Buzz.** `doctl` context `weown-labs` / team
   **We Own Labs** (the account that owns the Buzz droplets).
2. **POC HTTP surface, not a live LLM.** `MOCK_PROVIDER=true` — no API keys in
   git or on the host for this slice. Upstream has no published web image, so
   the droplet builds `shepherd-docker/Dockerfile`.
3. **Caddy in Compose** (not a host package), matching Buzz: `cap_drop: ALL` +
   `no-new-privileges`; Caddy gets `NET_BIND_SERVICE` only. Shepherd `:8080` is
   unpublished on the host.
4. **First ACME is grey-cloud.** Cloudflare A record for `shepherd.weown.tools`
   must be **DNS only** until Let's Encrypt HTTP-01 succeeds. Then SSL/TLS can
   move to Full (strict) and the record may be orange-clouded.
5. **Public repo:** no real droplet IPs or secrets in git.

## Port map (audit)

| Component | Listen | Notes |
| --- | --- | --- |
| shepherd POC HTTP | `:8080` | compose network only |
| caddy | `:80`/`:443` | only published host ports |

## Execution checklist

### 1. Provision

```bash
doctl auth ls
doctl account get    # expect team We Own Labs
# droplet: name shepherd-poc, region atl1, size s-2vcpu-4gb,
# image ubuntu-24-04-x64, team SSH keys (including shahid-wsl-key)
```

### 2. Host preparation

```bash
ssh root@<DROPLET_PUBLIC_IP>
# Docker CE + compose plugin, git, ufw 22/80/443
# 4G /swapfile + fstab
mkdir -p /opt/shepherd-docker
```

### 3. App files + start

```bash
# from the ai repo
scp -r shepherd-docker root@<DROPLET_PUBLIC_IP>:/opt/shepherd-docker
ssh root@<DROPLET_PUBLIC_IP> 'cd /opt/shepherd-docker && docker compose up -d --build'
```

### 4. DNS / Cloudflare (human)

- DNS-only (grey-cloud) `A` → `<DROPLET_PUBLIC_IP>`
- After cert issues: optional orange-cloud + Full (strict)

### 5. Verification

```bash
docker compose -f /opt/shepherd-docker/docker-compose.yml ps
curl -fsS http://127.0.0.1/healthz
# after DNS + ACME:
curl -fsS -o /dev/null -w '%{http_code}\n' https://shepherd.weown.tools/healthz
```

## Follow-ups (not in this slice)

- Infisical injection (if a live provider key is ever added)
- Full `*-docker` copier + OpenTofu droplet module
- Pin a published Shepherd image digest when upstream ships one
- SigNoz / OTel scrape

## Compliance notes

- Public repo: no real droplet IPs, no secrets in git.
- Supply-chain: pinned `shepherd-ai==0.3.0` and `caddy:2.10.2-alpine`.
- #OnlyHumanApproves for future pushes and production changes.
