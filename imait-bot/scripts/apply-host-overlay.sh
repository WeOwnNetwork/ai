#!/usr/bin/env bash
# Non-secret host overlay: home channel, watch list, WS transport.
# Never prints .env values. Never recreates containers. Never touches other stacks.
set -euo pipefail

ENV_FILE="${1:-/opt/imait-bot/.env}"
CONFIG_FILE="${2:-/opt/imait-bot/config.yaml}"
CHANNEL_ID="${BUZZ_HOME_CHANNEL_VALUE:-}"
CHANNEL_NAME="${BUZZ_HOME_CHANNEL_NAME_VALUE:-}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi
if [[ -z "$CHANNEL_ID" ]]; then
  echo "Set BUZZ_HOME_CHANNEL_VALUE to the home channel UUID (host overlay, not git)." >&2
  exit 1
fi

upsert() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    awk -v k="$key" -v v="$value" '
      $1 ~ "^"k"=" { print k"="v; next }
      { print }
    ' "$ENV_FILE" > "${ENV_FILE}.tmp"
    mv "${ENV_FILE}.tmp" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

upsert BUZZ_HOME_CHANNEL "$CHANNEL_ID"
upsert BUZZ_CHANNELS "$CHANNEL_ID"
upsert BUZZ_HOME_CHANNEL_NAME "$CHANNEL_NAME"
upsert BUZZ_TRANSPORT auto
# Hermes uid must read the bind-mount.
chmod 644 "$ENV_FILE"

if [[ -f "$CONFIG_FILE" ]]; then
  python3 - "$CONFIG_FILE" "$CHANNEL_ID" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
channel = sys.argv[2]
lines = path.read_text().splitlines(keepends=True)
has_home = any("home_channel:" in line for line in lines)
out = []
inserted = False
for line in lines:
    if "home_channel:" in line:
        if inserted:
            continue
        indent = line[: len(line) - len(line.lstrip())]
        out.append(f"{indent}home_channel: {channel}\n")
        inserted = True
        continue
    out.append(line)
    if (not has_home) and (not inserted) and line.lstrip().startswith("channels:"):
        indent = line[: len(line) - len(line.lstrip())]
        out.append(f"{indent}home_channel: {channel}\n")
        inserted = True
if not inserted:
    sys.exit("could not insert home_channel into config.yaml")
path.write_text("".join(out))
print("host config.yaml home_channel set")
PY
fi

echo "Host overlay applied (channel id not a secret; .env secrets untouched)."
echo "Next: docker compose up -d --no-deps --build imait-bot"
