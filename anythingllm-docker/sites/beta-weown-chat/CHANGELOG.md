# beta-weown-chat - Changelog

All notable changes to this deployment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [#WeOwnVer](https://github.com/WeOwnNetwork/ai/blob/main/docs/VERSIONING_WEOWNVER.md) (calendar-driven `vSEASON.MONTH.WEEK.ITERATION`).

---

## [Unreleased] — dashboard and embed-filter review fixes

### Security

- **The document library listed every file on the instance, not only this tenant's (weown-fleet#48).** AnythingLLM's system document store is instance-wide; the library merged all of it with the tenant's workspaces, so a customer saw operator test files, unattached files, and another brand's document titles on a shared instance. Replace-on-duplicate matched the same list. The store pass now reads only `DASHBOARD_DOCUMENT_FOLDER` and uploads are written there. Unset, malformed or `custom-documents` fails closed (workspace documents only). Test: `node dashboard/test-library-scope.mjs`.
  - This site: `DASHBOARD_DOCUMENT_FOLDER: "beta-weown-chat"`. On the next deploy, stored files that are in neither workspace and not in that folder leave the library; they stay in storage. Documents embedded in either workspace still show.

- **An uploaded SVG logo could run script on the instance's own origin.** The upload check ran regexes on the raw file, so character references (`href="j&#x61;vascript:…"`), DTD entities and namespace-prefixed elements (`<x:script xmlns:x="…svg">`) got through, and `/app/brand/logo` is public and same-origin with the dashboard.
  - Every `/app/brand/*` response now carries `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; sandbox` and `X-Content-Type-Options: nosniff`, and SVG is served as UTF-8. This also covers logos stored before this fix.
  - The upload check now refuses DOCTYPE/ENTITY, `&#` references, namespace-prefixed elements, processing instructions other than the XML declaration, non-UTF-8 encodings, NUL bytes, `handler`/`listener`, SMIL that retargets `href`, and any `href` or `url()` that is not a `#fragment`. Inkscape/Illustrator native SVGs (prefixed editor elements, DOCTYPE) are now refused; export as plain SVG or PNG.
  - Checked in a real browser: the same hostile stored logo ran script on the old server and did not on the new one (opaque origin).
- **`/healthz` returned raw socket errors** (`connect ECONNREFUSED <ip>:3001`) to unauthenticated callers. It now answers `unreachable` or `timeout` and logs the detail server-side.
- **embed-filter took the upstream host from the request.** An absolute-form (`GET http://other/x`), `//other/x` or `/\other/x` target was proxied to `other`. The host is now fixed from `ALLM_URL`, the request supplies only path and query, and any other target shape is a 400.
- **embed-filter container hardening**: `user: "1000:1000"`, `read_only: true`, `cap_drop: [ALL]`, `no-new-privileges:true`. Verified with `node:20-alpine` locally under exactly those settings: healthcheck 200, uid 1000, `CapEff` 0, `NoNewPrivs` 1, writes to the root filesystem refused, and `embed-filter/test.js` (full proxy path, in-memory widget cache) passes inside the container.

### Fixed

- **Review follow-ups (2026-10-02, #276 review):** backup exits 1 when the dashboard could not be quiesced (archive kept and offloaded, never reported clean) and skips retention, so a failed run never prunes an older archive; restore prints "Dashboard state restore complete" only when it was; `bootstrap-product` kills its FIFO writer on exit; new `dashboard/test-origins.mjs` (userinfo origins refused; the 400 names a rejected entry by position only).

- **Booking button text failed WCAG contrast on two themes.** `contrastInk` used a fixed luminance cut-off and put white on Harbor Gold (2.42:1) and WeOwn blue (2.73:1). It now picks whichever of `#0f172a` or white has the higher contrast ratio (7.38:1 and 6.53:1), and pure black for mid-tone fills where neither reaches 4.5:1 (`#777777`–`#7f7f7f`; `#7a7a7a` was 4.29:1 at best, now 4.89:1). The dashboard preview uses the same rule instead of hard-coded white.
- **Saving one card cleared the other's unsaved changes.** Appearance and Booking share the Copy button's "save first" guard but had one dirty flag. Each card now has its own flag, Copy is blocked while either is set, a logo upload no longer clears pending theme edits, clearing the accent counts as an edit, and saving Appearance no longer overwrites unsaved booking inputs. An edit made while a card's save is still in flight is kept, and that card stays unsaved.
- **`/api/documents/content` reported `locationVerified: true` for a bare filename.** It is now true only when ALLM returns a folder-qualified location equal to the requested path.
- **An oversize request body got no response.** `readBody` destroyed the socket, so the browser saw "could not reach the server", or `/api/chat` answered a misleading 400 "message required". It now drains the body and answers **413** with the limit (`12.5 MB` for chat, `256 KB` elsewhere) and `Connection: close`. A body past twice the cap is still dropped.
- Tests: `dashboard/test-embed-appearance.mjs` (hand-derived WCAG ratios, sanitiser payloads, the real UI script in a fake DOM) and new `dashboard/test-http.mjs` (the real server over HTTP against a stub AnythingLLM); `embed-filter/test.js` group 21. Each fails against the previous code.

## [Unreleased] — OpenBao deploy review sweep: store address, tokens, key gate (2026-09-30)

### Changed (deploy contract)

- **Every deploy of this site now needs `BAO_ADDR_INSTANCE`**: the platform store's URL as this droplet dials it (its VPC address). The address had been committed here in four places (`ansible/deploy.yml` x3, `docker/entrypoint-bao.sh`), and this repo is public. It is now supplied at deploy time and written only into the copy of `entrypoint-bao.sh` uploaded to the box:

  ```bash
  BAO_ADDR_INSTANCE=https://<store-vpc-address>:8200 ./scripts/deploy.sh root@<ip>
  ```

  Without it the playbook stops at its first task, before anything on the box changes. `--check --diff` reports the entrypoint as changed but does not print the filled-in address (`diff: false` on that task). The value is the fleet registry's `operator.bao_addr_instance`. Git history still holds the old address; this only stops new exposure. **Still open**: removing it from history means rewriting and force-pushing `main` of this public repo, and it would stay in existing clones and forks anyway, so that is a separate human decision. The address is a VPC address that is not reachable from outside, and it is not a credential. The AppRole `role_id` stays in the render: it is an identifier, not a credential.

### Security

- **A store key whose NAME contains a NUL byte is refused by the host gate** (both compose-up paths). Before, `A<NUL>B` passed the name check as two names and shifted the export loop, which exported `COMPOSE_PROJECT_NAME=evil` past the denylist in a local test with dummy JSON.
- **The wrap token reaches the host on stdin with `no_log`**, not through `environment:`, where it was on the droplet's process list and in `-vvv` output.
- **`embed-filter` runs as uid 1000, with no capabilities and `no-new-privileges`.**
- **`scripts/bootstrap-product.sh` keeps the admin JWT and API key off curl's argv.**
- **`devsec.hardening` pinned to `10.6.0`.**

### Fixed

- A failed `docker restart` of a consumer after a new secret-id now fails the deploy with the command to run, instead of being skipped silently.
- Store keys named `KVJSON`, `LOGIN_JS` or `KV_EXPORTS_JS` reach the app (they were unset after the exports).
- `./site.sh smoke-test` works (`REPO_ROOT` was never set).
- `scripts/deploy.sh` detects the backend from `docker/compose.prod.yaml`. Since #250 (2026-09-10) this OpenBao site's `deploy.sh` does not require `INFISICAL_PROJECT_ID`.

### Docs

- README: the intro names the OpenBao seam, the CA path is `<openbao-repo>/governance/certs/openbao-platform-ca.crt`, the secret-id path is `/opt/beta_weown_chat/.bao-secret-id`, and step 3 documents `BAO_ADDR_INSTANCE`.
- cloud-init header and `final_message` describe the OpenBao bootstrap (no Infisical CLI, no rotation log). `user_data` is in `ignore_changes`, so this does not touch the droplet.
- `entrypoint-bao.sh`: the login-attempt comment has the right arithmetic.

## [Unreleased] — review sweep: bootstrap secrets, embed allowlist, embed-filter privileges

### Security

- **`scripts/bootstrap-product.sh`**: the JWT and Developer API key reach curl as a config on a pipe, not argv; Infisical writes go through `--file` on a FIFO named `push.yaml` (YAML keeps the value exactly; nothing is written to disk) instead of `KEY=value` on argv. **`allowlist_domains` is sent as a comma-separated string**: a JSON array was stored as NULL, which AnythingLLM treats as "allow every site". Entries are normalised to origins (`https://host`) as the dashboard does, the instance's own origin is included, and the list is also stored as the dashboard seed `EMBED_ALLOWLIST_DOMAINS`. A URL with userinfo is refused, in the script and in the dashboard's `normOrigin()`. Rejected entries are named by position only, never echoed, since one may carry a password. A blank answer means only the instance's own origin, never no allowlist. On a re-run with an existing embed, the dashboard owns the list: the script prints the exact dashboard action instead of writing AnythingLLM directly. A failed store write stops the run, and the admin password is stored before the admin is created.
- **`embed-filter`** runs as uid 1000 with `cap_drop: [ALL]` and `no-new-privileges` (it listens on 3002 and only reads its code).

### Changed

- README: the OpenBao CA copy step uses an `<openbao-checkout>` placeholder, not one workstation's path.
- Every render carries `.python-version` (3.12.12) so `ansible-playbook` resolves under pyenv even when the global is `system` (added to the template in PR #203; recorded here).

---

## [Unreleased] — smoke test API check probes the real health endpoint

### Fixed

- **Smoke test check 3.2 (AnythingLLM API health) was meaningless (2026-09-30).** It probed `/api/v1/health` (a SigNoz path; AnythingLLM answers it with its HTML page and a 200) and passed on ANY non-empty body, while an empty SSH result read as "API down" (a false FAIL on the chat.weown.dev deploy of 2026-09-29). It now probes `/api/ping` inside the app container, the endpoint the compose healthcheck and the deploy's health wait use, and passes only on `"online":true`. A failed SSH is reported as NOT CHECKED. Template and `sites/beta-weown-chat` kept identical. Every in-container probe (3.2, 3.3, 3.4) now uses `docker exec` on the container found by its compose labels. A bare `docker compose exec` has to parse `compose.yaml`, whose `${ANYTHINGLLM_IMAGE:?}` only exists inside the deploy's `infisical run`. From a plain SSH session it therefore failed and returned nothing, which is why 3.3/3.4 only ever reported INFO/SKIP.

---

## [Unreleased] — backups now include the dashboard's state

### Fixed

- **Backups skipped the dashboard's own volume, `beta_weown_chat_dashboard_state`.** `backup.sh` archived only `storage` and `caddy_data`, so a restore dropped the embed allowlist domains, the document delete-locks and (with ai#256) the embed appearance, booking button and uploaded logos.
  - `backup.sh` adds `dashboard_state.tar.gz` when the volume exists, and prints "skipped" on a box that has not been redeployed since the dashboard shipped. The existence check avoids `docker run -v` creating an empty, unlabelled volume.
  - `restore.sh` restores it only when the archive has it (older backups leave the volume untouched), stopping and restarting `dashboard` around the restore.
  - Tested with a local Docker volume round trip: missing volume, back up → change → restore, and restore with no archive (6/6 pass).
  - Follow-up (Copilot reviews on #263/#264), **restore**: no dashboard error can leave AnythingLLM stopped any more. If `dashboard` can't be stopped, its volume is left untouched. A failed stop still gets a best-effort restart, and the restore still exits 1. If extraction fails, or the dashboard doesn't restart, that is now REPORTED; before, a failed restart was silently ignored (`|| true`). In every case the restore finishes, restarts AnythingLLM, prints FINISHED WITH ERRORS and exits 1.
  - Follow-up, **backup**: the dashboard is stopped for the few seconds `tar` takes, so a logo change (logo file + `embed-appearance.json`) is one consistent snapshot. It is restarted whatever `tar` does, and only if it was running; a failed archive fails the backup. If `compose ps` can't report its state, the backup prints a WARNING and archives without stopping it. If the stop itself fails, the backup warns, archives without quiescing, and still restarts the dashboard (it used to exit before the restart).
  - Follow-up, **dashboard**: `server.js` writes embed domains tmp + rename, like every other state file.

---

## [Unreleased] — Harbor View embed appearance + booking CTA

### Added

- **Dashboard Public tab: chat widget appearance + booking button** — Soft Light / WeOwn / Harbor Gold / Midnight / Forest themes, logo upload (SVG harden + raster magic-byte sniff), accent override, assistant name, live mini-preview (booking CTA stacked above FAB when URL set; "What are your hours?" sample). Booking URL (https, or http for localhost) + label; empty URL hides the companion CTA. Snippet generation injects theme colors, brand image, `data-no-sponsor`, and the companion booking script when set. Persisted under `DASHBOARD_STATE_DIR` (`embed-appearance.json`, `embed-brand/`, `booking.json`). APIs: `GET/POST /api/embed-appearance`, `POST/DELETE /api/embed-logo`, `GET/POST /api/booking`, public `/brand/logo` + `/brand/weownchat-mark.svg`.

---

## [Unreleased] — private chat no longer shares one conversation

### Fixed

- **Dashboard private chat wrote every message into the workspace's shared default conversation** ([weown-fleet#55](https://github.com/WeOwnDev/weown-fleet/issues/55)). The page opened on "Main conversation", and a send without a thread went to `/api/v1/workspace/<private>/chat`, which carries the last 20 turns of that shared history into each answer. Measured on a live instance on 2026-09-17: a customer-style test question was answered with a document list drawn from months-old unrelated test chats, naming files not loaded in the workspace.
  - `server.js`: `/api/chat` without `thread` now creates a new thread, answers inside it and returns it as `thread`. Nothing is written to the default conversation any more.
  - `index.html`: the dashboard opens on a new conversation. "Main conversation" stays readable, and sending from it starts a new conversation.
  - Existing default-conversation history is left untouched; clearing it on a live instance is a separate, owner-approved step.

---

## [Unreleased] — embed reasoning-leak filter

### Added

- **`embed-filter`** — a zero-dependency Node service that strips model reasoning blocks (`<think>…</think>`, configurable via `STRIP_TAGS`) out of the **public** embed API before they leave the box. Caddy now routes `/api/embed/*` through it, ahead of the AnythingLLM catch-all.

  **Why:** the chat widget hides reasoning blocks, so a rendered page looks clean while `POST /api/embed/<id>/stream-chat` — which is **unauthenticated** — returns the model's private reasoning to any consumer. Measured on a live client site 2026-09-01: 1,809 chars returned, of which 1,445 were reasoning that quoted the workspace **system prompt verbatim**, including the instruction that the knowledge base is sample data rather than the client's real offerings. That is system-prompt disclosure, not cosmetic noise (WO-Disc-961, filed 2026-07-31 as "unconfirmed" and never re-probed).

  It holds **no secret and reads no store**, deliberately: putting the strip in the `dashboard` container would couple a customer's public website widget to a credentialled process, so an AppRole failure would take the customer's site down — the coupling class fixed in #213/#214/#216.

---

## [Unreleased] — pgvector support

### Added

- **pgvector** as a `vector_db` option. When `vector_db=pgvector`, both `compose.prod.yaml` and `compose.local.yaml` inject fail-loud `PGVECTOR_CONNECTION_STRING` and `PGVECTOR_TABLE_NAME` env vars for per-instance table isolation on a shared pgvector substrate. From Infisical in prod, from `.env.local` locally. Existing `lancedb` sites render byte-identically.

---

## [v3.3.4.1] — 2026-04-23

### Added

- Initial anythingllm-docker copier template for DigitalOcean droplet deployments
- Docker Compose stack: AnythingLLM (LanceDB embedded) + Caddy reverse proxy
- Infisical runtime secret injection — zero application secrets on disk
  - `infisical run` fetches OPENROUTER_API_KEY, JWT_SECRET, ADMIN_EMAIL at container startup
  - Infisical Machine Identity (Client ID + Secret) is the only credential in terraform.tfvars
- Skinny backup system with grandfather-father-son retention policy
  - Daily backups retained for 30 days
  - Monthly backups (1st of month) retained for 12 months
  - Yearly backups (Jan 1st) kept forever
- DigitalOcean Spaces remote backup upload via `aws s3` CLI
- Idempotent deploy script (`scripts/deploy.sh`) using Infisical runtime injection
- Backup (`scripts/backup.sh`) and restore (`scripts/restore.sh`) scripts
  - Restore supports automatic fetch from DO Spaces if backup not found locally
- Terraform/OpenTofu infrastructure: droplet, reserved IP, firewall, monitoring alerts
  - CPU, memory, and disk utilization alerts via DigitalOcean monitoring
- Cloud-init bootstrap with Docker, Infisical CLI, unattended-upgrades
- Security hardening: firewall (22, 80, 443), Docker daemon config (log rotation, overlay2)
- Caddy automatic TLS with Let's Encrypt + security headers

### Security

- No application secrets committed to git or written to droplet disk
- All sensitive configuration sourced from Infisical Cloud at runtime
- Backup encryption at rest via DO Spaces SSE
- Docker volumes for persistent storage (no bind mounts for app data)

### Compliance

- NIST CSF 2.0: PR.DS (data security), PR.AC (access control), DE.CM (monitoring)
- CIS Controls v8 IG1: CIS 3.11 (encrypt sensitive data at rest), CIS 4.1 (secure config)
- ISO 27001-ready: A.5.17 (authentication info), A.8.24 (use of cryptography)

---

## Template Parameters Used

| Parameter | Value |
|-----------|-------|
| `project_name` | beta-weown-chat |
| `domain` | beta-chat.weown.dev |
| `do_region` | atl1 |
| `droplet_size` | s-2vcpu-4gb-amd |
| `anythingllm_image` | mintplexlabs/anythingllm:1.9.1 |
| `caddy_image` | reg.mini.dev/caddy:2 |
| `llm_provider` | openrouter |
| `vector_db` | lancedb |
| `infisical_project_id` |  |
| `infisical_environment` | prod |
| `enable_skinny_backups` | True |
| `backup_remote_storage` | do-spaces |

---

## Migration Notes

If migrating from the Kubernetes Helm deployment in `ai/anythingllm/`:

1. **Data**: Export the PVC contents as a tarball and restore into the Docker volume
2. **Secrets**: Move from Kubernetes secrets (`anythingllm-secrets`) to Infisical project
3. **Ingress**: Replace NGINX Ingress + cert-manager with Caddy (automatic TLS)
4. **Backups**: Replace Kubernetes CronJob with cron.daily + `infisical run` wrapper

See `README.md` for detailed migration procedures.
