#!/usr/bin/env bash
# test-image-host-check.sh — the anythingllm deploy refuses an ANYTHINGLLM_IMAGE on a registry host
# other than the one the box logs in to (WeOwnDev/weown-fleet#112, #140 review).
#
# Renders the infisical and openbao variants with the default registry and with a mirror, cuts
# the check out of every compose-up block of the real playbook, and runs it. Expected by hand:
#   login host reg.mini.dev:   reg.mini.dev/ns/anythingllm:v1 pass · mirror image FAIL ·
#                              Docker Hub mintplexlabs/anythingllm:v1 pass · bare anythingllm:v1 pass
#   login host the mirror:     mirror image pass · reg.mini.dev image FAIL · localhost:5000/x FAIL
#   COPIER=... ./scripts/test-image-host-check.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COPIER="${COPIER:-copier}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
MIRROR=registry.example.test/weown
common=(--trust --defaults --quiet --vcs-ref HEAD --data project_name=ci-render-check --data domain=ci-render-check.example.test
  --data do_region=atl1 --data droplet_size=s-2vcpu-4gb-amd --data data_volume_size_gb=50
  --data infisical_project_id=00000000-0000-4000-8000-000000000000 --data infisical_environment=prod
  --data infisical_secret_path=/sites/ci-render-check --data cloudflare_proxied=false)
bao=(--data secret_backend=openbao --data bao_addr=https://bao.example.test:8200 --data bao_role_id=00000000-0000-4000-8000-000000000000
  --data bao_secret_path=platform/ci-render-check --data bao_cli_sha256=0000000000000000000000000000000000000000000000000000000000000000)
render() { "$COPIER" copy "$ROOT/anythingllm-docker" "$W/$1" "${common[@]}" "${@:2}" >/dev/null || { echo "FAIL render $1"; exit 1; }; }
render inf-default --data secret_backend=infisical
render bao-default "${bao[@]}"
render inf-mirror --data secret_backend=infisical --data image_registry="$MIRROR" --data registry_username=puller
render bao-mirror "${bao[@]}" --data image_registry="$MIRROR" --data registry_username=puller
pass=0; fail=0
for r in inf-default bao-default inf-mirror bao-mirror; do
  # Every check block: from `IMG_HOST=` to its closing `fi`, de-indented.
  python3 - "$W/$r/ansible/deploy.yml" "$W/$r.checks" <<'PY'
import sys, re
lines = open(sys.argv[1]).read().splitlines()
blocks, i = [], 0
while i < len(lines):
    if lines[i].lstrip().startswith('LOGIN_REG='):
        j = i
        while lines[j].strip() != "fi":
            j += 1
        blocks.append("\n".join(l.strip() for l in lines[i:j + 1]))
        i = j
    i += 1
open(sys.argv[2], "w").write("\0".join(blocks))
pass
PY
  n=$(tr -cd '\0' < "$W/$r.checks" | wc -c | tr -d ' '); n=$((n + 1))
  [[ "$n" -eq 2 ]] || { echo "FAIL $r: want 2 check blocks (two compose-up tasks), got $n"; fail=$((fail+1)); continue; }
  case "$r" in
    *default) cases=("reg.mini.dev/ns/anythingllm:v1 0" "$MIRROR/ns/anythingllm:v1 1" "mintplexlabs/anythingllm:v1 0" "anythingllm:v1 0") ;;
    *mirror)  cases=("$MIRROR/ns/anythingllm:v1 0" "reg.mini.dev/ns/anythingllm:v1 1" "localhost:5000/x:v1 1") ;;
  esac
  while IFS= read -r -d '' block || [[ -n "$block" ]]; do
    for c in "${cases[@]}"; do
      img="${c% *}"; want="${c##* }"
      ANYTHINGLLM_IMAGE="$img" bash -c "set -euo pipefail; $block" >/dev/null 2>&1; rc=$?
      got=$([[ $rc -eq 0 ]] && echo 0 || echo 1)
      if [[ "$got" == "$want" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $r: $img -> $got (want $want)"; fi
    done
  done < "$W/$r.checks"
done
echo "== $pass passed, $fail failed"; [[ $fail -eq 0 ]]
