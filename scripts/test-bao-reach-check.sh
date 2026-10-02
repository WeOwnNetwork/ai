#!/usr/bin/env bash
# test-bao-reach-check.sh — the anythingllm openbao deploy stops with a reason when the
# platform store is unreachable from the droplet (WeOwnDev/weown-fleet#36).
#
# Renders the openbao variant, takes the two pre-check tasks out of the real playbook,
# and runs them on localhost against three stores. Expected values by hand:
#   refused port (https://127.0.0.1:1)        -> playbook fails, message names the /32 allowlist
#   reachable HTTPS host, valid CA bundle      -> passes (any HTTP answer = reachable)
#   reachable host, CA file is not a cert      -> fails with the reason (TLS)
#   the same under ansible --check            -> same verdicts (the probe is read-only and runs)
# Needs copier, ansible-playbook and network access for the reachable case.
#   COPIER=... ANSIBLE_PLAYBOOK=... ./scripts/test-bao-reach-check.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COPIER="${COPIER:-copier}"; PLAYBOOK="${ANSIBLE_PLAYBOOK:-ansible-playbook}"
CA_BUNDLE="${CA_BUNDLE:-$(for f in /etc/ssl/cert.pem /etc/ssl/certs/ca-certificates.crt; do [ -f "$f" ] && echo "$f" && break; done)}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
"$COPIER" copy --trust --defaults --quiet --vcs-ref HEAD "$ROOT/anythingllm-docker" "$W/r" \
  --data project_name=ci-render-check --data domain=ci-render-check.example.test --data do_region=atl1 \
  --data droplet_size=s-2vcpu-4gb-amd --data data_volume_size_gb=50 \
  --data infisical_project_id=00000000-0000-4000-8000-000000000000 --data infisical_environment=prod \
  --data infisical_secret_path=/sites/ci-render-check --data cloudflare_proxied=false \
  --data secret_backend=openbao --data bao_addr=https://bao.example.test:8200 \
  --data bao_role_id=00000000-0000-4000-8000-000000000000 --data bao_secret_path=platform/ci-render-check \
  --data bao_cli_sha256=0000000000000000000000000000000000000000000000000000000000000000 >/dev/null || { echo "FAIL render"; exit 1; }
python3 - "$W/r/ansible/deploy.yml" > "$W/play.yml" <<'PY' || { echo "FAIL: the pre-check tasks are not in the rendered playbook"; exit 1; }
import sys, yaml
tasks = [t for play in yaml.safe_load(open(sys.argv[1])) for t in (play.get("tasks") or [])
         if t.get("name", "").startswith(("Check the platform store is reachable", "Stop with the reason when the store is unreachable"))]
assert len(tasks) == 2
print(yaml.safe_dump([{"hosts": "localhost", "connection": "local", "gather_facts": False, "tasks": tasks}], sort_keys=False))
PY
mkdir -p "$W/good" "$W/bad"; cp "$CA_BUNDLE" "$W/good/.bao-ca.crt"; echo "not a cert" > "$W/bad/.bao-ca.crt"
pass=0; fail=0
case_() { # name app_dir bao_addr want_rc want_text [extra ansible args]
  "$PLAYBOOK" -i 'localhost,' "$W/play.yml" -e app_dir="$2" -e bao_addr="$3" "${@:6}" > "$W/out" 2>&1; local rc=$?
  if [[ $rc -eq $4 ]] && { [[ -z "$5" ]] || grep -q "$5" "$W/out"; }; then pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1 (rc $rc, want $4)"; tail -5 "$W/out"; fi
}
case_ "refused port: stops, names the /32 allowlist" "$W/good" https://127.0.0.1:1 2 "platform_api_source_cidrs"
case_ "reachable HTTPS host: passes"                 "$W/good" https://openrouter.ai 0 ""
case_ "unusable CA file: stops with the TLS reason"  "$W/bad"  https://openrouter.ai 2 "unreachable from this droplet"
case_ "--check, refused port: still stops (probe runs)" "$W/good" https://127.0.0.1:1 2 "platform_api_source_cidrs" --check
case_ "--check, reachable host: passes"         "$W/good" https://openrouter.ai 0 "" --check
echo "== $pass passed, $fail failed"; [[ $fail -eq 0 ]]
