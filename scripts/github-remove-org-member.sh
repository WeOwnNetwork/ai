#!/usr/bin/env bash
# GitHub Organization Member Removal Script
# Removes a user from all WeOwn ecosystem GitHub organizations
#
# Usage: ./github-remove-org-member.sh <username> [--dry-run]
#
# Requires: gh (GitHub CLI) authenticated with org:admin scope
# Or: GITHUB_TOKEN env var with admin:org scope
#
# Organizations (13 total):
#   BurnedOutMedia, CCCbotNet, jAIMSnet, pTokenAssets, SolarEVcoop,
#   Web3FreedomClub, WeOwnAcademy, WeOwnCash, WeOwnDev, WeOwnLabs,
#   WeOwnNet, WeOwnNetwork, REtokenDAO

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

ORGANIZATIONS=(
  "BurnedOutMedia"
  "CCCbotNet"
  "jAIMSnet"
  "pTokenAssets"
  "SolarEVcoop"
  "Web3FreedomClub"
  "WeOwnAcademy"
  "WeOwnCash"
  "WeOwnDev"
  "WeOwnLabs"
  "WeOwnNet"
  "WeOwnNetwork"
  "REtokenDAO"
)

# =============================================================================
# Argument Parsing
# =============================================================================

USERNAME=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 <github-username> [--dry-run]"
      echo ""
      echo "Removes a GitHub user from all 13 WeOwn ecosystem organizations."
      echo ""
      echo "Arguments:"
      echo "  <github-username>  The GitHub username to remove"
      echo "  --dry-run          Show what would be done without making changes"
      echo ""
      echo "Environment:"
      echo "  GITHUB_TOKEN       GitHub personal access token with admin:org scope"
      echo "                     (alternative to 'gh' CLI authentication)"
      echo ""
      echo "Examples:"
      echo "  $0 johndoe"
      echo "  $0 johndoe --dry-run"
      exit 0
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 1
      ;;
    *)
      if [[ -z "$USERNAME" ]]; then
        USERNAME="$1"
      else
        echo "Error: Unexpected argument $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$USERNAME" ]]; then
  echo "Error: GitHub username required" >&2
  echo "Usage: $0 <github-username> [--dry-run]" >&2
  exit 1
fi

# =============================================================================
# Authentication Detection
# =============================================================================

USE_GH_CLI=false

if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  USE_GH_CLI=true
  echo "==> Using GitHub CLI (gh) for API calls"
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  USE_GH_CLI=false
  echo "==> Using curl with GITHUB_TOKEN environment variable"
else
  echo "Error: No GitHub authentication found." >&2
  echo "  Option 1: Install and authenticate 'gh' CLI" >&2
  echo "  Option 2: Set GITHUB_TOKEN environment variable" >&2
  exit 1
fi

# =============================================================================
# Removal Logic
# =============================================================================

remove_from_org() {
  local org="$1"
  local user="$2"

  if [[ "$DRY_RUN" == true ]]; then
    echo "  [DRY-RUN] Would remove $user from $org"
    return 0
  fi

  if [[ "$USE_GH_CLI" == true ]]; then
    # Check if user is actually a member first
    if ! gh api "orgs/$org/members/$user" &>/dev/null; then
      echo "  ⚠️  $user is not a member of $org (skipping)"
      return 0
    fi

    if gh api --method DELETE "orgs/$org/members/$user" &>/dev/null; then
      echo "  ✅ Removed $user from $org"
      return 0
    else
      echo "  ❌ Failed to remove $user from $org"
      return 1
    fi
  else
    # curl fallback
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/orgs/$org/members/$user" 2>/dev/null || echo "000")

    if [[ "$response" == "404" ]]; then
      echo "  ⚠️  $user is not a member of $org (skipping)"
      return 0
    fi

    response=$(curl -s -o /dev/null -w "%{http_code}" \
      -X DELETE \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/orgs/$org/members/$user" 2>/dev/null || echo "000")

    if [[ "$response" == "204" || "$response" == "404" ]]; then
      echo "  ✅ Removed $user from $org"
      return 0
    else
      echo "  ❌ Failed to remove $user from $org (HTTP $response)"
      return 1
    fi
  fi
}

# =============================================================================
# Main Execution
# =============================================================================

echo ""
echo "==================================================================="
if [[ "$DRY_RUN" == true ]]; then
  echo "  DRY RUN MODE — No changes will be made"
fi
echo "  Target User: $USERNAME"
echo "  Organizations: ${#ORGANIZATIONS[@]}"
echo "==================================================================="
echo ""

SUCCESS=0
FAILED=0

for org in "${ORGANIZATIONS[@]}"; do
  echo "→ Processing $org..."
  if remove_from_org "$org" "$USERNAME"; then
    ((SUCCESS++))
  else
    ((FAILED++))
  fi
done

echo ""
echo "==================================================================="
echo "  Removal Complete"
echo "==================================================================="
echo "  Successful: $SUCCESS"
echo "  Failed:     $FAILED"
echo "  Total:      ${#ORGANIZATIONS[@]}"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "  This was a dry run. No actual changes were made."
  echo "  Remove --dry-run to execute for real."
  echo ""
fi

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi

exit 0
