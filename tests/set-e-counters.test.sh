#!/usr/bin/env bash
# Regression for weown-fleet#148: ((X++)) under set -e aborts on first increment.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
# 1) lint: fixed files must not use bare ((X++))
for f in scripts/check-template-alignment.sh scripts/verify-plan-safety.sh anythingllm/mcp.sh; do
  if grep -nE '\(\([A-Za-z_]+\+\+\)\)' "$ROOT/$f" | grep -v '|| true'; then echo "FAIL lint: $f"; fail=1; fi
done
# 2) behavior: alignment check on a fixture with 2 failures must report all of them
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
S="$T/keycloak-docker/sites/fx"; mkdir -p "$S/terraform" "$S/docker" "$S/scripts"
printf 'variable "db_password" {}\nvariable "infisical_client_id" {}\nvariable "infisical_client_secret" {}\n' > "$S/terraform/variables.tf"
echo 'enable_infisical = true' > "$S/terraform/main.tf"
echo 'infisical_client_id = ""' > "$S/terraform/terraform.tfvars"
echo 'services: {}' > "$S/docker/compose.prod.yaml"
echo 'x --projectId y' > "$S/scripts/deploy.sh"
out="$(cd "$T" && bash "$ROOT/scripts/check-template-alignment.sh" fx 2>&1)"; rc=$?
echo "$out" | grep -q 'Errors: 2' || { echo "FAIL behavior: expected 'Errors: 2' (rc=$rc)"; echo "$out" | tail -3; fail=1; }
[[ $rc -eq 1 ]] || { echo "FAIL behavior: rc=$rc want 1"; fail=1; }
[[ $fail -eq 0 ]] && echo "PASS set-e-counters" ; exit $fail
