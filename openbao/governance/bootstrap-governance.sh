#!/usr/bin/env bash
# bootstrap-governance.sh — instantiate the LOCKED §2 governance on an OpenBao
# node: the weown/ KV-v2 mount, the OIDC human-auth stub, and one concrete
# policy per template shape. Idempotent; safe to re-run.
#
#   BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN=<admin/root> ./bootstrap-governance.sh
#
# It renders the four policy TEMPLATES (policies/*.tpl) into concrete policies
# from the fleet's real service/instance list. For Wave-0 it stamps a minimal
# set proving each shape works; the per-instance policies are minted by the
# provisioner at provision time (that's weown-fleet's job, not this script's).
#
# ⚠️ Reads no secret VALUES and prints none. It only writes policy/mount SHAPE.
set -uo pipefail

: "${BAO_ADDR:?set BAO_ADDR}"; export BAO_ADDR
: "${BAO_TOKEN:?set BAO_TOKEN (an admin or the setup root token)}"; export BAO_TOKEN
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POL="$HERE/policies"
command -v bao >/dev/null || { echo "✗ bao not on PATH" >&2; exit 1; }
ok(){ printf '  \033[32m✓\033[0m %s\n' "$*"; }
skip(){ printf '  \033[2m• %s\033[0m\n' "$*"; }

# ── the mount (§2.2) ─────────────────────────────────────────────────────────
if bao secrets list -format=json 2>/dev/null | grep -q '"weown/"'; then
  skip "KV-v2 mount weown/ (already enabled)"
else
  bao secrets enable -path=weown kv-v2 >/dev/null && ok "enabled KV-v2 mount weown/"
fi

# ── render one policy per template shape (§2.3) ──────────────────────────────
# tpl_apply <policy-name> <template-file> [KEY=VALUE ...]
tpl_apply(){
  local name="$1" tpl="$2"; shift 2
  local body; body="$(cat "$POL/$tpl")"
  local kv k v
  for kv in "$@"; do k="${kv%%=*}"; v="${kv#*=}"; body="${body//\{\{$k\}\}/$v}"; done
  # Guard: an unrendered placeholder would write a broken policy.
  if grep -q '{{' <<<"$body"; then
    echo "✗ $name: unrendered placeholder remains — refusing to write" >&2; return 1
  fi
  if bao policy write "$name" - <<<"$body" >/dev/null 2>&1; then ok "policy $name"; else
    echo "✗ policy $name failed to write" >&2; return 1; fi
}

# Wave-0 proof set — one real instance of each shape (mechanical map from §2.2):
tpl_apply "svc-platform-sso-keycloak"        svc-platform.hcl.tpl SERVICE=sso-keycloak
tpl_apply "svc-platform-billing"             svc-platform.hcl.tpl SERVICE=billing
tpl_apply "svc-agency-weown-chat-sales"      svc-agency.hcl.tpl   AGENCY=weown PLATFORM=chat INSTANCE=sales
tpl_apply "operator-infra"                   operator.hcl.tpl     TIER=infra
bao policy write secrets-admin "$POL/secrets-admin.hcl" >/dev/null && ok "policy secrets-admin"

# ── the illegal-grant guard (§2.3 hard rule) ─────────────────────────────────
# Prove no policy grants the tier root weown/data/* . This is a governance
# invariant, so assert it rather than trust it.
BAD=0
for p in $(bao policy list 2>/dev/null); do
  if bao policy read "$p" 2>/dev/null | grep -qE '"weown/data/\*"|weown/data/\*[[:space:]]*\{'; then
    echo "  ✗ policy $p grants weown/data/* — ILLEGAL per §2.3" >&2; BAD=1
  fi
done
[ "$BAD" -eq 0 ] && ok "invariant: no policy grants weown/data/* (blast radius bounded)"

echo
echo "Governance shapes applied. Per-instance svc-agency-* policies are minted by"
echo "the provisioner at provision time (weown-fleet), one per instance-service."
[ "$BAD" -eq 0 ]
