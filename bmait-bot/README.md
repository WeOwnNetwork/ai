# b.MAIT.bot — Hermes Agent droplet

> #WeOwnVer: v4.3.5.1 · Status: COMMITTED (branch `feature/shahid-bmait-bot-deployment`, 2026-08-30) · Domain: `b.mait.bot`

Standalone Compose stack: Nous Hermes Agent gateway + Caddy TLS for `https://b.mait.bot`. Sibling of `imait-bot/` (same pattern — Hermes gateway + buzz CLI + Caddy — different identity and domain). Target droplet: `bmait-bot-prod-atl1` (atl1 · s-1vcpu-2gb · ubuntu-24-04-x64). Do not point this compose at another host (empty volumes, silent data loss).

Git holds **shared infrastructure** for one Hermes gateway (`b.MAIT.bot`). Team members do **not** pick channels by editing git or `.env`. They add **b.MAIT.bot** as a channel member in Buzz Desktop (role `bot`) and `@` mention it. Hermes watches **all joined channels** (`channels: []`). Desktop **Add Agent** is only for local runtimes — it will not list this gateway.

This droplet is one Buzz **community** (relay URL is ops, set once on the host). A different community needs that host `.env` changed by ops, or a separate gateway. Other Buzz agents in the same community are separate identities; they share a channel by membership, not by forking this repo.

| Service | Image | Role |
| --- | --- | --- |
| `bmait-bot` | `nousresearch/hermes-agent` + `buzz` CLI | Gateway + Buzz. API on `:8080`. |
| `caddy` | `caddy:2.8-alpine` | Auto-SSL `:80`/`:443` → `bmait-bot:8080`. |

Identity **b.MAIT.bot**. The Hermes image does not ship `buzz`. The Dockerfile builds it from `block/buzz` at `6df7eba24d49b6a2c7f0188b19e24f3df999678c` (same pin as `docs/PRJ-432.2-buzz-deployment.md`) → `/usr/local/bin/buzz`.

## Ops overlay (host `.env`, not git)

Copy `.env.example`-style variables into `.env` on the box **once** when standing up the droplet. This is not a per-teammate workflow.

| Variable | Purpose |
| --- | --- |
| `BUZZ_RELAY_URL` | HTTPS origin of the Buzz community this gateway serves |
| `BUZZ_RELAY_WSS` | `wss://` of the same relay |
| `BUZZ_PRIVATE_KEY` | Bot identity (nsec or hex) |
| `OPENROUTER_API_KEY` | Inference |
| `BUZZ_CHANNELS` | Leave empty so the UI membership list is the source of truth |

Leave `BUZZ_CHANNELS` empty. Pinning UUIDs here (or in git) blocks "add from Buzz UI".

## Secrets

Public repo: **never commit `.env`**. Host `.env` is bind-mounted at `/opt/data/.env` (must be world-readable, not `0600` root-only). Inject secrets with a TTY paste (`read -rs`), never argv, never git. Agents must not `cat` `.env` or `docker inspect` this stack.

## DNS

`b.mait.bot` A → droplet public IP (ops-only; not in git). Orange-cloud is OK: Caddy HTTP-01 has issued through Cloudflare on the sibling. SSL/TLS: **Full (strict)** once the origin has a Let's Encrypt cert.

## Deploy (post-review)

```bash
# 1. Stage files to the new droplet (never commit/push first — human review)
rsync -az --exclude '.env' \
  ./ root@<DROPLET_PUBLIC_IP>:/opt/bmait-bot/

# 2. On the box: install Docker + Compose plugin
ssh root@<DROPLET_PUBLIC_IP>
apt-get update && apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# 3. Create host .env (TTY paste, never in git)
cd /opt/bmait-bot
# BUZZ_RELAY_URL / BUZZ_RELAY_WSS / BUZZ_PRIVATE_KEY / OPENROUTER_API_KEY

# 4. Launch
docker compose up -d --build
docker compose ps
docker compose logs -f bmait-bot
```

`docker compose restart` re-reads the bind-mounted `.env` (Hermes dotenv). It does **not** rebuild the image. Rsync of `config.yaml` overwrites host model/channel pins — exclude it when the box has instance edits.

## Buzz membership

Closed relays: add the bot pubkey from that community's Buzz compose dir (not strfry):

```bash
cd /opt/<buzz-app>/buzz/deploy/compose
./run.sh add-member <64_HEX> --role member
```

Private channels also need **channel** membership (role `bot`), not only relay membership. Do not restart the relay stack for membership. If `users get` returns `[]`, publish kind:0 from the bot container:

```bash
docker compose exec -T bmait-bot sh -c 'set -a; . /opt/data/.env; set +a; /usr/local/bin/buzz users set-profile --name b.MAIT.bot --about "Hermes Agent Bot"'
```

Team chat: `GATEWAY_ALLOW_ALL_USERS=true` (host `.env`). Channels still require mention (`require_mention: true`).

## Pre-flight checklist (before deploy)

- [x] Human review of the staged files (committed 2026-08-30)
- [ ] DigitalOcean droplet `bmait-bot-prod-atl1` created (atl1 · s-1vcpu-2gb · ubuntu-24-04-x64 · SSH key 57190333)
- [ ] DNS: `b.mait.bot` A record → droplet IP (Cloudflare)
- [ ] `.env` populated on host via TTY secure handoff
- [ ] R-011: explicit human go for live deploy
