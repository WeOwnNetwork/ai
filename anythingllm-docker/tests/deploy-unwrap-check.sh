#!/usr/bin/env bash
# deploy-unwrap-check.sh — behaviour test of the host-side secret-id unwrap in
# anythingllm-docker's openbao deploy (template/ansible/deploy.yml.jinja, task
# "Unwrap the secret-id on the HOST") against a REAL OpenBao dev server.
#
# Synthetic values only, in a throwaway dev store; nothing leaves this machine.
# The playbook is rendered with copier (secret_backend=openbao), the task's
# script is taken from the rendered YAML, its two ansible expressions (app_dir,
# bao_addr) are filled in as ansible would, and it runs as root in a container
# that shares the dev server's network namespace. `docker` inside is a stub that
# reports both consumers running and logs each restart.
#
# Expected outcomes come from what the deploy must guarantee: a first deploy
# writes a secret-id the store accepts (0600, uid 1000) and blanks the wrap
# token; a re-run with a valid secret-id changes nothing; a rejected secret-id
# is replaced from a fresh wrap token and both consumers restart; without a
# token, or with a spent one, the task fails and says why; and neither the
# secret-id nor the wrap token ever reaches a bao argv or the task output.
#
#   anythingllm-docker/tests/deploy-unwrap-check.sh
# Exit: 0 pass · 1 mismatch · 2 not run.
set -uo pipefail

BAO_IMAGE=quay.io/openbao/openbao:2.7.0
RUN_IMAGE=alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
ROLE_ID=role-test-123
APP=/opt/allm_test

T=$(cd "$(dirname "$0")/.." && pwd)
command -v docker > /dev/null || { echo "NOT RUN: docker is not installed"; exit 2; }
COPIER=${COPIER:-$(command -v copier)}
[ -n "$COPIER" ] || { echo "NOT RUN: copier is not installed"; exit 2; }
PY=${PYTHON:-python3}
"$PY" -c 'import yaml' 2> /dev/null || { echo "NOT RUN: $PY has no PyYAML"; exit 2; }

W=$(mktemp -d)
BAO=ducheck-bao-$$
cleanup() { docker rm -f "$BAO" > /dev/null 2>&1; find "$W" -delete 2> /dev/null; }
trap cleanup EXIT
PASS=0; FAIL=0
res() { if [ "$1" = "$2" ]; then echo "PASS     $3"; PASS=$((PASS + 1)); else echo "MISMATCH $3 (expected '$2', got '$1')"; FAIL=$((FAIL + 1)); fi; }

# --- render the playbook and extract the task's script ----------------------
"$COPIER" copy "$T" "$W/render" --defaults --trust --quiet \
  --data project_name=allm-test --data domain=allm.example.test \
  --data secret_backend=openbao --data bao_role_id="$ROLE_ID" \
  --data bao_secret_path=platform/allm-test \
  --data bao_cli_sha256=b82f5d05d0ab83244340893b8860542dccb9ff25422a30b3b9d60df0e34fb19d > /dev/null 2>&1 \
  || { echo "NOT RUN: copier render failed"; exit 2; }
"$PY" - "$W/render/ansible/deploy.yml" "$W/unwrap.sh" "$APP" << 'PY' || { echo "NOT RUN: could not extract the unwrap task"; exit 2; }
import sys, yaml
play = yaml.safe_load(open(sys.argv[1]))[0]
task = [t for t in play["tasks"] if t.get("name", "").startswith("Unwrap the secret-id on the HOST")]
assert len(task) == 1, "expected exactly one unwrap task"
cmd = task[0]["ansible.builtin.shell"]["cmd"]
cmd = cmd.replace("{{ app_dir }}", sys.argv[3]).replace("{{ bao_addr | quote }}", "'https://127.0.0.1:8200'")
assert "{{" not in cmd and "{%" not in cmd, "unrendered expression left in the script"
open(sys.argv[2], "w").write(cmd)
PY

# --- the dev store ----------------------------------------------------------
docker run -d --name "$BAO" --cap-add=IPC_LOCK --tmpfs /certs:mode=1777 "$BAO_IMAGE" \
  bao server -dev -dev-tls -dev-tls-cert-dir=/certs -dev-root-token-id=root \
  -dev-listen-address=127.0.0.1:8200 > /dev/null || { echo "NOT RUN: dev server did not start"; exit 2; }
for _ in $(seq 30); do docker exec "$BAO" sh -c 'ls /certs/*ca*.pem' > /dev/null 2>&1 && break; sleep 1; done
CA=$(docker exec "$BAO" sh -c 'ls /certs/*ca*.pem 2>/dev/null | head -1')
[ -n "$CA" ] || { echo "NOT RUN: no dev CA in /certs"; exit 2; }
mkdir -p "$W/app"
docker exec "$BAO" cat "$CA" > "$W/app/.bao-ca.crt"
[ -s "$W/app/.bao-ca.crt" ] || { echo "NOT RUN: could not read the dev CA"; exit 2; }
docker cp "$BAO:/usr/bin/bao" "$W/bao-real" > /dev/null
adm() { docker exec -i -e BAO_ADDR=https://127.0.0.1:8200 -e BAO_CACERT="$CA" -e BAO_TOKEN=root "$BAO" bao "$@"; }
for _ in $(seq 30); do adm status > /dev/null 2>&1 && break; sleep 1; done
adm auth enable approle > /dev/null
adm write auth/approle/role/svc-test token_ttl=1h > /dev/null
adm write auth/approle/role/svc-test/role-id role_id="$ROLE_ID" > /dev/null
wrap() { adm write -wrap-ttl=1h -f -field=wrapping_token auth/approle/role/svc-test/secret-id; }

# argv logger in front of the real bao; a docker stub for the restart loop.
cat > "$W/bao" << 'SH'
#!/bin/sh
printf '%s\n' "$*" >> /w/argv.log
exec /w/bao-real "$@"
SH
cat > "$W/docker" << 'SH'
#!/bin/sh
case "$1" in
  ps) echo running ;;
  restart) echo "$2" >> /w/restarts.log ;;
esac
SH
chmod 0755 "$W/bao" "$W/docker"

# The image's package index is the distro's own channel; bash and jq are what
# the script needs beyond busybox, and the droplet has both.
docker run --rm "$RUN_IMAGE" true > /dev/null 2>&1 || { echo "NOT RUN: cannot run $RUN_IMAGE"; exit 2; }
TOOLS=$(docker run -d --network "container:$BAO" -v "$W:/w" -v "$W/app:$APP" "$RUN_IMAGE" sleep 600) \
  || { echo "NOT RUN: tool container did not start"; exit 2; }
trap 'docker rm -f "$TOOLS" > /dev/null 2>&1; cleanup' EXIT
docker exec "$TOOLS" sh -c 'apk add -q --no-cache bash jq > /dev/null && ln -sf /w/bao /usr/bin/bao && ln -sf /w/docker /usr/bin/docker' \
  || { echo "NOT RUN: could not add bash and jq to the tool container"; exit 2; }

run() {  # run <stdin line>  -> output in $W/out, rc returned
  : > "$W/restarts.log"
  printf '%s\n' "$1" | docker exec -i "$TOOLS" bash /w/unwrap.sh > "$W/out" 2>&1
  local rc=$?
  cat "$W/out" >> "$W/allout"
  return $rc
}
sid_logs_in() {  # does the secret-id on disk log in with the role?
  docker exec "$TOOLS" sh -c "jq -nc --arg r $ROLE_ID --rawfile s $APP/.bao-secret-id '{role_id: \$r, secret_id: \$s}' \
    | BAO_ADDR=https://127.0.0.1:8200 BAO_CACERT=$APP/.bao-ca.crt /w/bao-real write -field=token auth/approle/login - > /dev/null 2>&1" \
    && echo yes || echo no
}
: > "$W/argv.log"; chmod 0666 "$W/argv.log"; : > "$W/allout"
SEEN=""  # every credential value handed to the script, checked against argv and output

echo "== U1. first deploy: a wrap token on stdin becomes a working secret-id"
TOK1=$(wrap); SEEN="$SEEN $TOK1"
run "BAO_WRAP_TOKEN=$TOK1"; rc=$?
res "$rc" 0 "U1 exits 0"
res "$(sid_logs_in)" yes "U1 the secret-id on disk logs in"
res "$(docker exec "$TOOLS" stat -c '%a %u' $APP/.bao-secret-id)" "600 1000" "U1 secret-id is 0600 uid 1000"
res "$(docker exec "$TOOLS" sh -c "[ -s $APP/.bao-wrap.token ] && echo full || echo blank")" blank "U1 wrap token blanked"
res "$(sort "$W/restarts.log" | tr '\n' ' ')" "allm_test-anythingllm-1 allm_test-dashboard-1 " "U1 both consumers restarted"
SID1=$(docker exec "$TOOLS" cat $APP/.bao-secret-id); SEEN="$SEEN $SID1"

echo "== U2. re-run with a valid secret-id and no token: nothing changes"
run "BAO_WRAP_TOKEN="; rc=$?
res "$rc" 0 "U2 exits 0"
res "$(grep -c 'VALID — nothing to unwrap' "$W/out")" 1 "U2 says the secret-id is valid"
res "$(docker exec "$TOOLS" cat $APP/.bao-secret-id)" "$SID1" "U2 secret-id unchanged"
res "$(wc -l < "$W/restarts.log" | tr -d ' ')" 0 "U2 no restart"

echo "== U3. a rejected secret-id is replaced from a fresh token"
docker exec "$TOOLS" sh -c "printf 'not-a-valid-secret-id' > $APP/.bao-secret-id"
TOK3=$(wrap); SEEN="$SEEN $TOK3"
run "BAO_WRAP_TOKEN=$TOK3"; rc=$?
res "$rc" 0 "U3 exits 0"
res "$(grep -c 'REJECTED by the store' "$W/out")" 1 "U3 says the old one was rejected"
res "$(sid_logs_in)" yes "U3 the new secret-id logs in"
res "$(wc -l < "$W/restarts.log" | tr -d ' ')" 2 "U3 both consumers restarted"
SEEN="$SEEN $(docker exec "$TOOLS" cat $APP/.bao-secret-id)"

echo "== U4. a rejected secret-id and no token: fails and says what is needed"
docker exec "$TOOLS" sh -c "printf 'not-a-valid-secret-id' > $APP/.bao-secret-id"
run "BAO_WRAP_TOKEN="; rc=$?
res "$([ "$rc" -ne 0 ] && echo failed || echo ok)" failed "U4 exits non-zero"
res "$(grep -c 'need BAO_WRAP_TOKEN' "$W/out")" 1 "U4 names BAO_WRAP_TOKEN"
res "$(wc -l < "$W/restarts.log" | tr -d ' ')" 0 "U4 no restart"

echo "== U5. a spent wrap token: fails and says to mint a fresh one"
run "BAO_WRAP_TOKEN=$TOK1"; rc=$?
res "$([ "$rc" -ne 0 ] && echo failed || echo ok)" failed "U5 exits non-zero"
res "$(grep -c 'unwrap failed' "$W/out")" 1 "U5 says the unwrap failed"
res "$(docker exec "$TOOLS" sh -c "[ -s $APP/.bao-wrap.token ] && echo full || echo blank")" blank "U5 the failed token is not kept on disk"

echo "== U6. after a failed unwrap, the next fresh token is used (not the spent one on disk)"
TOK6=$(wrap); SEEN="$SEEN $TOK6"
run "BAO_WRAP_TOKEN=$TOK6"; rc=$?
res "$rc" 0 "U6 exits 0"
res "$(sid_logs_in)" yes "U6 the secret-id from the fresh token logs in"
res "$(docker exec "$TOOLS" sh -c "[ -s $APP/.bao-wrap.token ] && echo full || echo blank")" blank "U6 wrap token blanked"
SEEN="$SEEN $(docker exec "$TOOLS" cat $APP/.bao-secret-id)"

echo "== U8. a VALID secret-id plus a fresh token: the token rotates it"
SID6=$(docker exec "$TOOLS" cat $APP/.bao-secret-id)
TOK8=$(wrap); SEEN="$SEEN $TOK8"
run "BAO_WRAP_TOKEN=$TOK8"; rc=$?
res "$rc" 0 "U8 exits 0"
res "$(grep -c 'rotating to the new one' "$W/out")" 1 "U8 says it is rotating"
res "$([ "$(docker exec "$TOOLS" cat $APP/.bao-secret-id)" != "$SID6" ] && echo changed || echo same)" changed "U8 the secret-id was replaced"
res "$(sid_logs_in)" yes "U8 the new secret-id logs in"
res "$(sort "$W/restarts.log" | tr '\n' ' ')" "allm_test-anythingllm-1 allm_test-dashboard-1 " "U8 both consumers restarted"
SID8=$(docker exec "$TOOLS" cat $APP/.bao-secret-id); SEEN="$SEEN $SID8"

echo "== U9. a VALID secret-id plus a spent token: warns, keeps the working one, deploy goes on"
run "BAO_WRAP_TOKEN=$TOK8"; rc=$?
res "$rc" 0 "U9 exits 0"
res "$(grep -c 'rotation NOT done' "$W/out")" 1 "U9 warns that it did not rotate"
res "$([ "$(docker exec "$TOOLS" cat $APP/.bao-secret-id)" = "$SID8" ] && echo kept || echo changed)" kept "U9 the secret-id is unchanged"
res "$(wc -l < "$W/restarts.log" | tr -d ' ')" 0 "U9 no restart"
res "$(docker exec "$TOOLS" sh -c "[ -s $APP/.bao-wrap.token ] && echo full || echo blank")" blank "U9 the spent token is not kept on disk"

echo "== U7. no credential value reached a bao argv or the task output"
hits=0; outhits=0
for v in $SEEN; do
  grep -qF -- "$v" "$W/argv.log" && hits=$((hits + 1))
  grep -qF -- "$v" "$W/allout" && outhits=$((outhits + 1))
done
res "$hits" 0 "U7 no secret-id or wrap token in $(wc -l < "$W/argv.log" | tr -d ' ') logged bao calls"
res "$outhits" 0 "U7 none in the task output"

echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
