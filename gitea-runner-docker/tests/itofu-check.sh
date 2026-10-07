#!/usr/bin/env bash
# itofu-check.sh — the rendered terraform/itofu.sh's plan/apply rules, with stand-in
# infisical and tofu on PATH (no Infisical, no state, nothing applied):
#   - plan writes the saved plan 0600 even under an operator umask of 022;
#   - a failed re-plan leaves NO plan behind, so apply cannot run a stale one;
#   - apply refuses arguments, and refuses without a saved plan;
#   - apply runs exactly the saved plan, then deletes it.
#
#   gitea-runner-docker/tests/itofu-check.sh <site-dir>
# Exit: 0 pass · 1 mismatch · 2 not run.
set -uo pipefail
SITE=$(cd "${1:?usage: $0 <site-dir>}" && pwd) || exit 2
W=$(mktemp -d)
trap 'find "$W" -delete 2>/dev/null' EXIT
BAD=0
res() { if [ "$1" = "$2" ]; then echo "PASS     $3"; else echo "MISMATCH $3 (expected '$2', got '$1')"; BAD=1; fi; }
mkdir -p "$W/bin" "$W/tf"
cp "$SITE/terraform/itofu.sh" "$W/tf/itofu.sh"
cat > "$W/bin/infisical" <<'EOF'
#!/usr/bin/env bash
# export = the session probe; run = exec the command after --, with synthetic TF_VARs.
case "$1" in
  export) exit 0 ;;
  run) while [ "$1" != "--" ]; do shift; done; shift
       TF_VAR_spaces_access_key=a TF_VAR_spaces_secret_key=b exec "$@" ;;
esac
EOF
cat > "$W/bin/tofu" <<'EOF'
#!/usr/bin/env bash
echo "tofu $*" >> "$CALLS"
case "$1" in
  plan) [ "${TOFU_FAIL:-0}" = 1 ] && exit 1
        for a in "$@"; do case "$a" in -out=*) : > "${a#-out=}" ;; esac; done ;;
esac
EOF
chmod +x "$W/bin/infisical" "$W/bin/tofu"
export CALLS="$W/calls" WEOWN_TOFU_PROJECT_ID=p PATH="$W/bin:$PATH"
cd "$W/tf" || exit 2
mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }

: > "$CALLS"; (umask 022; bash itofu.sh plan > /dev/null 2>&1)
res "$( [ -f plan.tfplan ] && mode plan.tfplan || echo none)" 600 "plan: the saved plan is 0600 under an operator umask of 022"
: > "$CALLS"; (TOFU_FAIL=1 bash itofu.sh plan > /dev/null 2>&1)
res "$( [ -f plan.tfplan ] && echo present || echo gone)" gone "a failed re-plan leaves no plan behind (the old one is deleted first)"
bash itofu.sh apply > /dev/null 2>&1; rc=$?
res "$rc|$(grep -c 'tofu apply' "$CALLS")" "1|0" "apply without a saved plan: refused, tofu apply never runs"
(bash itofu.sh plan > /dev/null 2>&1); : > "$CALLS"
bash itofu.sh apply -auto-approve > /dev/null 2>&1; rc=$?
res "$rc|$(grep -c 'tofu apply' "$CALLS")" "1|0" "apply with arguments: refused, tofu apply never runs"
bash itofu.sh apply > /dev/null 2>&1; rc=$?
res "$rc|$(cat "$CALLS")|$( [ -f plan.tfplan ] && echo present || echo gone)" "0|tofu apply plan.tfplan|gone" "apply runs exactly the saved plan, then deletes it"
exit "$BAD"
