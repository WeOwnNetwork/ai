# Run the whole WeOwn Chat stack on your laptop

For working on the **customer dashboard UI** (`anythingllm-docker/template/dashboard/`) without
touching a customer's droplet. You get AnythingLLM, the dashboard you edit, and the billing site,
wired together the way they are in production.

## What you need first

| | |
|---|---|
| Docker Desktop | running, ~6 GB free disk (the AnythingLLM image is large) |
| `node`, `jq`, `curl`, `openssl` | on your PATH — `node` is used once, to hash the dashboard password |
| this repo | cloned; no Infisical, no OpenBao, no VPN, no droplet access needed |

## One command

```bash
cd <repo>
./dev/up.sh
```

Safe to re-run: it reuses what exists and only creates what is missing. First run pulls images and
builds the billing container, so give it a few minutes. `./dev/up.sh --down` stops it,
`./dev/up.sh --destroy` also deletes the local data.

## The three surfaces, and how you log in to each

**Every password is generated on your machine and written to `dev/.env.dev`. Nothing is printed to
the terminal.** Read them with `cat dev/.env.dev`.

| Surface | URL | Who you are | Credential |
|---|---|---|---|
| **AnythingLLM** | http://localhost:$ALLM_PORT/ | **the support person** — the WeOwn-side admin | `ALLM_ADMIN_USER` (`support@weown.net`) + `ALLM_ADMIN_PASSWORD` |
| **Dashboard** | http://localhost:$DASHBOARD_PORT/app/ | **the customer** — the only surface a customer ever sees | `DASHBOARD_PASSWORD` |
| **Billing** | http://localhost:$BILLING_PORT/admin/ | **WeOwn staff** | user `weown-admin` + `BILLING_BREAK_GLASS_PASSWORD` |

### Ports are chosen for you, once

The first `up.sh` picks a free host port for each service and records it in `dev/.env.dev` as
`BILLING_PORT`, `ALLM_PORT` and `DASHBOARD_PORT`. Later runs reuse those numbers, so your URLs
stay stable and bookmarkable.

It works this way because the obvious defaults are the ones most likely to be taken. Billing wants
8000, which is the Django default, so any other Django project on your machine owns it first. When
that happened here, `docker compose up` failed partway, the bootstrap that mints the AnythingLLM
API key never ran, and the dashboard sat in a restart loop complaining about a missing key — three
steps away from the actual cause.

`up.sh` prints the URLs it settled on when it finishes. If a port you recorded is later taken by
something else, it names the port and the key rather than letting compose fail on its own.

### Logging in to AnythingLLM as the support person

`up.sh` creates `support@weown.net` as the ALLM admin and switches the instance into **multi-user
mode**, which is exactly what happens on a real tenant. That account is the *support* identity: it
administers the instance, manages documents and workspaces, and is **not** the customer's login.

⚠️ **The order matters and the script encodes it.** AnythingLLM's `/api/system/*` endpoints are
unauthenticated *only* until multi-user mode is switched on, and the token from
`/api/request-token` does **not** authorize them afterwards. So the Developer API key is minted
first and multi-user mode is enabled second. If you enable multi-user by hand in the UI before the
key is minted, you have closed the window — `./dev/up.sh --destroy` and start again.

### Logging in to the dashboard as the customer

The dashboard has two ways in: **Keycloak SSO** (production) and a **break-glass password**
(local). Locally there is no Keycloak, so you use the password. That is the same break-glass path
production keeps for when SSO is down, not a dev-only shim.

## The loop you actually work in

The dashboard source is bind-mounted, so your editor changes the running container's files
directly. Restart it to pick them up:

```bash
docker compose --env-file dev/.env.dev -f dev/compose.dev.yaml restart dashboard
```

Edit `anythingllm-docker/template/dashboard/` — the **template**, never `sites/<name>/dashboard/`.
A site directory is a *render*; the next `copier` run overwrites it and silently reverts you.

## How billing and the dashboard relate

They are **separate applications that share a customer, not a database**. Billing owns the
commercial record — customer, subscription, instance row, and the `provisioning → active` status a
customer watches on their account page. The dashboard owns the *instance* surface. The dashboard
links out to billing via `BILLING_URL` (locally `http://localhost:$BILLING_PORT`); billing never calls the
dashboard.

Provisioning is what connects them, and it is **not** part of this local stack: on the fleet, a
paid billing row is read by `provision-from-billing.sh`, which creates the droplet, then writes
`active` back to billing. Locally you get the two ends without that middle, which is the right
scope for UI work.

## Where local differs from production — read this before trusting a local result

| | local | production |
|---|---|---|
| **AnythingLLM image** | public `mintplexlabs/anythingllm:1.16.1` | a **private-registry** build pinned to **v1.15.0** |
| Secrets | generated into `dev/.env.dev` | Infisical or OpenBao, injected at container start |
| Billing login | Django admin, break-glass superuser | Keycloak OIDC |
| Dashboard login | break-glass password | Keycloak SSO, password as fallback |
| TLS / domain | plain HTTP on localhost | Caddy, real domain, Let's Encrypt |
| LLM | none unless you set `OPENAI_API_KEY` | per-tenant OpenRouter key, spend-capped |

**The image version is the one that can mislead you.** Local runs a *newer* AnythingLLM than any
customer. If something works locally and not on a tenant, check that difference before assuming
your change is wrong.

**Chat will not answer locally** unless you put a key in `OPENAI_API_KEY` in `dev/.env.dev` and set
`LLM_PROVIDER` accordingly. Everything else — documents, workspaces, uploads, the library, the
whole dashboard UI — works without one.

## When it breaks

| symptom | cause | fix |
|---|---|---|
| `could not mint an API key` | multi-user mode was enabled before the key existed | `./dev/up.sh --destroy && ./dev/up.sh` |
| dashboard 502 or empty | started before `ALLM_ADMIN_API_KEY` was in `.env.dev` | `./dev/up.sh` again — it restarts the dashboard last |
| library previews empty | `ALLM_DOCUMENTS_PATH` not readable | the compose mounts ALLM storage read-only; confirm the `dashboard` service is on the current file |
| billing 500 on a page | migrations behind | `docker compose --env-file dev/.env.dev -f dev/compose.dev.yaml exec billing python manage.py migrate` |
| a port you recorded is now taken | another project grabbed it since the first run | `up.sh` says which port and which key; free it, or edit that key in `dev/.env.dev` and re-run |

Logs: `docker compose --env-file dev/.env.dev -f dev/compose.dev.yaml logs -f <service>`.
