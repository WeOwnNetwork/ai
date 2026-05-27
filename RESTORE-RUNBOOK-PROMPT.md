# burnedout.xyz — Local Restore + Production Reconciliation Runbook

**For AI assistant use.** Read this entire document before taking any action.

---

## Background & Context

burnedout.xyz is a WordPress site on a DigitalOcean droplet, managed via OpenTofu + Docker Compose. The architecture is:

```text
Internet → Caddy (TLS) → WordPress (Minimus hardened image) → MariaDB
```

All three run as Docker containers via `docker/compose.prod.yaml`, provisioned by `terraform/`.

### Production Is Currently BROKEN (as of ~April 28–30, 2026)

During a DB password rotation, someone ran `docker run` to restart MariaDB instead of using `docker compose`. This caused a cascade of 3 failures:

1. **MariaDB dropped off `wpnet`** (the Docker overlay network) — WordPress lost DB connectivity
2. **WordPress container was restarted using `wordpress:latest`** (Docker Hub default) — NOT the Minimus hardened image
3. **Caddy also fell off the network** — a custom Caddyfile was added to route to nginx inside the default WP image → **double proxy now running** (Caddy → nginx)

**Current production state:**

- Image: `wordpress:latest` (Docker Hub) — NOT Minimus
- Caddy: custom config routing to nginx — double proxy
- Containers: running **standalone** (`docker run`), NOT in the Docker Compose stack
- What IaC expects: Minimus image + standard Caddy config + MariaDB, all on `wpnet` via Docker Compose

### There Is Already a Local Backup (April 14, pre-incident)

```text
backups/burnedout-backup-20260414-014849.tar.gz
```

This backup was taken April 14, before the incident. It contains:

- `wordpress.sql` — full DB dump
- `wp-content/` — plugins, themes, uploads
- `wp-config.php` — production config (different DB creds — do NOT use)
- `Caddyfile` — the production Caddyfile at time of backup (clean, pre-incident)
- `dot-env` — production .env at time of backup (contains production secrets — do NOT commit)
- `compose.yaml` — production compose at time of backup
- `containers.txt`, `wp-image-digest.txt`, `images.txt` — state snapshots

---

## Overall Mission

**Phase 1 — Get a fresh backup from production** (so we have current content, not just April 14)
**Phase 2 — Restore the fresh backup locally** (using the IaC local compose + Minimus images)
**Phase 3 — Validate the site runs locally** (production content, IaC architecture)
**Phase 4 — Write the production reconciliation recipe** (the playbook to fix prod using IaC)

Do the phases in order. **Phase 2 can start with the April 14 backup** if the production server is inaccessible or the fresh backup takes time — validate the process works first, then repeat with the fresh backup.

---

## Phase 1 — Get a Fresh Backup from Production

### Option A: Run backup.sh directly against the production droplet

```bash
# From the project root
./scripts/backup.sh root@<PROD_DROPLET_IP>
```

This will SSH into the droplet, run the backup script there, and print the backup filename and SCP command. Then pull it locally:

```bash
scp root@<PROD_DROPLET_IP>:/opt/burnedout/backups/<BACKUP_NAME>.tar.gz backups/
```

### Option B: Pull from DO Spaces (if Mohammed has already uploaded)

The team's DO Spaces bucket for backups — check with Mohammed or the team for the bucket name and credentials. Use `doctl compute` or `s3cmd` / AWS CLI (DigitalOcean Spaces is S3-compatible).

### What backup.sh captures (from the broken production server)

Even though production is in a bad state, `backup.sh` will still work because it:

- Uses `docker exec burnedout-wordpress-1` to dump the DB — the container is running (just not via compose)
- Uses `docker cp burnedout-wordpress-1:/var/www/html/wp-content` for content
- Captures `containers.txt` and `images.txt` — these will document the `wordpress:latest` image and the broken state (useful forensics)

> **Note:** The production Caddyfile in this backup will be the broken/custom one. Do NOT use it locally. Use `docker/Caddyfile.local` for local development.

---

## Phase 2 — Restore Backup into Local Docker Compose

The local environment uses `docker/compose.local.yaml` with the **Minimus hardened WordPress image** — this is what production SHOULD be using. The backup data (DB + wp-content) will be loaded into this clean, IaC-correct environment.

### Step 1: Log into Minimus registry

```bash
docker login reg.mini.dev -u minimus -p <YOUR_MINIMUS_TOKEN>
```

Verify:

```bash
docker pull reg.mini.dev/1923/wordpress-fluentsmtp:latest
docker pull reg.mini.dev/caddy:2
```

> **Important:** Always use the private FluentSMTP image (`reg.mini.dev/1923/wordpress-fluentsmtp:latest`), NOT the base Minimus image (`reg.mini.dev/wordpress:latest`). The base image strips PHP's PDO extension which FluentSMTP requires for DB logging — using it causes fatal errors on login.

### Step 2: Set up local .env

```bash
cd docker
cp .env.example .env
```

Edit `docker/.env` — set your local DB passwords (anything safe for local dev):

```env
WP_IMAGE=reg.mini.dev/1923/wordpress-fluentsmtp   # or the image you have access to
CADDY_IMAGE=reg.mini.dev/caddy:2
MYSQL_DATABASE=wordpress
MYSQL_USER=wordpress
MYSQL_PASSWORD=localdev
MYSQL_ROOT_PASSWORD=localdevroot
```

> **Important:** The local passwords do NOT need to match production. WordPress will use whatever is in this `.env`. The DB dump from production will be imported and WordPress will connect using these local credentials.

### Step 3: Extract the backup

```bash
cd ~/projects/burnedout.xyz/backups
# Use the fresh backup, or the April 14 one for initial testing:
tar xzf burnedout-backup-20260414-014849.tar.gz
# (or your fresh backup name)
```

You'll get a directory like `backups/burnedout-backup-20260414-014849/` with:

```text
wordpress.sql
wp-content/
wp-config.php    ← ignore for local (use .env credentials instead)
dot-env          ← do NOT use or commit — contains production secrets
Caddyfile        ← do NOT use locally — use docker/Caddyfile.local
...
```

### Step 4: Start the local stack (DB only first)

```bash
cd docker
docker compose -f compose.local.yaml up -d db
# Wait ~10s for MariaDB to initialize
docker compose -f compose.local.yaml logs db | tail -5
```

Wait until logs show: `ready for connections` or `mariadbd: ready for connections`

### Step 5: Import the database

```bash
# From the project root
BACKUP_DIR="backups/burnedout-backup-20260414-014849"   # adjust to your backup name

docker exec -i wp-db \
  mysql -u root -plocaldevroot wordpress \
  < "${BACKUP_DIR}/wordpress.sql"
```

> If the DB already has tables, you may need to drop and recreate:
>
> ```bash
> docker exec -i wp-db mysql -u root -plocaldevroot -e "DROP DATABASE wordpress; CREATE DATABASE wordpress;"
> ```
>
> Then re-run the import.

Verify the import:

```bash
docker exec -i wp-db mysql -u root -plocaldevroot -e "SHOW TABLES;" wordpress
```

### Step 6: Copy wp-content into the volume

The `wp_data` Docker volume is where WordPress files live. We need to copy the production `wp-content` into it.

```bash
# Start the WordPress container (it will mount the volume at /var/www/html)
docker compose -f compose.local.yaml up -d wordpress

# Wait for WP container to initialize (it may run WP setup scripts)
sleep 5

# Copy production wp-content over the container's wp-content
docker cp "${BACKUP_DIR}/wp-content" wp-app:/var/www/html/
```

Fix ownership:

```bash
docker exec wp-app chown -R www-data:www-data /var/www/html/wp-content
```

### Step 7: Fix WordPress URLs in the database (search-replace)

Production database has `https://burnedout.xyz` hardcoded in rows. For local dev, replace with `http://localhost`.

**Method A — WP-CLI (if available in the image):**

```bash
docker exec wp-app wp search-replace 'https://burnedout.xyz' 'http://localhost' --all-tables --allow-root
```

**Method B — SQL directly (if WP-CLI not in image):**

```bash
docker exec -i wp-db mysql -u root -plocaldevroot wordpress << 'SQL'
UPDATE wp_options SET option_value = REPLACE(option_value, 'https://burnedout.xyz', 'http://localhost') WHERE option_name IN ('siteurl', 'home');
UPDATE wp_posts SET guid = REPLACE(guid, 'https://burnedout.xyz', 'http://localhost');
UPDATE wp_posts SET post_content = REPLACE(post_content, 'https://burnedout.xyz', 'http://localhost');
UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, 'https://burnedout.xyz', 'http://localhost') WHERE meta_value LIKE '%burnedout.xyz%';
SQL
```

> **Note:** `compose.local.yaml` does NOT set `WORDPRESS_CONFIG_EXTRA` — only `compose.prod.yaml` does (for `https://${DOMAIN}`). Updating the DB values directly is required for local development to avoid redirect loops.

### Step 8: Start the full stack

```bash
docker compose -f compose.local.yaml up -d
```

### Step 9: Validate

Open <http://localhost> in your browser. You should see the burnedout.xyz site running with production content, using the Minimus WordPress image and the local Caddy config (HTTP only, no double proxy).

Check:

- Site loads ✓
- Admin login works at <http://localhost/wp-admin> ✓
- Plugins are active (Fluent Forms, FluentCRM, etc.) ✓
- Media/uploads are visible ✓

Useful debug commands:

```bash
docker compose -f compose.local.yaml logs -f wordpress    # WP errors
docker compose -f compose.local.yaml logs -f db           # DB errors
docker compose -f compose.local.yaml logs -f caddy        # Caddy errors
docker exec wp-app php -r "echo PHP_VERSION;" && echo    # Confirm PHP version
docker inspect wp-app | grep Image                        # Confirm Minimus image
```

---

## Phase 3 — Validation Checklist

Before proceeding to Phase 4, confirm all of the following:

- [ ] Site loads at <http://localhost> without errors
- [ ] wp-admin is accessible and login works
- [ ] Plugins are listed and active in wp-admin → Plugins
- [ ] Uploaded media is visible (wp-admin → Media)
- [ ] The Docker image in use is the Minimus image (NOT `wordpress:latest`)
  - Verify: `docker inspect wp-app | grep -i image`
- [ ] No double proxy (Caddy is proxying directly to WordPress on port 9000, not to nginx)
  - Verify: `docker compose -f compose.local.yaml logs caddy` — should show PHP FastCGI, not nginx upstream
- [ ] All three containers on `wpnet` network
  - Verify: `docker network inspect burnedout-xyz_wpnet` (or `docker_wpnet`)

**If the site loads but shows a fresh WP install:** The DB import didn't take or the URL didn't redirect. Check Step 5 and 7.

**If wp-content/uploads are missing:** The `docker cp` in Step 6 may not have overwritten correctly. Try:

```bash
docker exec wp-app ls /var/www/html/wp-content/uploads/
```

---

## Phase 4 — Production Reconciliation Playbook

This is the recipe to take production from its broken state back to IaC-managed, Minimus-image state. Run this ONLY after Phase 3 validates locally.

> **Pre-conditions:**
>
> - SSH key rotation must be complete (P0 — May 1 deadline)
> - A fresh backup of production is in hand and has been tested locally (Phase 2–3 complete)
> - `tofu plan` has been run and confirmed it will NOT destroy the production droplet

### Recipe Overview

```text
1. Run final production backup  →  upload to DO Spaces
2. tofu plan  →  verify no destroy
3. deploy.sh  →  push IaC compose + Caddyfile to server
4. SSH into server  →  stop standalone containers
5. docker compose up  →  bring up IaC stack (Minimus images)
6. Restore DB + wp-content from backup
7. URL check (should already be correct — prod URLs stay prod URLs)
8. Test live site
9. Monitor for 30 minutes
```

### Detailed Steps

#### Step P1 — Final production backup before any changes

```bash
./scripts/backup.sh root@<PROD_DROPLET_IP>
# Pull it locally:
scp root@<PROD_DROPLET_IP>:/opt/burnedout/backups/<LATEST_BACKUP>.tar.gz backups/
# Upload to DO Spaces (Mohammed has credentials)
```

#### Step P2 — tofu plan (verify safe)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in real values (gitignored)
tofu init
tofu plan
```

**STOP if the plan shows `destroy` on the droplet or its volumes.** The plan should only show updates to firewall rules, monitoring, or no-ops for the droplet itself. If it plans to destroy, investigate before proceeding — likely a tfvars mismatch with existing state.

#### Step P3 — Push IaC files to production

```bash
./scripts/deploy.sh root@<PROD_DROPLET_IP>
```

This uploads `compose.prod.yaml` → `/opt/burnedout/compose.yaml`, `Caddyfile` → `/opt/burnedout/Caddyfile`, and `.env.prod` → `/opt/burnedout/.env`.

> You must have `docker/.env.prod` with production values. Create it from `.env.prod.example` with real production passwords. Do NOT commit it.

#### Step P4 — SSH in and stop standalone containers

```bash
ssh root@<PROD_DROPLET_IP>
```

On the server:

```bash
# List running containers (the broken standalone ones)
docker ps

# Stop and remove the standalone WordPress + Caddy containers
docker stop burnedout-wordpress-1 && docker rm burnedout-wordpress-1
docker stop burnedout-caddy-1 && docker rm burnedout-caddy-1
# Leave MariaDB running — we need the data still in its volume

# Confirm MariaDB is still up
docker ps | grep db
```

#### Step P5 — Bring up IaC stack

```bash
cd /opt/burnedout
docker compose up -d
```

Docker Compose will:

- Pull the Minimus WordPress image
- Start WordPress, MariaDB, and Caddy — all on `wpnet`
- Caddy will serve via FastCGI to WordPress (no double proxy)

**The site will 500 at this point** because the DB credentials changed during the incident — that's expected. We'll fix in the next step.

#### Step P6 — Restore DB from backup

On the server, import the `wordpress.sql` from the pre-change backup (or the fresh backup from P1 if you have more current content):

```bash
# Copy the SQL to the server
scp backups/<BACKUP_DIR>/wordpress.sql root@<PROD_DROPLET_IP>:/opt/burnedout/

# SSH back in
ssh root@<PROD_DROPLET_IP>

# Import into the running IaC MariaDB container
source /opt/burnedout/.env
docker exec -i burnedout-db-1 mysql -u root -p"${MYSQL_ROOT_PASSWORD}" wordpress < /opt/burnedout/wordpress.sql

# Or if DB/table names differ:
docker exec -i burnedout-db-1 mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e \
  "DROP DATABASE IF EXISTS wordpress; CREATE DATABASE wordpress;"
docker exec -i burnedout-db-1 mysql -u root -p"${MYSQL_ROOT_PASSWORD}" wordpress < /opt/burnedout/wordpress.sql
```

#### Step P7 — Restore wp-content from backup

```bash
# From local machine — copy wp-content to server
scp -r backups/<BACKUP_DIR>/wp-content root@<PROD_DROPLET_IP>:/tmp/

# SSH in
ssh root@<PROD_DROPLET_IP>

# Copy into the running WordPress container
docker cp /tmp/wp-content burnedout-wordpress-1:/var/www/html/
docker exec burnedout-wordpress-1 chown -R www-data:www-data /var/www/html/wp-content
```

#### Step P8 — Verify site is live

```bash
curl -I https://burnedout.xyz
# Expect: HTTP/2 200 or HTTP/1.1 301 → 200
```

Check from a browser. Admin login should work. All plugins active. No double proxy.

Confirm the correct images are running:

```bash
ssh root@<PROD_DROPLET_IP> "docker ps --format 'table {{.Names}}\t{{.Image}}'"
```

Expected:

```text
burnedout-wordpress-1   reg.mini.dev/1923/wordpress-fluentsmtp (or similar Minimus path)
burnedout-db-1          mariadb:11
burnedout-caddy-1       reg.mini.dev/caddy:2
```

#### Step P9 — Monitor

```bash
ssh root@<PROD_DROPLET_IP> "cd /opt/burnedout && docker compose logs -f"
```

Watch for errors for ~30 minutes post-restore.

---

## Key Files Reference

| File | Purpose |
|---|---|
| `docker/compose.local.yaml` | Local dev stack (HTTP only, no TLS) |
| `docker/compose.prod.yaml` | Production stack (HTTPS via Caddy) |
| `docker/Caddyfile.local` | Local Caddy config — FastCGI to wordpress:9000 |
| `docker/Caddyfile` | Production Caddy config — same FastCGI pattern |
| `docker/.env.example` | Template for local `.env` — **copy to `docker/.env`** |
| `docker/.env.prod.example` | Template for production env — **copy to `docker/.env.prod`** |
| `scripts/backup.sh` | Run on/against droplet — creates datestamped tar.gz |
| `scripts/deploy.sh` | Push IaC files to droplet and restart compose |
| `terraform/terraform.tfvars.example` | Template — **copy to `terraform/terraform.tfvars`** |
| `backups/` | Local backup storage — gitignored |

## Critical Reminders

1. **Never commit** `terraform.tfvars`, `docker/.env`, `docker/.env.prod`, or any extracted backup files — all are gitignored, but double-check before any `git add`.
2. **Local DB credentials do NOT need to match production.** WordPress reads credentials from the .env at runtime.
3. **Production Caddyfile from the backup is broken** (custom double-proxy config). Use `docker/Caddyfile.local` for local, `docker/Caddyfile` (repo version) for production.
4. **tofu plan MUST be reviewed before apply.** If it plans to destroy the droplet, stop and debug.
5. **The 30-minute production downtime window is pre-approved** — but only AFTER local test passes and tofu plan is confirmed safe.
6. **Minimus registry login required** before pulling images on any new machine or droplet.
