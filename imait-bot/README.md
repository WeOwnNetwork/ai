# i.MAIT.bot — Hermes Agent droplet

> #WeOwnVer: v4.3.4.1 · Status: ACTIVE · Domain: `i.mait.bot`

Standalone Compose stack: Nous Hermes Agent gateway + Caddy TLS for `https://i.mait.bot`. Not a `*-docker` copier render. One droplet: `imait-bot-prod`. Do not point this compose at another host (empty volumes, silent data loss).

Git holds **shared infrastructure** for one Hermes gateway (`i.mait.bot`). Team members do **not** pick channels by editing git or `.env`. They add **i.MAIT.bot** as a channel member in Buzz Desktop (role `bot`) and `@` mention it. Hermes watches **all joined channels** (`channels: []`). Desktop **Add Agent** is only for local runtimes — it will not list this gateway.

This droplet is one Buzz **community** (relay URL is ops, set once on the host). A different community needs that host `.env` changed by ops, or a separate gateway. Other Buzz agents in the same community are separate identities; they share a channel by membership, not by forking this repo.

| Service | Image | Role |
| --- | --- | --- |
| `imait-bot` | `nousresearch/hermes-agent` + `buzz` CLI | Gateway + Buzz. API on `:8080`. |
| `caddy` | `caddy:2.8-alpine` | Auto-SSL `:80`/`:443` → `imait-bot:8080`. |

Identity **i.MAIT.bot**. The Hermes image does not ship `buzz`. The Dockerfile builds it from `block/buzz` at `6df7eba24d49b6a2c7f0188b19e24f3df999678c` (same pin as `docs/PRJ-432.2-buzz-deployment.md`) → `/usr/local/bin/buzz`.

## Ops overlay (host `.env`, not git)

Copy `.env.example` → `.env` on the box **once** when standing up the droplet. This is not a per-teammate workflow.

| Variable | Purpose |
| --- | --- |
| `BUZZ_RELAY_URL` | HTTPS origin of the Buzz community this gateway serves |
| `BUZZ_RELAY_WSS` | `wss://` of the same relay |
| `BUZZ_PRIVATE_KEY` | Bot identity (nsec or hex) |
| `OPENROUTER_API_KEY` | Inference |
| `BUZZ_CHANNELS` | Leave empty so the UI membership list is the source of truth |

Leave `BUZZ_CHANNELS` empty. Pinning UUIDs here (or in git) blocks “add from Buzz UI”.

## Secrets

Public repo: **never commit `.env`**. Host `.env` is bind-mounted at `/opt/data/.env` (must be world-readable, not `0600` root-only). Inject `BUZZ_PRIVATE_KEY` with `scripts/inject-secrets.sh`. To set only the LLM key later: `scripts/set-openrouter-key.sh` (TTY paste, never argv). Generate `API_SERVER_KEY` on the box (`openssl rand -hex 32`). Agents must not `cat` `.env` or `docker inspect` this stack.

## DNS

`i.mait.bot` A → droplet public IP (ops-only; not in git). Orange-cloud is OK: Caddy HTTP-01 has issued through Cloudflare. SSL/TLS: **Full (strict)** once the origin has a Let's Encrypt cert.

## Deploy

```bash
rsync -az --exclude '.env' --exclude '.droplet-ip' \
  ./imait-bot/ root@<DROPLET_PUBLIC_IP>:/opt/imait-bot/

ssh root@<DROPLET_PUBLIC_IP>
APP_DIR=/opt/imait-bot bash /opt/imait-bot/scripts/bootstrap-host.sh
bash /opt/imait-bot/scripts/inject-secrets.sh /opt/imait-bot/.env
cd /opt/imait-bot
docker compose up -d --build
docker compose ps
docker compose logs -f imait-bot
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
docker compose exec -T imait-bot sh -c 'set -a; . /opt/data/.env; set +a; /usr/local/bin/buzz users set-profile --name i.MAIT.bot --about "Hermes Agent Bot"'
```

Team chat: `GATEWAY_ALLOW_ALL_USERS=true` (in `.env.example`). Channels still require mention (`require_mention: true`).
