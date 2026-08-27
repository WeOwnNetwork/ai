#!/usr/bin/env bash
# readme-links.test.sh — every relative link in a README must resolve.
#
# A README that indexes a repo's features is only useful if its drill-down links
# work. "Link only to files that exist" is a rule someone must REMEMBER at the
# moment they add a row, and a link index decays silently — it is believed while
# wrong. This makes the rule mechanical.
#
# Checks every inline Markdown link target that is RELATIVE. Skipped by design:
# absolute URLs (nothing local to verify), mailto:, and same-document #anchors.
#
# Two ways a link fails, reported differently because they need different fixes:
# BROKEN (no such path) and LOCAL-ONLY (on this disk, absent from git — so it
# 404s for every reader on the forge).
#
# Percent-encoded paths are DECODED before testing, because `[x](My%20Docs/)` is
# a correct link that both Gitea and Obsidian render — reporting it broken would
# manufacture a failure on working content, which erodes trust in the checker.
#
# But a false GREEN is the graver defect for THIS instrument, and the two are not
# symmetric: a false red announces itself (someone investigates and finds nothing
# wrong), while a false green is silent and surfaces only when a reader clicks a
# 404. This checker exists to stop an index rotting WHILE BEING BELIEVED, so a
# false green does not merely weaken it — it defeats its purpose.
#
# Portable by design — the repo root is derived from the README's own location,
# so this file can be copied into any repo unchanged.
#
# Usage:  bash tests/readme-links.test.sh [path/to/README.md]

set -uo pipefail

README="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/README.md}"
# Links in a Markdown file resolve relative to that file's directory.
ROOT="$(cd "$(dirname "$README")" && pwd)"

# NAME THE ARTIFACT LOUDLY. A persisted `cd` once pointed a run at the WRONG
# repo's README and printed a clean green; it was caught only because the operator
# happened to know their expected target count (22) and saw 70. A verdict that does
# not say what it verified can be a true statement about the wrong thing.
_repo="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)"
_label="$README"
[ -n "$_repo" ] && _label="$(basename "$_repo")/${README#"$_repo"/}"
echo "readme-links"
echo "  ► $_label"

if [ ! -f "$README" ]; then
  echo "  ❌ no README at $README"
  exit 1
fi

# Decode %XX, and ONLY %XX. A blanket `${t//%/\\x}` would corrupt a literal
# percent that is not an escape (a path containing `100%` becomes `\x10`+`0`),
# turning one false red into a different one.
urldecode() {
  local s
  s="$(printf '%s' "$1" | sed -E 's/%([0-9A-Fa-f]{2})/\\x\1/g')"
  printf '%b' "$s"
}

targets="$(grep -oE '\]\([^)]+\)' "$README" \
  | sed -E 's/^\]\(//; s/\)$//' \
  | grep -vE '^(https?://|mailto:|#)' \
  | sed -E 's/#.*$//' \
  | sed -E 's/[[:space:]]+".*"$//' \
  | sort -u)"

# EXISTING ON DISK IS NOT THE SAME AS VISIBLE ON THE FORGE, and the link is
# followed on the forge. Git tracks no empty directories, and ignored paths
# (node_modules/, dist/, .venv/, coverage/) exist locally and ship nowhere — so a
# filesystem test reports green on links that 404 for every reader.
#
# untracked-but-NOT-ignored counts as visible: it is work about to be committed,
# and failing it would be the false-RED direction this checker already refuses.
visible() { # $1 = path relative to ROOT -> 0 visible, 1 missing, 2 local-only
  local t="$1"
  [ -e "$ROOT/$t" ] || return 1
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0   # no git: disk is all there is
  if [ -d "$ROOT/$t" ]; then
    [ -n "$(git -C "$ROOT" ls-files -- "$t" 2>/dev/null | head -1)" ] && return 0
    return 2
  fi
  [ -n "$(git -C "$ROOT" ls-files -- "$t" 2>/dev/null)" ] && return 0
  git -C "$ROOT" check-ignore -q -- "$t" 2>/dev/null && return 2
  return 0
}

total=0; broken=0
while IFS= read -r t; do
  [ -z "$t" ] && continue
  total=$((total+1))
  decoded="$(urldecode "$t")"
  # Accept either spelling: a path may legitimately contain a literal % that the
  # decoder would alter, so a hit on EITHER means the link resolves.
  visible "$t"; rc=$?
  if [ "$rc" -ne 0 ]; then
    visible "$decoded"; rc=$?
  fi
  case "$rc" in
    0) ;;
    1) echo "  ❌ BROKEN: $t (no such path)"; broken=$((broken+1)) ;;
    2) echo "  ❌ LOCAL-ONLY: $t (exists here, but git does not carry it — 404 on the forge)"
       broken=$((broken+1)) ;;
  esac
done <<< "$targets"

echo "  $total relative link target(s), $broken broken"

# A README with no relative links at all has not adopted the convention. That is
# the un-indexed starting state, and it must not read as a pass.
if [ "$total" -eq 0 ]; then
  echo "  ❌ no relative links found — the README is not a feature index"
  exit 1
fi

if [ "$broken" -ne 0 ]; then
  echo "  ❌ FAIL — $_label: $broken of $total drill-down link(s) do not resolve"
  exit 1
fi

echo "  ✅ $_label — all $total drill-down link(s) resolve"
