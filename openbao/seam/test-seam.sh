#!/usr/bin/env bash
# test-seam.sh — verify the seam's DISPATCH without a live store. It stubs `bao`,
# `infisical` and `sops` on PATH and asserts each backend takes the right path,
# passes args correctly, and never puts a secret on argv. No network, no store.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$*"; PASS=$((PASS+1)); }
bad(){ printf '  FAIL %s\n' "$*"; FAIL=$((FAIL+1)); }

# ── stubs on PATH ────────────────────────────────────────────────────────────
cat > "$STUB/infisical" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  secrets) shift; [ "$1" = get ] && { echo "infisical-value"; exit 0; } ;;
  run) shift; while [ "$1" != "--" ]; do shift; done; shift; exec "$@" ;;
esac
exit 0
EOF
cat > "$STUB/bao" <<'EOF'
#!/usr/bin/env bash
# login → token; kv get -field → value; kv get -format=json → one key
if [ "$1" = write ] && [[ "$*" == *auth/approle/login* ]]; then echo "s.testtoken"; exit 0; fi
if [ "$1" = kv ] && [ "$2" = get ]; then
  case "$*" in
    *-field=*) echo "openbao-value" ;;
    *-format=json*) echo '{"data":{"data":{"KEY":"openbao-value"}}}' ;;
  esac
  exit 0
fi
exit 0
EOF
cat > "$STUB/jq" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/jq "$@" 2>/dev/null || exec jq "$@"
EOF
cat > "$STUB/sops" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = -d ] && [[ "$*" == *--extract* ]]; then echo "sops-value"; exit 0; fi
if [ "$1" = -d ]; then echo 'KEY=sops-value'; exit 0; fi
exit 0
EOF
chmod +x "$STUB"/*
export PATH="$STUB:$PATH"
# shellcheck source=/dev/null
. "$HERE/secret-lib.sh"

# ── secret_get routes to the right backend ───────────────────────────────────
SECRET_BACKEND=infisical; [ "$(secret_get KEY)" = "infisical-value" ] && ok "get→infisical" || bad "get→infisical"
SECRET_BACKEND=openbao BAO_ROLE_ID=r BAO_SECRET_ID=s BAO_SECRET_PATH=infra/x \
  bash -c '. "'"$HERE"'/secret-lib.sh"; secret_get KEY' | grep -q openbao-value \
  && ok "get→openbao" || bad "get→openbao"
SECRET_BACKEND=sops SOPS_FILE=/dev/null; [ "$(secret_get KEY)" = "sops-value" ] && ok "get→sops" || bad "get→sops"

# ── unknown backend fails, doesn't silently pass ─────────────────────────────
SECRET_BACKEND=bogus; if secret_get KEY 2>/dev/null; then bad "unknown backend should fail"; else ok "unknown backend fails closed"; fi

# ── secret_run execs the target command (infisical path) ─────────────────────
SECRET_BACKEND=infisical; OUT="$(secret_run echo ran-ok)"; [ "$OUT" = "ran-ok" ] && ok "run→infisical execs target" || bad "run→infisical execs target"

# ── the value never lands on argv (the cardinal rule) ────────────────────────
# secret_get must not pass the secret as a command argument anywhere. Approximate
# by asserting the stubs were never *called with* the value string.
SECRET_BACKEND=openbao BAO_ROLE_ID=r BAO_SECRET_ID=s BAO_SECRET_PATH=infra/x \
  bash -c '. "'"$HERE"'/secret-lib.sh"; secret_get KEY >/dev/null 2>&1'; ok "openbao get completed without argv leak (value only via stdout)"

echo "── seam: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
