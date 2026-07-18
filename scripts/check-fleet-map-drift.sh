#!/usr/bin/env bash
# check-fleet-map-drift.sh — fail when the DO `anythingllm` droplet tag drifts
# from the documented fleet manifest (docs/runbooks/anythingllm-fleet.txt).
#
# Guards against the "tag covers 12 droplets, docs list 3" class of surprise:
# tag-wide operations (manage-droplets.sh exec/deploy) hit every ACTIVE tagged
# box, so undocumented members are an operational hazard.
#
# Usage:
#   ./scripts/check-fleet-map-drift.sh [--tag anythingllm] [--manifest <path>]
#
# Exit codes:
#   0 — no drift (or doctl unavailable/unauthenticated: SKIP with notice, so
#       public CI without DO credentials does not fail)
#   1 — drift detected (undocumented live droplet, or documented droplet gone)
#   2 — usage / manifest missing

set -euo pipefail

TAG="anythingllm"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/docs/runbooks/anythingllm-fleet.txt"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --manifest) MANIFEST="$2"; shift 2 ;;
    *) echo "Usage: $0 [--tag <tag>] [--manifest <path>]" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 2
fi

if ! command -v doctl >/dev/null 2>&1; then
  echo "SKIP: doctl not installed — drift check needs DO API access."
  exit 0
fi

if ! LIVE_RAW=$(doctl compute droplet list --tag-name "$TAG" --format Name --no-header 2>&1); then
  echo "SKIP: doctl not authenticated or DO API unreachable — drift check skipped."
  echo "      ($(echo "$LIVE_RAW" | head -1))"
  exit 0
fi

live=$(echo "$LIVE_RAW" | sed '/^[[:space:]]*$/d' | sort -u)
documented=$(grep -v '^[[:space:]]*#' "$MANIFEST" | sed '/^[[:space:]]*$/d' | sort -u)

undocumented=$(comm -23 <(echo "$live") <(echo "$documented"))
missing=$(comm -13 <(echo "$live") <(echo "$documented"))

status=0
if [[ -n "$undocumented" ]]; then
  echo "DRIFT: live droplets tagged '$TAG' but NOT in the fleet manifest:"
  echo "$undocumented" | sed 's/^/  + /'
  echo "  → add them to $MANIFEST (and the runbook fleet map) or fix the tag."
  status=1
fi
if [[ -n "$missing" ]]; then
  echo "DRIFT: manifest entries with no live droplet tagged '$TAG':"
  echo "$missing" | sed 's/^/  - /'
  echo "  → remove them from $MANIFEST (decommissioned?) or restore the tag."
  status=1
fi

if [[ $status -eq 0 ]]; then
  echo "OK: tag '$TAG' matches the fleet manifest ($(echo "$documented" | wc -l | tr -d ' ') droplets)."
fi
exit $status
