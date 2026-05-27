#!/usr/bin/env bash
# tag-droplet.sh — Mutate DO droplet tags from any script or playbook.
#
# Maintains the WeOwn tag taxonomy documented in
# docs/INFRA_BOOTSTRAP_PATTERN.md ("DO tag taxonomy" section):
#
#   - Project tags     — set by terraform at create time (project_name, service
#                        family, "ai", "weown-ai"). Terraform droplet has
#                        `ignore_changes = [tags]` so runtime mutations stick.
#   - Feature tags     — what's actually deployed on this droplet:
#                        otel, searxng-mcp, skinny-backup, etc.
#   - State tags       — what state the droplet is currently in:
#                        commit-<short-sha>   (replaced on every deploy)
#
# Usage:
#   tag-droplet.sh <droplet-name> <action> [args...] [<action2> [args...]] ...
#
# Actions (chainable in one call):
#   add <tag1>[,tag2,...]               Idempotently add tags
#   remove <tag1>[,tag2,...]            Remove tags
#   replace-prefix <prefix> <new-tag>   Remove any tag starting with <prefix>,
#                                       then add <new-tag>. Useful for state
#                                       tags that should have exactly one
#                                       current value (e.g. commit-<sha>).
#   set-commit [<sha>]                  Convenience: replace-prefix commit-
#                                       commit-<sha> (default: git HEAD short).
#   list                                Print current tags, one per line.
#
# Example (from ansible after deploy):
#   scripts/tag-droplet.sh s004-anythingllm \
#     replace-prefix commit- "commit-$(git rev-parse --short HEAD)" \
#     add skinny-backup
#
# Example (from bootstrap-otel-agent.sh):
#   scripts/tag-droplet.sh "$droplet" add otel
#
# Requires: doctl (authenticated) + jq.
# Compliance: NIST CM-8 (system inventory), CIS Controls v8 1.2.

set -euo pipefail

usage() {
  sed -n '/^# Usage:/,/^# Requires:/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

[[ $# -lt 2 ]] && usage 1

command -v doctl >/dev/null || { echo "ERROR: doctl not found (brew install doctl)" >&2; exit 1; }
command -v jq    >/dev/null || { echo "ERROR: jq not found (brew install jq)" >&2; exit 1; }

DROPLET_NAME="$1"
shift

# Resolve droplet name → ID once. Error if zero or multiple matches —
# tagging the wrong droplet is worse than not tagging at all.
matches=$(doctl compute droplet list --format Name,ID --no-header 2>/dev/null \
  | awk -v n="$DROPLET_NAME" '$1 == n {print $2}')
match_count=$(printf '%s\n' "$matches" | grep -c . || true)
if [[ "$match_count" -eq 0 ]]; then
  echo "ERROR: no droplet named '$DROPLET_NAME' in this DO account" >&2
  exit 2
fi
if [[ "$match_count" -gt 1 ]]; then
  echo "ERROR: multiple droplets named '$DROPLET_NAME' (got $match_count) — refusing to tag" >&2
  echo "       resolve by renaming one of the droplets so names are unique" >&2
  exit 2
fi
DROPLET_ID="$matches"

current_tags() {
  doctl compute droplet get "$DROPLET_ID" -o json 2>/dev/null \
    | jq -r '.[0].tags[]?' 2>/dev/null \
    | sort -u
}

tag_add_one() {
  local tag="$1"
  # `doctl compute droplet-action tag` waits idempotently
  doctl compute droplet-action tag --tag-name "$tag" --wait "$DROPLET_ID" >/dev/null 2>&1 \
    || true   # ignore if already tagged (doctl returns non-zero in that case)
}

tag_remove_one() {
  local tag="$1"
  doctl compute droplet-action untag --tag-name "$tag" --wait "$DROPLET_ID" >/dev/null 2>&1 \
    || true   # ignore if tag not present
}

action_add() {
  IFS=',' read -ra tags <<< "$1"
  for t in "${tags[@]}"; do
    t="${t// /}"   # trim spaces
    [[ -z "$t" ]] && continue
    echo "  + $t"
    tag_add_one "$t"
  done
}

action_remove() {
  IFS=',' read -ra tags <<< "$1"
  for t in "${tags[@]}"; do
    t="${t// /}"
    [[ -z "$t" ]] && continue
    echo "  - $t"
    tag_remove_one "$t"
  done
}

action_replace_prefix() {
  local prefix="$1" new_tag="$2"
  echo "  ↺ replace tags matching '${prefix}*' with '${new_tag}'"
  while read -r t; do
    [[ -z "$t" ]] && continue
    case "$t" in
      "${prefix}"*)
        if [[ "$t" != "$new_tag" ]]; then
          echo "    - $t"
          tag_remove_one "$t"
        fi
        ;;
    esac
  done < <(current_tags)
  if ! current_tags | grep -qx -- "$new_tag"; then
    echo "    + $new_tag"
    tag_add_one "$new_tag"
  fi
}

action_set_commit() {
  local sha="${1:-}"
  if [[ -z "$sha" ]]; then
    sha=$(git rev-parse --short HEAD 2>/dev/null || true)
    [[ -z "$sha" ]] && { echo "ERROR: not in a git repo and no SHA given" >&2; exit 3; }
  fi
  action_replace_prefix "commit-" "commit-${sha}"
}

action_list() {
  current_tags
}

# Parse chained actions
echo "Tagging droplet '$DROPLET_NAME' (id=$DROPLET_ID):"
while [[ $# -gt 0 ]]; do
  case "$1" in
    add)            [[ $# -lt 2 ]] && usage 1; action_add "$2";              shift 2 ;;
    remove)         [[ $# -lt 2 ]] && usage 1; action_remove "$2";           shift 2 ;;
    replace-prefix) [[ $# -lt 3 ]] && usage 1; action_replace_prefix "$2" "$3"; shift 3 ;;
    set-commit)     # optional positional <sha>; if next arg looks like an action keyword, skip
      if [[ $# -ge 2 && "$2" != add && "$2" != remove && "$2" != replace-prefix && "$2" != set-commit && "$2" != list ]]; then
        action_set_commit "$2"; shift 2
      else
        action_set_commit; shift 1
      fi
      ;;
    list)           action_list;                                              shift 1 ;;
    *)              echo "ERROR: unknown action '$1'" >&2; usage 1 ;;
  esac
done

echo "Done. Current tags:"
current_tags | sed 's/^/  /'
