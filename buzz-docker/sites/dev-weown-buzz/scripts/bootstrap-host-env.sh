#!/usr/bin/env bash
# Generate a production .env on the droplet. Secrets stay on the host —
# never printed. Idempotent if .env already exists.
#
# Usage (on droplet):
#   BUZZ_DOMAIN=dev.weown.buzz \
#   BUZZ_IMAGE=ghcr.io/block/buzz@sha256:<DIGEST> \
#     ./bootstrap-host-env.sh /opt/dev-weown-buzz/buzz/deploy/compose
set -euo pipefail

COMPOSE_DIR="${1:-/opt/dev-weown-buzz/buzz/deploy/compose}"
DOMAIN="${BUZZ_DOMAIN:-dev.weown.buzz}"

: "${BUZZ_IMAGE:?Set BUZZ_IMAGE to an immutable digest or release tag (never :main/:latest)}"

# Reject floating tags (§3.8 / §3.13).
case "$BUZZ_IMAGE" in
  *:main|*:latest|*/*:main|*/*:latest)
    echo "ERROR: BUZZ_IMAGE must not use floating :main or :latest — got: $BUZZ_IMAGE" >&2
    echo "Use a digest (ghcr.io/block/buzz@sha256:…) or a pinned release/sha tag." >&2
    exit 1
    ;;
esac

if [[ ! -d "$COMPOSE_DIR" ]]; then
  echo "ERROR: compose dir missing: $COMPOSE_DIR" >&2
  exit 1
fi

if [[ -f "$COMPOSE_DIR/.env" ]]; then
  echo "=== .env already exists; leaving secrets untouched ==="
  grep -E "^(BUZZ_DOMAIN|RELAY_URL|BUZZ_IMAGE|BUZZ_AUTO_MIGRATE|RELAY_OWNER_PUBKEY)=" "$COMPOSE_DIR/.env" || true
  exit 0
fi

# Local venv — do not mutate the host Python with --break-system-packages.
VENV_DIR="$COMPOSE_DIR/.buzz-bootstrap-venv"
python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
pip install -q --upgrade pip
pip install -q coincurve

export COMPOSE_DIR DOMAIN BUZZ_IMAGE
python <<'PY'
from coincurve import PrivateKey
import secrets, pathlib, os

def bip340_keypair():
    sk = PrivateKey()
    pub = sk.public_key.format(compressed=True)
    if pub[0] == 3:
        n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
        sk = PrivateKey((n - int.from_bytes(sk.secret, "big")).to_bytes(32, "big"))
        pub = sk.public_key.format(compressed=True)
    assert pub[0] == 2
    return sk.secret.hex(), pub[1:].hex()

owner_priv, owner_pub = bip340_keypair()
relay_priv, _ = bip340_keypair()

def rand_hex(n=32):
    return secrets.token_hex(n)

def rand_pass(n=24):
    return secrets.token_urlsafe(n)

domain = os.environ["DOMAIN"]
buzz_image = os.environ["BUZZ_IMAGE"]
compose = pathlib.Path(os.environ["COMPOSE_DIR"])

env = f"""# Buzz production — generated on host. DO NOT commit.
BUZZ_IMAGE={buzz_image}
BUZZ_DOMAIN={domain}
RELAY_URL=wss://{domain}
BUZZ_MEDIA_BASE_URL=https://{domain}/media
BUZZ_MEDIA_SERVER_DOMAIN={domain}
BUZZ_CORS_ORIGINS=https://{domain}

BUZZ_REQUIRE_AUTH_TOKEN=true
BUZZ_REQUIRE_RELAY_MEMBERSHIP=true
BUZZ_ALLOW_NIP_OA_AUTH=true
BUZZ_AUTO_MIGRATE=true
BUZZ_GIT_CONFORMANCE_PROBE=true
RUST_LOG=buzz_relay=info,buzz_db=info,buzz_auth=info,buzz_pubsub=info,tower_http=info

RELAY_OWNER_PUBKEY={owner_pub}
BUZZ_RELAY_PRIVATE_KEY={relay_priv}
BUZZ_GIT_HOOK_HMAC_SECRET={rand_hex(32)}
POSTGRES_DB=buzz
POSTGRES_USER=buzz
POSTGRES_PASSWORD={rand_pass(24)}
REDIS_PASSWORD={rand_pass(24)}
BUZZ_S3_ACCESS_KEY={rand_pass(16)}
BUZZ_S3_SECRET_KEY={rand_pass(32)}
BUZZ_S3_BUCKET=buzz-media
BUZZ_S3_ADDRESSING_STYLE=path

BUZZ_HTTP_PORT=3000
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443
"""

env_path = compose / ".env"
env_path.write_text(env)
env_path.chmod(0o600)

owner_path = pathlib.Path("/root/buzz-owner-keypair.txt")
owner_path.write_text(
    "# Owner Nostr keypair for "
    + domain
    + "\n"
    "# Retrieve ONLY via SSH as root. Import private key into Buzz desktop as relay owner.\n"
    f"RELAY_OWNER_PUBKEY={owner_pub}\n"
    f"RELAY_OWNER_PRIVATE_KEY={owner_priv}\n"
)
owner_path.chmod(0o600)

pub_path = pathlib.Path("/opt/dev-weown-buzz/OWNER_PUBKEY.txt")
pub_path.parent.mkdir(parents=True, exist_ok=True)
pub_path.write_text(owner_pub + "\n")
pub_path.chmod(0o644)

print("OWNER_PUBKEY=" + owner_pub)
print("ENV_WRITTEN=" + str(env_path))
print("BUZZ_IMAGE=" + buzz_image)
print("OWNER_KEY_FILE=/root/buzz-owner-keypair.txt")
PY

deactivate || true

if grep -Eq "CHANGE_ME|:(main|latest)([[:space:]]|$)" "$COMPOSE_DIR/.env"; then
  echo "ERROR: .env still contains CHANGE_ME or floating :main/:latest" >&2
  exit 1
fi

echo "=== public config ==="
grep -E "^(BUZZ_DOMAIN|RELAY_URL|BUZZ_IMAGE|BUZZ_AUTO_MIGRATE|RELAY_OWNER_PUBKEY)=" "$COMPOSE_DIR/.env"
ls -la "$COMPOSE_DIR/.env" /root/buzz-owner-keypair.txt /opt/dev-weown-buzz/OWNER_PUBKEY.txt
