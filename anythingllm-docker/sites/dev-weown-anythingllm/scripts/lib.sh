#!/usr/bin/env bash
# dev-weown-anythingllm-anythingllm — shared config reader
# Safe loader for site.conf. Sources ONLY uppercase KEY=value lines.
# Rejects anything that could execute arbitrary code.
#
# Usage (from any script in scripts/):
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib.sh"
#   load_site_conf "$(dirname "$SCRIPT_DIR")/site.conf"

load_site_conf() {
  local conf="$1"
  [[ -f "$conf" ]] || return 0

  while IFS= read -r line; do
    # Skip blank lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Strip inline comments (after #)
    line="${line%%#*}"

    # Trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Only accept UPPER_CASE=value (no spaces, no special chars in key)
    if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"

      # Strip surrounding quotes from value (single or double)
      if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi

      # Export the variable (env vars take precedence — don't override if already set)
      if [[ -z "${!key:-}" ]]; then
        export "$key=$value"
      fi
    fi
  done < "$conf"
}
