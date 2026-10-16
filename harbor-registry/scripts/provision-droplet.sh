#!/usr/bin/env bash
# Create the registry droplet if it does not already exist.
# Idempotent: a second run prints the existing public IPv4 and does not resize
# or rebuild. doctl must already be authenticated to the We Own Labs team.
# A context from another team will create a second droplet there. Does not
# read or print tokens.
#
# Usage: ./scripts/provision-droplet.sh
# Prints a final line: PUBLIC_IP=<ipv4>
set -euo pipefail

REGION="${REGION:-atl1}"
# v5 Shared, 2 vCPU, 4 GB RAM, 80 GB disk. Available in atl1.
SIZE="${SIZE:-s5-2vcpu-4gb-80gb}"
IMAGE="${IMAGE:-ubuntu-24-04-x64}"
NAME="${NAME:-registry-weown-tools}"
TAG="${TAG:-harbor}"
FW_NAME="${FW_NAME:-harbor-registry-fw}"

if ! command -v doctl >/dev/null 2>&1; then
  echo "doctl is required and must already be authenticated" >&2
  exit 1
fi

existing_id=$(doctl compute droplet list "$NAME" --format ID --no-header 2>/dev/null | tr -d '[:space:]' || true)
if [[ -n "$existing_id" ]]; then
  # Prefer the reserved address. droplet list PublicIPv4 stays the anchor address.
  reserved_ip=$(doctl compute reserved-ip list --format IP,DropletID --no-header \
    | awk -v id="$existing_id" '$2 == id { print $1; exit }')
  if [[ -n "$reserved_ip" ]]; then
    echo "droplet ${NAME} already exists" >&2
    echo "PUBLIC_IP=${reserved_ip}"
    exit 0
  fi
  existing=$(doctl compute droplet list "$NAME" --format PublicIPv4 --no-header | tr -d '[:space:]')
  echo "droplet ${NAME} already exists" >&2
  echo "PUBLIC_IP=${existing}"
  exit 0
fi

mapfile -t key_ids < <(doctl compute ssh-key list --format ID --no-header | tr -d '[:space:]' | sed '/^$/d')
if [[ ${#key_ids[@]} -eq 0 ]]; then
  echo "no SSH keys on the DigitalOcean account; import one before creating the droplet" >&2
  exit 1
fi
keys_csv=$(IFS=,; echo "${key_ids[*]}")

echo "creating ${NAME} in ${REGION} size ${SIZE} image ${IMAGE}" >&2
doctl compute droplet create "$NAME" \
  --region "$REGION" \
  --size "$SIZE" \
  --image "$IMAGE" \
  --ssh-keys "$keys_csv" \
  --tag-names "$TAG" \
  --enable-monitoring \
  --enable-ipv6 \
  --wait >&2

drop_id=$(doctl compute droplet list "$NAME" --format ID --no-header | tr -d '[:space:]')
ip=$(doctl compute droplet list "$NAME" --format PublicIPv4 --no-header | tr -d '[:space:]')
if [[ -z "$drop_id" || -z "$ip" ]]; then
  echo "droplet create finished but id or IPv4 was empty" >&2
  exit 1
fi

# Anchor DNS to a reserved IP (free while assigned). Assignment replaces the
# ephemeral public IPv4.
if ! doctl compute reserved-ip list --format IP,DropletID,Region --no-header 2>/dev/null \
  | awk -v id="$drop_id" '$2 == id { found=1 } END { exit found ? 0 : 1 }'; then
  echo "reserving an IPv4 in ${REGION}" >&2
  reserved=$(doctl compute reserved-ip create --region "$REGION" --format IP --no-header | tr -d '[:space:]')
  doctl compute reserved-ip-action assign "$reserved" "$drop_id" >&2
  ip="$reserved"
fi

if ! doctl compute firewall list --format Name --no-header | grep -qx "$FW_NAME"; then
  echo "creating firewall ${FW_NAME}" >&2
  doctl compute firewall create \
    --name "$FW_NAME" \
    --droplet-ids "$drop_id" \
    --inbound-rules "protocol:tcp,ports:22,address:0.0.0.0/0 protocol:tcp,ports:22,address:::/0 protocol:tcp,ports:80,address:0.0.0.0/0 protocol:tcp,ports:80,address:::/0 protocol:tcp,ports:443,address:0.0.0.0/0 protocol:tcp,ports:443,address:::/0 protocol:udp,ports:443,address:0.0.0.0/0 protocol:udp,ports:443,address:::/0" \
    --outbound-rules "protocol:tcp,ports:0,address:0.0.0.0/0 protocol:tcp,ports:0,address:::/0 protocol:udp,ports:0,address:0.0.0.0/0 protocol:udp,ports:0,address:::/0 protocol:icmp,address:0.0.0.0/0" \
    >&2
else
  fw_id=$(doctl compute firewall list --format ID,Name --no-header | awk -v n="$FW_NAME" '$2 == n { print $1; exit }')
  doctl compute firewall add-droplets "$fw_id" --droplet-ids "$drop_id" >&2 || true
fi

echo "droplet ${NAME} id ${drop_id} is up" >&2
echo "PUBLIC_IP=${ip}"
