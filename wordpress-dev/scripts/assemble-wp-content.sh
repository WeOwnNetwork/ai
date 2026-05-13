#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_KEY="${1:-}"
[[ -z "$SITE_KEY" ]] && { echo "Usage: $0 <site-key>"; exit 1; }

SRC_TEMPLATE="$ROOT/template/wp-content"
SRC_OVERRIDES="$ROOT/sites/$SITE_KEY/overrides/wp-content"
OUT_DIR="$ROOT/.build/$SITE_KEY/wp-content"

rm -rf "$ROOT/.build/$SITE_KEY"
mkdir -p "$OUT_DIR"
rsync -a "$SRC_TEMPLATE/" "$OUT_DIR/"
if [ -d "$SRC_OVERRIDES" ]; then
  rsync -a "$SRC_OVERRIDES/" "$OUT_DIR/"
fi
echo "Composed wp-content at $OUT_DIR"
