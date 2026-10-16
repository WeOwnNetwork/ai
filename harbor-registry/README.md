# Harbor registry (`registry.weown.tools`)

> #WeOwnVer: v5.1.3.1 · Status: ACTIVE

Self-contained Harbor v2.15.4 registry. Everything for this service lives in
this directory. It does not modify any other compose file, workflow, or droplet.

## Target

| Field | Value |
| --- | --- |
| Hostname | `registry.weown.tools` |
| Region | `atl1` |
| Size | `s5-2vcpu-4gb-80gb` (v5 Shared, 2 vCPU, 4 GB RAM, 80 GB disk, Ubuntu 24.04) |
| Droplet name | `registry-weown-tools` |
| App dir | `/opt/harbor-registry` (Caddy) |
| Harbor dir | `/opt/harbor` (pinned upstream installer) |
| Harbor pin | `v2.15.4` sha256 `eeb899cf7b626c925790adba87db9008dd1d73a693a72442651b5bdece9805c6` |
| Caddy pin | `caddy:2.11.7-alpine` digest `sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f` |
| Public IP | `<DROPLET_PUBLIC_IP>` (ops only; do not commit it) |

## What runs

Caddy is the only process with host ports. It listens on 80 and 443, redirects
HTTP to HTTPS, and gets a Let's Encrypt certificate for `registry.weown.tools`.
It reverse-proxies to Harbor's `nginx` container on the Harbor Docker network.

Harbor's own HTTPS is off. `external_url` is `https://registry.weown.tools`, so
`docker login` and the UI use that name. The proxy's host port mapping is
removed before `docker compose up`, so 8080 is not published on the droplet.

Upstream `install.sh` is not used. That script always runs `docker compose down -v`.
`deploy.sh` runs `./prepare --with-trivy` and then `docker compose up -d`.

## Persistent volumes

| Docker volume | Host path Harbor uses | Contents |
| --- | --- | --- |
| `harbor_database` | `/data/database` | Postgres data |
| `harbor_registry` | `/data/registry` | Image blobs |
| `harbor_jobservice` | `/data/job_logs` | Jobservice logs |
| `harbor-edge_caddy_data` | Caddy `/data` | Let's Encrypt certificates |
| `harbor-edge_caddy_config` | Caddy `/config` | Caddy state |

`deploy.sh` bind-mounts the three Harbor volumes onto `/data/...` and records
them in `/etc/fstab` (`bind,nofail`), so they survive container recreation and
reboot. A 4 GB swapfile is added because this size is Harbor's minimum and
Trivy is enabled.

## Layout

```
harbor-registry/
  Caddyfile                 TLS termination and reverse proxy
  docker-compose.yml        Caddy plus the named volumes
  harbor.yml.tmpl           Harbor config; passwords are placeholders
  deploy.sh                 Root bootstrap on the droplet
  scripts/provision-droplet.sh
  scripts/dns-a-record.sh
```

`harbor.yml` is rendered on the droplet only (`/opt/harbor/harbor.yml`, mode
0600). The admin and database passwords are written once to
`/root/harbor-registry-credentials.txt` (mode 0600) and are not printed.

## 1. Droplet

`doctl` must already be authenticated to the We Own Labs team. Contexts are
team-scoped, and the default context on a shared machine is often a different
team. The script creates the droplet only when `registry-weown-tools` does not
exist, attaches a reserved IPv4 in `atl1`, and opens inbound 22, 80, and 443
(plus UDP 443). It uses every SSH key already on that account.

```bash
./scripts/provision-droplet.sh
# last line: PUBLIC_IP=<ipv4>
```

SSH from the internet is allowed so operators whose keys are on the account can
log in. Narrow port 22 to an admin CIDR in the DigitalOcean firewall
`harbor-registry-fw` when that CIDR is known.

## 2. DNS

Public resolvers use Cloudflare (`erin.ns.cloudflare.com`,
`jack.ns.cloudflare.com`). Porkbun is the registrar and those are the
nameservers it publishes. The We Own Labs DigitalOcean zone for `weown.tools`
can hold the same A record, and `ns1.digitalocean.com` will answer it, but
that zone is not delegated. A record that exists only there leaves
`registry.weown.tools` as NXDOMAIN on 1.1.1.1 and 8.8.8.8, so Caddy's
Let's Encrypt HTTP-01 and TLS-ALPN challenges fail and browsers cannot open
the hostname.

Leave the domain nameservers on Cloudflare. Moving them to DigitalOcean would
drop names that exist only in Cloudflare and would take the proxied names off
the Cloudflare proxy. Publish the A record in Cloudflare, grey-cloud (DNS
only), so the HTTP-01 challenge reaches Caddy.

```bash
RECORD_IP=<DROPLET_PUBLIC_IP> ./scripts/dns-a-record.sh
```

The script reads `CLOUDFLARE_API_TOKEN` from the environment or an interactive
prompt. The token is not passed on argv. A token needs Zone DNS Edit on
`weown.tools`.

Dashboard equivalent:

| Type | Name | Content | Proxy |
| --- | --- | --- | --- |
| A | `registry.weown.tools` | `<DROPLET_PUBLIC_IP>` | DNS only |

After the certificate exists, orange-cloud is possible if the zone SSL mode is
Full (strict). Leave it grey-cloud until the first certificate is issued.

## 3. Install

From a checkout of this directory:

```bash
tar -C harbor-registry -cf - . \
  | ssh root@<DROPLET_PUBLIC_IP> 'mkdir -p /opt/harbor-registry && tar -C /opt/harbor-registry -xf -'
ssh root@<DROPLET_PUBLIC_IP> 'bash /opt/harbor-registry/deploy.sh'
```

`deploy.sh` installs the pinned Docker apt packages (Ubuntu 24.04), creates
the volumes, renders `harbor.yml`, starts Harbor with Trivy, then starts Caddy.

Read the admin password on the droplet. Don't paste it into Slack, email, or a ticket:

```bash
ssh root@<DROPLET_PUBLIC_IP> 'cat /root/harbor-registry-credentials.txt'
```

The UI user is `admin`. Change the password in the UI after the first login.
The file value is what Harbor stored at first boot; `deploy.sh` will not
overwrite `harbor.yml` on a later run.

## 4. Checks

```bash
curl -sI http://registry.weown.tools/ | head -n 5          # 308 or 301 to https
curl -fsS -o /dev/null -w '%{http_code}\n' https://registry.weown.tools/healthz   # 200
curl -sI https://registry.weown.tools/v2/ | head -n 1      # 401 until you log in
```

On the droplet, `docker ps` should show Harbor healthy and `caddy` up. Nothing
should be listening on `0.0.0.0:8080`.

```bash
ss -lnt | awk '$4 ~ /:8080$/'    # expect no public listener
```

## Client

```bash
docker login registry.weown.tools
docker tag <image> registry.weown.tools/<project>/<image>:<tag>
docker push registry.weown.tools/<project>/<image>:<tag>
```

Create a project in the UI before the first push. New projects are private.

## Upgrade

Pin a newer Harbor release in `deploy.sh` (`HARBOR_VERSION` and `HARBOR_SHA256`)
only after reading that version's upgrade notes. Do not re-run upstream
`install.sh`. Take a snapshot of the droplet first. `harbor.yml` and
`/data` must be left in place.
