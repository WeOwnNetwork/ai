#!/usr/bin/env bash
# lint-site-conf.sh — reject secret-shaped keys in site.conf files
#
# Usage:
#   ./scripts/lint-site-conf.sh sites/<domain>/site.conf
#   ./scripts/lint-site-conf.sh  # checks all site.conf files in the repo
#
# site.conf must contain ONLY non-secret identifiers (project IDs, env slugs).
# Secrets belong in Infisical, not in git. This script catches accidental
# commits of credentials by rejecting keys that match secret patterns.

set -euo pipefail

FORBIDDEN_PATTERN='(SECRET|PASSWORD|TOKEN|KEY|CREDENTIAL|AUTH|PRIVATE|CERT)'

check_file() {
  local file="$1"
  local violations=0

  while IFS= read -r line; do
    # Skip blank lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Extract the key (everything before =)
    if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)= ]]; then
      local key="${BASH_REMATCH[1]}"

      # Check if key matches forbidden pattern (case-insensitive)
      if echo "$key" | grep -iqE "$FORBIDDEN_PATTERN"; then
        echo "ERROR: $file contains forbidden key: $key" >&2
        echo "       site.conf must not contain secrets (matched: $FORBIDDEN_PATTERN)" >&2
        echo "       Secrets belong in Infisical, not in git." >&2
        violations=$((violations + 1))
      fi
    fi
  done < "$file"

  return $violations
}

# If a file is passed, check it
if [[ $# -eq 1 ]]; then
  if [[ ! -f "$1" ]]; then
    echo "ERROR: file not found: $1" >&2
    exit 1
  fi
  check_file "$1"
  exit $?
fi

# Otherwise, find all site.conf files in the repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

total_violations=0
while IFS= read -r -d '' file; do
  if ! check_file "$file"; then
    total_violations=$((total_violations + 1))
  fi
done < <(find "$REPO_ROOT" -name "site.conf" -type f -print0)

if [[ $total_violations -gt 0 ]]; then
  echo "" >&2
  echo "Found $total_violations site.conf file(s) with violations." >&2
  exit 1
fi

echo "✓ All site.conf files passed lint check"
exit 0
