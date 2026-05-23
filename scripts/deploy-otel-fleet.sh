#!/usr/bin/env bash
# deploy-otel-fleet.sh — deploy the OTel agent to one or many WeOwn droplets.
# Telemetry ships to SigNoz Cloud (Yonks' managed account); OTEL_URL + OTEL_KEY
# are fetched fresh at every `docker compose up` via `infisical run`, so
# secrets are NEVER stored on disk.
#
# Prerequisite per host: run scripts/bootstrap-otel-agent.sh ONCE on that
# host to install the Infisical CLI and the Machine Identity auth file at
# /opt/otel-agent/.infisical-auth.env (0600 root). This script will refuse
# to deploy to a host that has not been bootstrapped.
#
# Target selection (pick one):
#   --droplet <name>   Single DO droplet by name (e.g. burnedout-xyz)
#   --tag <tag>        All DO droplets with this tag (e.g. weown-ai)
#   --host <user@ip>   Direct SSH target
#
# Options:
#   --dir <path>             OTel agent install dir on the droplet
#                            (default: /opt/otel-agent, burnedout-xyz uses
#                             /root/observability/otel-agent)
#   --env-slug <slug>        Infisical env slug override. If omitted, uses the
#                            value recorded in <dir>/.infisical-auth.env by
#                            bootstrap-otel-agent.sh (typically "dev").
#   --environment <env>      deployment.environment resource attr (default: production)
#   --namespace <ns>         service.namespace resource attr (default: weown-ai)
#   --dry-run                Print actions without executing
#   -h, --help               Show this help
#
# Examples:
#   # burnedout-xyz at the legacy Gemini path
#   ./scripts/deploy-otel-fleet.sh --droplet burnedout-xyz \
#       --dir /root/observability/otel-agent
#
#   # Future fleet roll-out at the standard /opt path
#   ./scripts/deploy-otel-fleet.sh --tag weown-ai
#   ./scripts/deploy-otel-fleet.sh --host root@198.51.100.42
#
# Compliance: NIST DE.CM, CIS 8.5, ISO A.8.15

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}WARN:${NC} $*"; }
die()   { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: deploy-otel-fleet.sh (--droplet <name> | --tag <tag> | --host <user@ip>) [options]

Target (pick one):
  --droplet <name>          Single DO droplet by name (requires doctl)
  --tag <tag>               All DO droplets matching tag (requires doctl)
  --host <user@ip>          Direct SSH target (no doctl needed)

Options:
  --dir <path>              OTel agent install dir on the droplet
                            (default: /opt/otel-agent)
  --env-slug <slug>         Override Infisical env slug. If omitted, uses the
                            slug recorded by bootstrap (typically "dev").
  --environment <env>       deployment.environment attr (default: production)
  --namespace <ns>          service.namespace attr (default: weown-ai)
  --dry-run                 Print actions, do not execute
  -h, --help                Show this help

Prerequisite per host:
  ./scripts/bootstrap-otel-agent.sh  (once per droplet, before first deploy)

Examples:
  # burnedout-xyz at the legacy Gemini path
  ./scripts/deploy-otel-fleet.sh --droplet burnedout-xyz \
      --dir /root/observability/otel-agent

  ./scripts/deploy-otel-fleet.sh --tag weown-ai --environment staging
EOF
  exit "${1:-0}"
}

# ── parse args ────────────────────────────────────────────────────────────────
DROPLET=""
TAG=""
HOST=""
OTEL_AGENT_DIR="/opt/otel-agent"
ENV_SLUG_OVERRIDE=""          # empty => use slug from auth file
DEPLOY_ENVIRONMENT="production"
SERVICE_NAMESPACE="weown-ai"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --droplet)     DROPLET="${2:?--droplet requires a name}"; shift 2 ;;
    --tag)         TAG="${2:?--tag requires a tag name}"; shift 2 ;;
    --host)        HOST="${2:?--host requires user@ip}"; shift 2 ;;
    --dir)         OTEL_AGENT_DIR="${2:?--dir requires a path}"; shift 2 ;;
    --env-slug)    ENV_SLUG_OVERRIDE="${2:?--env-slug requires a slug}"; shift 2 ;;
    --environment) DEPLOY_ENVIRONMENT="${2:?--environment requires a value}"; shift 2 ;;
    --namespace)   SERVICE_NAMESPACE="${2:?--namespace requires a value}"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     usage 0 ;;
    *)             die "Unknown argument: $1 (run --help)" ;;
  esac
done

[[ -z "$DROPLET" && -z "$TAG" && -z "$HOST" ]] && usage 1
[[ "$OTEL_AGENT_DIR" = /* ]] || die "--dir must be an absolute path, got: $OTEL_AGENT_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OTEL_DIR="$SCRIPT_DIR/../otel-agent"
[[ -f "$OTEL_DIR/compose.yaml" ]] || die "otel-agent/compose.yaml not found at $OTEL_DIR"
[[ -f "$OTEL_DIR/config.yaml"  ]] || die "otel-agent/config.yaml not found at $OTEL_DIR"

# ── resolve targets ───────────────────────────────────────────────────────────
declare -a TARGETS=()
declare -A LABEL_BY_TARGET=()

if [[ -n "$HOST" ]]; then
  TARGETS=("$HOST")
  LABEL_BY_TARGET["$HOST"]="$HOST"
elif [[ -n "$DROPLET" || -n "$TAG" ]]; then
  command -v doctl >/dev/null || die "doctl not installed (needed for --droplet/--tag). brew install doctl"
  doctl account get >/dev/null 2>&1 || die "doctl not authenticated. Run: doctl auth init"

  if [[ -n "$DROPLET" ]]; then
    ip=$(doctl compute droplet list --format Name,PublicIPv4 --no-header \
      | awk -v d="$DROPLET" '$1 == d { print $2; exit }')
    [[ -z "$ip" ]] && die "Droplet '$DROPLET' not found in DigitalOcean account"
    target="root@${ip}"
    TARGETS=("$target")
    LABEL_BY_TARGET["$target"]="$DROPLET ($ip)"
  fi

  if [[ -n "$TAG" ]]; then
    while IFS=$'\t' read -r name ip; do
      [[ -z "$ip" ]] && continue
      target="root@${ip}"
      TARGETS+=("$target")
      LABEL_BY_TARGET["$target"]="$name ($ip)"
    done < <(doctl compute droplet list --tag-name "$TAG" \
                --format Name,PublicIPv4 --no-header \
              | awk 'NF >= 2 {print $1 "\t" $2}')
    [[ ${#TARGETS[@]} -eq 0 ]] && die "No droplets found with tag: $TAG"
  fi
fi

# ── deploy function ───────────────────────────────────────────────────────────
deploy_one() {
  local target="$1"
  local label="${LABEL_BY_TARGET[$target]:-$target}"
  echo -e "\n${BOLD}── $label ──${NC}"
  echo "    dir:           $OTEL_AGENT_DIR"
  echo "    env-slug:      ${ENV_SLUG_OVERRIDE:-<from auth file>}"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "[dry-run] would scp compose.yaml + config.yaml to ${target}:${OTEL_AGENT_DIR}/"
    info "[dry-run] would 'infisical run -- docker compose up -d' on $target"
    return 0
  fi

  # Refuse to deploy to a host that has not been bootstrapped
  if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes "$target" \
        "[ -f '${OTEL_AGENT_DIR}/.infisical-auth.env' ]" 2>/dev/null; then
    warn "$label has not been bootstrapped at $OTEL_AGENT_DIR — run scripts/bootstrap-otel-agent.sh first"
    return 1
  fi

  # Upload compose.yaml + config.yaml
  scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 -q \
    "$OTEL_DIR/compose.yaml" "$OTEL_DIR/config.yaml" \
    "${target}:${OTEL_AGENT_DIR}/"

  # Start (or reconcile) the stack via infisical run.
  # We forward our local DEPLOY_ENVIRONMENT / SERVICE_NAMESPACE / OTEL_AGENT_DIR
  # / ENV_SLUG_OVERRIDE via inline env vars to the remote bash session.
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes \
      "$target" \
      "DEPLOY_ENVIRONMENT='${DEPLOY_ENVIRONMENT}' \
       SERVICE_NAMESPACE='${SERVICE_NAMESPACE}' \
       OTEL_AGENT_DIR='${OTEL_AGENT_DIR}' \
       ENV_SLUG_OVERRIDE='${ENV_SLUG_OVERRIDE}' \
       bash -s" <<'REMOTE_EOF'
set -euo pipefail
set -a
# shellcheck disable=SC1091
source "${OTEL_AGENT_DIR}/.infisical-auth.env"
set +a

# Resolve effective env slug: command-line override beats the auth-file value
# (which is what bootstrap-otel-agent.sh recorded). Default to "dev".
EFFECTIVE_ENV="${ENV_SLUG_OVERRIDE:-${INFISICAL_ENV_SLUG:-dev}}"

# Machine Identity auth: capture the short-lived access token and pass it to
# `infisical run`. Discarding login stdout (>/dev/null) leaves no session for
# run to use — see https://infisical.com/docs/cli/commands/run#infisical_token
export INFISICAL_TOKEN
INFISICAL_TOKEN="$(infisical login --method=universal-auth \
  --client-id="$INFISICAL_CLIENT_ID" \
  --client-secret="$INFISICAL_CLIENT_SECRET" \
  --silent --plain)"

cd "$OTEL_AGENT_DIR"

# Pull image quietly
docker compose pull --quiet otel-agent >/dev/null 2>&1 || true

# Start with secrets injected fresh at runtime.
# Wrap compose in bash so we can normalize OTEL_URL before the collector sees it.
# Infisical may store the host as "ingest.us2.signoz.cloud:443" without a scheme;
# otlphttp requires https:// or http:// or it errors with "unsupported protocol scheme".
HOSTNAME="$(hostname)" \
DEPLOY_ENVIRONMENT="${DEPLOY_ENVIRONMENT:-production}" \
SERVICE_NAMESPACE="${SERVICE_NAMESPACE:-weown-ai}" \
infisical run \
  --projectId="$INFISICAL_PROJECT_ID" \
  --env="$EFFECTIVE_ENV" \
  -- bash -c 'set -euo pipefail
    case "${OTEL_URL:-}" in
      http://*|https://*) ;;
      "") echo "ERROR: OTEL_URL is empty"; exit 1 ;;
      *) export OTEL_URL="https://${OTEL_URL}" ;;
    esac
    cd "$OTEL_AGENT_DIR"
    exec docker compose up -d --force-recreate --remove-orphans'

# Host-side health probe (network_mode: host binds 127.0.0.1:13133 on the droplet).
# Prefer curl — wget is not always installed on minimal DO images.
health_ok() {
  curl -sf http://127.0.0.1:13133/health >/dev/null 2>&1 \
    || wget -q --spider http://127.0.0.1:13133/health 2>/dev/null
}

# Give the collector up to 120s (filelog receivers can be slow on busy hosts).
for i in $(seq 1 24); do
  if health_ok; then
    echo "  OK: otel-agent healthy on $(hostname) (env=$EFFECTIVE_ENV)"
    exit 0
  fi
  # If the container exited, no point waiting the full 120s.
  if ! docker ps --filter name=^otel-agent$ --filter status=running -q | grep -q .; then
    echo "  ERROR: otel-agent container is not running"
    docker ps -a --filter name=otel-agent --format '  status: {{.Status}}'
    echo "  --- docker logs otel-agent (last 30 lines) ---"
    docker logs otel-agent 2>&1 | tail -30
    exit 2
  fi
  sleep 5
done
echo "  WARN: otel-agent did not become healthy within 120s"
docker ps -a --filter name=otel-agent --format '  status: {{.Status}}'
echo "  --- docker logs otel-agent (last 30 lines) ---"
docker logs otel-agent 2>&1 | tail -30
exit 2
REMOTE_EOF
}

# ── run ───────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Deploying OTel agent to ${#TARGETS[@]} target(s)${NC}"
echo "    deployment.environment = $DEPLOY_ENVIRONMENT"
echo "    service.namespace      = $SERVICE_NAMESPACE"

SUCCESS=0
FAILED=0
for target in "${TARGETS[@]}"; do
  if deploy_one "$target"; then
    ((SUCCESS++)) || true
  else
    ((FAILED++)) || true
  fi
done

echo ""
echo -e "${BOLD}Summary:${NC}"
info "Deployed: $SUCCESS / ${#TARGETS[@]}"
[[ $FAILED -gt 0 ]] && warn "Failed:   $FAILED"
echo ""
info "Verify in SigNoz Cloud UI: Infrastructure → Hosts (filter by host.name)"
info "Logs:                       Logs Explorer (filter by deployment.environment=$DEPLOY_ENVIRONMENT)"
