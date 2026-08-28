# i.MAIT.bot — Hermes Agent droplet

> #WeOwnVer: v4.3.4.1 · Status: ACTIVE · Domain: `i.mait.bot`

Standalone Compose stack: Nous Hermes Agent gateway on Buzz (`https://dev.weown.buzz` / `wss://dev.weown.buzz`), Caddy TLS for `https://i.mait.bot`. Not a `*-docker` copier render. One droplet: `imait-bot-prod`. Do not point this compose at another host (empty volumes, silent data loss).

| Service | Image | Role |
| --- | --- | --- |
| `imait-bot` | `nousresearch/hermes-agent` + `buzz` CLI | Gateway + Buzz. API on `:8080`. |
| `caddy` | `caddy:2.8-alpine` | Auto-SSL `:80`/`:443` → `imait-bot:8080`. |

Identity **i.MAIT.bot**. Ops channel labels: `FELG.WeOwn.Buzz` / `#CCC-MAIT-SQUAD`. Hermes watches **UUIDs** (`BUZZ_CHANNELS`); empty = all joined.

The Hermes image does not ship `buzz`. The Dockerfile builds it from `block/buzz` at `6df7eba24d49b6a2c7f0188b19e24f3df999678c` (same pin as `docs/PRJ-432.2-buzz-deployment.md`) → `/usr/local/bin/buzz`.

## Secrets

Public repo: **never commit `.env`**. Host `.env` is bind-mounted at `/opt/data/.env` (must be world-readable, not `0600` root-only). Inject `BUZZ_PRIVATE_KEY` and `OPENROUTER_API_KEY` with `scripts/inject-secrets.sh`. Generate `API_SERVER_KEY` on the box (`openssl rand -hex 32`). Agents must not `cat` `.env` or `docker inspect` this stack.

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

`docker compose restart` re-reads the bind-mounted `.env` (Hermes dotenv). It does **not** rebuild the image.

## Buzz membership (dev.weown.buzz)

Closed relay. After the bot has a keypair, add it from the **Buzz** compose dir (not strfry):

```bash
cd /opt/dev-weown-buzz/buzz/deploy/compose
./run.sh add-member <64_HEX> --role member
```

Do not restart the relay stack for membership. If `users get` returns `[]`, publish kind:0 from the bot container:

```bash
docker compose exec -T imait-bot sh -c 'set -a; . /opt/data/.env; set +a; /usr/local/bin/buzz users set-profile --name i.MAIT.bot --about "Hermes Agent Bot"'
```

Team chat: `GATEWAY_ALLOW_ALL_USERS=true` (in `.env.example`). Channels still require mention (`require_mention: true`).
