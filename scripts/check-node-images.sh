#!/usr/bin/env bash
# Every Node.js container image in the repo is a SUPPORTED major, pinned by
# digest (weown-fleet#98). node:20 reached end-of-life 2026-04-30, and a
# floating tag lets each host run whatever it last pulled.
# Usage: scripts/check-node-images.sh   (from the repo root; exit 1 on a finding)
set -euo pipefail
MIN_MAJOR=22   # oldest Node line still in support (EOL 2027-04-30)
bad=0
while IFS=: read -r file line text; do
  ref="$(printf '%s' "$text" | grep -oE 'node:[^[:space:]"]+' | head -1)"
  [[ -n "$ref" ]] || continue
  major="$(printf '%s' "$ref" | sed -nE 's/^node:([0-9]+).*/\1/p')"
  if [[ "$ref" != *@sha256:* ]]; then
    echo "::error file=$file,line=$line::$ref is not pinned by digest"; bad=1
  fi
  if [[ -z "$major" || "$major" -lt "$MIN_MAJOR" ]]; then
    echo "::error file=$file,line=$line::$ref is not a supported Node major (need >= $MIN_MAJOR)"; bad=1
  fi
done < <(git grep -nE '^[[:space:]]*(image:[[:space:]]*"?|FROM[[:space:]]+)node:' -- \
  '*compose*.yaml' '*compose*.yml' '*compose*.jinja' '*Dockerfile*' || true)
[[ $bad -eq 0 ]] && echo "ok: every node image is a supported major, pinned by digest"
exit $bad
