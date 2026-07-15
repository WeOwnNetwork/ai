#!/usr/bin/env bash
# bootstrap-otel-agent.sh — one-time per-droplet bootstrap for the OTel fleet agent
#
# Installs the Infisical CLI (if missing) and writes <dir>/.infisical-auth.env
# (root 0600) with the Machine Identity credentials for the Infisical "otel" project.
# After bootstrap, scripts/deploy-otel-fleet.sh or otel-agent/deploy.yml can start
# the agent — OTEL_URL + OTEL_KEY get fetched fresh at every `docker compose up`
# via `infisical run`, so secrets are NEVER stored on disk.
#
# Bootstrap target selection — choose ONE:
#   --droplet <name>     Single droplet by DigitalOcean name (e.g. burnedout-xyz)
#   --tag <tag-name>     All droplets matching a DigitalOcean tag (e.g. weown-ai)
#   --host <user@ip>     Direct SSH target (skips doctl)
#
# Path / env overrides (optional):
#   --dir <path>         Install dir on the droplet (default /opt/otel-agent).
#                        For burnedout-xyz use /root/observability/otel-agent.
#   --env-slug <slug>    Infisical environment slug to record (default dev).
#                        Stored in the auth file; consumed by deploy scripts so
#                        you do not have to repeat --env-slug on every deploy.
#
# Infisical Machine Identity values are read from THESE env vars on YOUR local
# machine (NEVER passed on the command line, NEVER written to repo):
#   INFISICAL_OTEL_PROJECT_ID    — projectId of the Infisical "otel" project
#   INFISICAL_OTEL_CLIENT_ID     — Machine Identity Client ID with read access
#   INFISICAL_OTEL_CLIENT_SECRET — Machine Identity Client Secret (shown once at creation)
#
# Example (burnedout-xyz, legacy Gemini path, Development env):
#   export INFISICAL_OTEL_PROJECT_ID="<project-id>"
#   export INFISICAL_OTEL_CLIENT_ID="<client-id>"
#   export INFISICAL_OTEL_CLIENT_SECRET="<client-secret>"
#   ./bootstrap-otel-agent.sh \
#     --droplet burnedout-xyz \
#     --dir /root/observability/otel-agent \
#     --env-slug dev
#
# Compliance: NIST PR.DS, CIS 3.11, ISO A.5.16

set -euo pipefail

# ── colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}WARN:${NC} $*"; }
die()   { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }

# ── usage ─────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
Usage: bootstrap-otel-agent.sh (--droplet <name> | --tag <tag> | --host <user@ip>) [options]

Target (pick one):
  --droplet <name>          Single DO droplet by name (requires doctl)
  --tag <tag>               All DO droplets matching tag (requires doctl)
  --host <user@ip>          Direct SSH target (no doctl needed)

Options:
  --dir <path>              Install dir on the droplet (default: /opt/otel-agent)
                            burnedout-xyz uses /root/observability/otel-agent
  --env-slug <slug>         Infisical env slug to record (default: dev)
  --dry-run                 Print actions without executing
  -h, --help                Show this help

Required env on YOUR machine (NEVER on remote, NEVER in repo):
  INFISICAL_OTEL_PROJECT_ID
  INFISICAL_OTEL_CLIENT_ID
  INFISICAL_OTEL_CLIENT_SECRET

Examples:
  ./bootstrap-otel-agent.sh --droplet burnedout-xyz \
      --dir /root/observability/otel-agent --env-slug dev
  ./bootstrap-otel-agent.sh --tag weown-ai
  ./bootstrap-otel-agent.sh --host root@198.51.100.42
EOF
  exit "${1:-0}"
}

# ── parse args ────────────────────────────────────────────────────────────────
DROPLET=""
TAG=""
HOST=""
OTEL_AGENT_DIR="/opt/otel-agent"
INFISICAL_ENV_SLUG="dev"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --droplet)   DROPLET="${2:?--droplet requires a name}"; shift 2 ;;
    --tag)       TAG="${2:?--tag requires a tag name}"; shift 2 ;;
    --host)      HOST="${2:?--host requires user@ip}"; shift 2 ;;
    --dir)       OTEL_AGENT_DIR="${2:?--dir requires a path}"; shift 2 ;;
    --env-slug)  INFISICAL_ENV_SLUG="${2:?--env-slug requires a slug}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage 0 ;;
    *)           die "Unknown argument: $1 (run --help)" ;;
  esac
done

[[ -z "$DROPLET" && -z "$TAG" && -z "$HOST" ]] && usage 1

# Basic path sanity — must be absolute
[[ "$OTEL_AGENT_DIR" = /* ]] || die "--dir must be an absolute path, got: $OTEL_AGENT_DIR"

# ── env validation ────────────────────────────────────────────────────────────
: "${INFISICAL_OTEL_PROJECT_ID:?Set INFISICAL_OTEL_PROJECT_ID (Infisical otel project ID)}"
: "${INFISICAL_OTEL_CLIENT_ID:?Set INFISICAL_OTEL_CLIENT_ID (Machine Identity client ID)}"
: "${INFISICAL_OTEL_CLIENT_SECRET:?Set INFISICAL_OTEL_CLIENT_SECRET (Machine Identity secret)}"

# ── resolve targets ───────────────────────────────────────────────────────────
declare -a TARGETS=()

if [[ -n "$HOST" ]]; then
  TARGETS=("$HOST")
elif [[ -n "$DROPLET" || -n "$TAG" ]]; then
  command -v doctl >/dev/null || die "doctl not installed (needed for --droplet/--tag). brew install doctl"
  doctl account get >/dev/null 2>&1 || die "doctl not authenticated. Run: doctl auth init"

  if [[ -n "$DROPLET" ]]; then
    ip=$(doctl compute droplet list --format Name,PublicIPv4 --no-header \
      | awk -v d="$DROPLET" '$1 == d { print $2; exit }')
    [[ -z "$ip" ]] && die "Droplet '$DROPLET' not found in DigitalOcean account"
    TARGETS=("root@${ip}")
  fi

  if [[ -n "$TAG" ]]; then
    mapfile -t ips < <(doctl compute droplet list --tag-name "$TAG" \
      --format PublicIPv4 --no-header | grep -v '^$' || true)
    [[ ${#ips[@]} -eq 0 ]] && die "No droplets found with tag: $TAG"
    for ip in "${ips[@]}"; do TARGETS+=("root@${ip}"); done
  fi
fi

[[ ${#TARGETS[@]} -eq 0 ]] && die "No target hosts resolved"

# ── bootstrap function ────────────────────────────────────────────────────────
bootstrap_one() {
  local target="$1"
  echo -e "\n${BOLD}── $target ──${NC}"
  echo "    dir:       $OTEL_AGENT_DIR"
  echo "    env-slug:  $INFISICAL_ENV_SLUG"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "[dry-run] would create $OTEL_AGENT_DIR/.infisical-auth.env on $target"
    return 0
  fi

  # Single SSH session that:
  #   1) installs infisical CLI if missing
  #   2) ensures <OTEL_AGENT_DIR> exists
  #   3) writes .infisical-auth.env atomically with 0600 root:root
  # Secrets are piped to the remote bash via stdin (NOT argv), so they do not
  # appear in the local `ps` listing while the SSH connection is alive.
  # `printf %q` handles quoting for any special characters in the secret values.
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes \
      "$target" 'bash -s' < <(
    printf 'export INFISICAL_OTEL_PROJECT_ID=%q\n' "$INFISICAL_OTEL_PROJECT_ID"
    printf 'export INFISICAL_OTEL_CLIENT_ID=%q\n'  "$INFISICAL_OTEL_CLIENT_ID"
    printf 'export INFISICAL_OTEL_CLIENT_SECRET=%q\n' "$INFISICAL_OTEL_CLIENT_SECRET"
    printf 'export OTEL_AGENT_DIR=%q\n'             "$OTEL_AGENT_DIR"
    printf 'export INFISICAL_ENV_SLUG=%q\n'         "$INFISICAL_ENV_SLUG"
    cat <<'REMOTE_EOF'
set -euo pipefail

# Ensure a CURRENT Infisical CLI is installed.
#
# We use the NEW official Infisical artifacts repo (artifacts-cli.infisical.com),
# per https://infisical.com/docs/cli/overview#installation. The repo this CLI
# previously lived in (dl.cloudsmith.io/.../infisical-cli/) is frozen at v0.38,
# whose session handling is broken on `infisical run` (it prints "session
# expired" right after a successful login). The OLD install-cli.sh from
# infisical.com is also deprecated and pins to the same v0.38.
#
# This block is fully idempotent:
#   * removes the stale Cloudsmith repo + keyring (so apt does not keep v0.38 as
#     a candidate from a second repo)
#   * removes the legacy /usr/local/bin/infisical binary (if a previous run of
#     install-cli.sh left one — it would shadow the apt binary in $PATH)
#   * adds the new artifacts-cli.infisical.com repo
#   * installs / upgrades the package
LEGACY_REPO_LIST="/etc/apt/sources.list.d/infisical-infisical-cli.list"
NEW_REPO_LIST="/etc/apt/sources.list.d/infisical-cli.list"
INSTALL_CLI=0
if ! command -v infisical >/dev/null 2>&1; then
  INSTALL_CLI=1
else
  # Treat anything < v0.100 as "legacy, force upgrade" — the frozen Cloudsmith
  # / install-cli.sh channels max out at v0.38; the new artifacts repo is v0.1xx+.
  CURRENT_VER=$(infisical --version 2>/dev/null | grep -oE "v?[0-9]+\.[0-9]+\.[0-9]+" | head -n1 | tr -d v || echo "0.0.0")
  MAJOR_MINOR=$(echo "$CURRENT_VER" | awk -F. '{printf "%d%03d", $1, $2}')
  if [ "${MAJOR_MINOR:-0}" -lt 100 ]; then
    echo "  detected legacy infisical CLI ($CURRENT_VER); upgrading..."
    INSTALL_CLI=1
  fi
fi
if [ "$INSTALL_CLI" -eq 1 ]; then
  # 1) purge stale Cloudsmith repo (if present) so apt does not pick v0.38 from it
  if [ -f "$LEGACY_REPO_LIST" ] || [ -f "${LEGACY_REPO_LIST}.save" ]; then
    echo "  purging stale Cloudsmith repo (was capped at v0.38)..."
    rm -f "$LEGACY_REPO_LIST" "${LEGACY_REPO_LIST}.save"
    rm -f /usr/share/keyrings/infisical-infisical-cli-archive-keyring.gpg
  fi
  # 2) remove the legacy script's binary (apt won't track it; can shadow new one)
  if [ -f /usr/local/bin/infisical ] || [ -f /usr/bin/infisical ]; then
    # Only remove if dpkg does NOT track the file (i.e. it came from install-cli.sh)
    if ! dpkg -S /usr/bin/infisical >/dev/null 2>&1; then
      rm -f /usr/bin/infisical
    fi
    rm -f /usr/local/bin/infisical
    hash -r 2>/dev/null || true
  fi
  # 3) add new repo + install
  if [ ! -f "$NEW_REPO_LIST" ]; then
    echo "  adding Infisical artifacts apt repo (artifacts-cli.infisical.com)..."
    curl -1sLf "https://artifacts-cli.infisical.com/setup.deb.sh" | bash >/dev/null
  fi
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq infisical >/dev/null
fi
infisical --version >/dev/null || { echo "  ERROR: infisical CLI install failed"; exit 1; }
echo "  infisical CLI: $(infisical --version 2>/dev/null | head -n1)"

# Ensure target dir exists (compose.yaml + config.yaml come later via deploy)
mkdir -p "$OTEL_AGENT_DIR"
chown root:root "$OTEL_AGENT_DIR"
chmod 0755 "$OTEL_AGENT_DIR"

# Write the Machine Identity auth file atomically, 0600 root:root
AUTH_FILE="$OTEL_AGENT_DIR/.infisical-auth.env"
TMP_FILE=$(mktemp "$OTEL_AGENT_DIR/.infisical-auth.env.XXXXXX")
trap 'rm -f "$TMP_FILE"' EXIT
{
  echo "# Infisical Machine Identity for the 'otel' project."
  echo "# Written by bootstrap-otel-agent.sh. DO NOT commit. DO NOT print."
  echo "# Used by docker compose + infisical run to fetch OTEL_URL/OTEL_KEY at runtime."
  echo "INFISICAL_PROJECT_ID=${INFISICAL_OTEL_PROJECT_ID}"
  echo "INFISICAL_CLIENT_ID=${INFISICAL_OTEL_CLIENT_ID}"
  echo "INFISICAL_CLIENT_SECRET=${INFISICAL_OTEL_CLIENT_SECRET}"
  echo "INFISICAL_ENV_SLUG=${INFISICAL_ENV_SLUG}"
} > "$TMP_FILE"
chmod 0600 "$TMP_FILE"
chown root:root "$TMP_FILE"
mv "$TMP_FILE" "$AUTH_FILE"
trap - EXIT

# Sanity check — login AND verify we can read OTEL_URL/OTEL_KEY from this project/env.
# login alone is not enough: `infisical run` needs INFISICAL_TOKEN (see Infisical docs).
export INFISICAL_TOKEN
export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="${INFISICAL_OTEL_CLIENT_ID}"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="${INFISICAL_OTEL_CLIENT_SECRET}"
INFISICAL_TOKEN="$(infisical login --method=universal-auth --silent --plain)" || {
  echo "  ERROR: Infisical login failed with provided Machine Identity credentials"
  exit 1
}
if infisical secrets \
     --projectId="${INFISICAL_OTEL_PROJECT_ID}" \
     --env="${INFISICAL_ENV_SLUG}" \
     --path=/ 2>/dev/null | grep -q 'OTEL_URL'; then
  echo "  OK: Infisical login + secrets fetch succeeded; auth file written to $AUTH_FILE (0600 root)"
else
  echo "  ERROR: login OK but cannot read OTEL_URL from project=${INFISICAL_OTEL_PROJECT_ID} env=${INFISICAL_ENV_SLUG} path=/"
  echo "         Check: secrets exist in Infisical UI, env slug matches --env-slug, identity has project access."
  exit 1
fi
unset INFISICAL_TOKEN
REMOTE_EOF
  )
}

# Resolve the script's own directory so we can call sibling helpers.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Tag a successfully-bootstrapped droplet with "otel" so the DO console
# reflects the credential's presence. See docs/INFRA_BOOTSTRAP_PATTERN.md
# "DO tag taxonomy". On-prem hosts (no matching DO droplet) are skipped silently.
tag_otel_on() {
  local target="$1"
  local ip="${target##*@}"
  local name
  name=$(doctl compute droplet list --format Name,PublicIPv4 --no-header 2>/dev/null \
    | awk -v ip="$ip" '$2 == ip {print $1; exit}')
  if [[ -n "$name" ]]; then
    bash "$SCRIPT_DIR/tag-droplet.sh" "$name" add otel 2>/dev/null || \
      warn "could not tag $name (continuing)"
  fi
}

# ── run ───────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Bootstrapping OTel agent Infisical credentials on ${#TARGETS[@]} host(s)${NC}"

SUCCESS=0
FAILED=0
for target in "${TARGETS[@]}"; do
  if bootstrap_one "$target"; then
    ((SUCCESS++)) || true
    tag_otel_on "$target"
  else
    warn "bootstrap failed on $target"
    ((FAILED++)) || true
  fi
done

echo ""
echo -e "${BOLD}Summary:${NC}"
info "Bootstrapped: $SUCCESS / ${#TARGETS[@]}"
[[ $FAILED -gt 0 ]] && warn "Failed: $FAILED"
echo ""
info "Next step: deploy the agent itself with one of"
if [[ "$OTEL_AGENT_DIR" != "/opt/otel-agent" ]]; then
  echo "    ./scripts/deploy-otel-fleet.sh --droplet <name> --dir $OTEL_AGENT_DIR"
  echo "    ansible-playbook otel-agent/deploy.yml -i 'root@<ip>,' -e otel_agent_dir=$OTEL_AGENT_DIR"
else
  echo "    ./scripts/deploy-otel-fleet.sh --droplet <name>"
  echo "    ansible-playbook otel-agent/deploy.yml -i 'root@<ip>,'"
fi
