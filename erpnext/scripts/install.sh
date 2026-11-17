#!/usr/bin/env bash
# Install ERPNext only after every pod template requires weown.dev/pool=erpnext.
# Password is read from ERP_DB_ROOT_PASSWORD. It is not printed or written here.
#
#   export ERP_DB_ROOT_PASSWORD
#   ./scripts/install.sh
#
# Dry-run only:
#   DRY_RUN=1 ERP_DB_ROOT_PASSWORD=dry-run-placeholder ./scripts/install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${ERP_DB_ROOT_PASSWORD:?Set ERP_DB_ROOT_PASSWORD in the environment. Do not commit it.}"

args=(
  upgrade --install erpnext frappe/erpnext
  --version 8.0.89
  --namespace erpnext
  --create-namespace
  -f "$ROOT/values.yaml"
  --set "mariadb-sts.rootPassword=${ERP_DB_ROOT_PASSWORD}"
  --post-renderer "$ROOT/scripts/pin-pool.cmd"
)

if [[ "${DRY_RUN:-}" == "1" ]]; then
  helm "${args[@]}" --dry-run=client \
    | python "$ROOT/scripts/verify-pin.py"
  exit 0
fi

helm "${args[@]}" --dry-run=client \
  | python "$ROOT/scripts/verify-pin.py"
helm "${args[@]}"
