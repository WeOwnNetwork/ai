# Buzz site — `dev.weown.buzz`

> #WeOwnVer: v4.3.3.1 · Status: ACTIVE · Scope: isolated Buzz relay for `dev.weown.buzz`

Separate droplet from production `felg.weown.buzz` / `buzzweowntools-*`. Same DO
team (**We Own Labs**) and DO project (**WeOwn.tools**), different host, volumes,
Postgres, Redis, MinIO, and owner keypair. Never reuse the felg droplet or its
`/opt/buzz-weown-tools` path.

## Target

| Field | Value |
| --- | --- |
| Domain | `dev.weown.buzz` |
| Droplet label | `dev-weown-buzz-2vcpu-4gb-amd-atl1` |
| Droplet IP | `<DROPLET_PUBLIC_IP>` (ops-only; do not commit) |
| SSH | `root@<DROPLET_PUBLIC_IP>` |
| App root | `/opt/dev-weown-buzz` |
| Upstream path | `/opt/dev-weown-buzz/buzz/deploy/compose` |
| Region / size | `atl1` / `s-2vcpu-4gb-amd` (parity with felg Buzz) |
| DO project | WeOwn.tools |
| Upstream git pin | `6df7eba24d49b6a2c7f0188b19e24f3df999678c` |
| Image pin | `ghcr.io/block/buzz@sha256:815e8e57bd09efb6a6857e9e635bbcdbb4411f5a8f6b3595ef4eb636c4620163` |

## Isolation guarantees

- New droplet + VPC NIC only — no shared Docker volumes with felg
- App root `/opt/dev-weown-buzz` (not `/opt/buzz-weown-tools`)
- Fresh secrets from `bootstrap-host-env.sh` (new owner / relay keys, DB passwords)
- Cloudflare DNS name `dev.weown.buzz` only — does not rewrite felg records

## Deploy (operator)

```bash
# From repo root (Ubuntu WSL or Linux with doctl + ssh)
export BUZZ_SITE_DOMAIN=dev.weown.buzz
export BUZZ_SITE_APP_ROOT=/opt/dev-weown-buzz
./buzz-docker/sites/dev-weown-buzz/scripts/01-create-droplet.sh
# note <DROPLET_PUBLIC_IP> from script output (do not commit it)

./buzz-docker/sites/dev-weown-buzz/scripts/02-bootstrap-host.sh <DROPLET_PUBLIC_IP>
./buzz-docker/sites/dev-weown-buzz/scripts/03-enable-pairing.sh <DROPLET_PUBLIC_IP>
./buzz-docker/sites/dev-weown-buzz/scripts/04-cloudflare-a-record.sh <DROPLET_PUBLIC_IP>
```

Owner private key (human-only, never agent context):

```bash
ssh root@<DROPLET_PUBLIC_IP> 'cat /root/buzz-owner-keypair.txt'
```

## Verify

```bash
curl -fsS -o /dev/null -w '%{http_code}\n' https://dev.weown.buzz/
curl -fsS -o /dev/null -w '%{http_code}\n' https://dev.weown.buzz/_liveness
curl -fsS https://dev.weown.buzz/ | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("version"), d.get("pairing_relay_url"))'
```

## Related

- Shared Buzz mirror (unchanged by this site): [`../../README.md`](../../README.md)
- Production runbook (felg / original): [`../../../docs/PRJ-432.2-buzz-deployment.md`](../../../docs/PRJ-432.2-buzz-deployment.md)
- This instance owns its own `scripts/bootstrap-host-env.sh` and `scripts/enable-pairing-relay.sh` copies under `/opt/dev-weown-buzz` paths — shared `buzz-docker/scripts/*` are not modified.
