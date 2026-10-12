#!/usr/bin/env bash
# backup-bao-check.sh — behaviour test of billing-docker's openbao backup path
# (scripts/bao-run.sh + the daily backup cron in ansible/deploy.yml) against a
# REAL OpenBao dev server. weown-fleet#166 stage 4.
#
# Synthetic values only, in a throwaway dev store; nothing leaves this machine.
# The template is rendered with copier (secret_backend=openbao). The cron file
# is taken from the rendered playbook and run as-is with app_dir filled in as
# ansible would; backup.sh is replaced by a probe that records which backup
# keys it received. entrypoint-bao.sh gets the dev store's URL where the deploy
# would write the real one.
#
# Expected outcomes come from what billing's backups must guarantee: with every
# key in the store the backup runs with exactly those values; with one missing,
# or a secret-id the store rejects, the backup does not run and the cron fails
# at once (one login attempt, no cooldown sleep); a refusal is recorded and no
# further login is made until the deploy clears it; no value reaches a bao,
# docker or aws argv (pg_dump gets the password on stdin); the archive is
# owner-only; a render without DO Spaces asks for no Spaces keys, and the
# unimplemented s3 target is refused.
#
#   billing-docker/tests/backup-bao-check.sh
# Exit: 0 pass · 1 mismatch · 2 not run.
set -uo pipefail

BAO_IMAGE=quay.io/openbao/openbao:2.7.0
RUN_IMAGE=alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
ROLE_ID=role-test-456
KV_PATH=platform/billing
APP=/opt/billing_test

T=$(cd "$(dirname "$0")/.." && pwd)
command -v docker > /dev/null || { echo "NOT RUN: docker is not installed"; exit 2; }
COPIER=${COPIER:-$(command -v copier)}
[ -n "$COPIER" ] || { echo "NOT RUN: copier is not installed"; exit 2; }
PY=${PYTHON:-python3}
"$PY" -c 'import yaml' 2> /dev/null || { echo "NOT RUN: $PY has no PyYAML"; exit 2; }

W=$(mktemp -d)
BAO=bbcheck-bao-$$
TOOLS=""
cleanup() { [ -n "$TOOLS" ] && docker rm -f "$TOOLS" > /dev/null 2>&1; docker rm -f "$BAO" > /dev/null 2>&1; find "$W" -delete 2> /dev/null; }
trap cleanup EXIT
PASS=0; FAIL=0
res() { if [ "$1" = "$2" ]; then echo "PASS     $3"; PASS=$((PASS + 1)); else echo "MISMATCH $3 (expected '$2', got '$1')"; FAIL=$((FAIL + 1)); fi; }

render() {  # render <dir> [extra copier args...]
  local d=$1; shift
  "$COPIER" copy "$T" "$d" --defaults --trust --quiet \
    --data project_name=billing-test --data domain=billing.example.test \
    --data secret_backend=openbao --data bao_role_id="$ROLE_ID" \
    --data bao_secret_path="$KV_PATH" "$@" > /dev/null 2>&1
}

# --- render, and take the cron file from the playbook -----------------------
render "$W/render" || { echo "NOT RUN: copier render failed"; exit 2; }
"$PY" - "$W/render/ansible/deploy.yml" "$W/cron.sh" "$APP" << 'PY' || { echo "NOT RUN: could not extract the backup cron task"; exit 2; }
import sys, yaml
play = yaml.safe_load(open(sys.argv[1]))[0]
task = [t for t in play["tasks"] if t.get("name", "").startswith("Install daily backup cron")]
assert len(task) == 1, "expected exactly one backup cron task"
body = task[0]["ansible.builtin.copy"]["content"].replace("{{ app_dir }}", sys.argv[3])
assert "{{" not in body and "{%" not in body, "unrendered expression left in the cron file"
open(sys.argv[2], "w").write(body)
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
adm secrets enable -path=weown kv-v2 > /dev/null
printf 'path "weown/data/%s" { capabilities = ["read"] }\n' "$KV_PATH" | adm policy write svc-test - > /dev/null
adm auth enable approle > /dev/null
adm write auth/approle/role/svc-test token_ttl=1h token_policies=svc-test > /dev/null
adm write auth/approle/role/svc-test/role-id role_id="$ROLE_ID" > /dev/null
SID=$(adm write -f -field=secret_id auth/approle/role/svc-test/secret-id)
[ -n "$SID" ] || { echo "NOT RUN: could not mint a secret-id"; exit 2; }

# Synthetic values, one per backup key, plus a key backups must NOT receive.
seed_all() {
  adm kv put -mount=weown "$KV_PATH" POSTGRES_USER=u-test POSTGRES_DB=d-test \
    POSTGRES_PASSWORD=pg-pass-test SPACES_ACCESS_KEY=sp-access-test \
    SPACES_SECRET_KEY=sp-secret-test DJANGO_SECRET_KEY=dj-not-for-backups > /dev/null
}
seed_all

# --- the droplet's /opt/<project>, as the deploy leaves it --------------------
sed 's#__BAO_ADDR_FILLED_AT_DEPLOY__#https://127.0.0.1:8200#' "$W/render/docker/entrypoint-bao.sh" > "$W/app/entrypoint-bao.sh"
cp "$W/render/scripts/bao-run.sh" "$W/app/bao-run.sh"
printf '%s' "$SID" > "$W/app/.bao-secret-id"
# backup.sh stand-in: records the backup keys it was started with.
cat > "$W/app/backup.sh" << 'SH'
#!/bin/sh
env | grep -E '^(POSTGRES|SPACES|DJANGO)_' | sort > /w/probe.env
echo PROBE-RAN
SH
chmod 0755 "$W/app/entrypoint-bao.sh" "$W/app/bao-run.sh" "$W/app/backup.sh"
chmod 0600 "$W/app/.bao-secret-id"
mkdir -p "$W/app/bao-state"; chmod 0777 "$W/app/bao-state"

# argv logger in front of the real bao.
cat > "$W/bao" << 'SH'
#!/bin/sh
printf '%s\n' "$*" >> /w/argv.log
exec /w/bao-real "$@"
SH
chmod 0755 "$W/bao"

docker run --rm "$RUN_IMAGE" true > /dev/null 2>&1 || { echo "NOT RUN: cannot run $RUN_IMAGE"; exit 2; }
TOOLS=$(docker run -d --network "container:$BAO" -v "$W:/w" -v "$W/app:$APP" "$RUN_IMAGE" sleep 600) \
  || { echo "NOT RUN: tool container did not start"; exit 2; }
docker exec "$TOOLS" sh -c 'apk add -q --no-cache bash > /dev/null && ln -sf /w/bao /usr/bin/bao && mkdir -p /var/log' \
  || { echo "NOT RUN: could not add bash to the tool container"; exit 2; }

LOG=/var/log/billing_test-backup.log
run_cron() {  # -> rc returned; elapsed seconds in $ELAPSED
  rm -f "$W/probe.env"; : > "$W/argv.log"; chmod 0666 "$W/argv.log"
  docker exec "$TOOLS" sh -c ": > $LOG"
  local t0; t0=$(date +%s)
  docker exec "$TOOLS" bash /w/cron.sh > /dev/null 2>&1
  local rc=$?
  ELAPSED=$(( $(date +%s) - t0 ))
  docker exec "$TOOLS" cat "$LOG" >> "$W/alllog"
  cat "$W/argv.log" >> "$W/allargv"
  return $rc
}
logins() { grep -c 'auth/approle/login' "$W/argv.log"; }
: > "$W/alllog"; : > "$W/allargv"

echo "== B1. every key in the store: the backup runs with exactly the backup keys"
run_cron; rc=$?
res "$rc" 0 "B1 cron exits 0"
res "$(docker exec "$TOOLS" grep -c PROBE-RAN $LOG)" 1 "B1 backup.sh ran, its output in the backup log"
res "$(tr '\n' ' ' < "$W/probe.env" 2> /dev/null)" \
  "POSTGRES_DB=d-test POSTGRES_PASSWORD=pg-pass-test POSTGRES_USER=u-test SPACES_ACCESS_KEY=sp-access-test SPACES_SECRET_KEY=sp-secret-test " \
  "B1 the five backup keys, seeded values, and nothing else from the document"

echo "== B2. a backup key missing from the store: refused, backup.sh never runs"
adm kv put -mount=weown "$KV_PATH" POSTGRES_USER=u-test POSTGRES_DB=d-test \
  POSTGRES_PASSWORD=pg-pass-test SPACES_ACCESS_KEY=sp-access-test > /dev/null
run_cron; rc=$?
res "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)" nonzero "B2 cron fails"
res "$([ -f "$W/probe.env" ] && echo ran || echo not-run)" not-run "B2 backup.sh did not run"
res "$(docker exec "$TOOLS" grep -c 'key SPACES_SECRET_KEY is missing' $LOG)" 1 "B2 the log names the missing key"
res "$([ "$ELAPSED" -lt 15 ] && echo fast || echo "slow ${ELAPSED}s")" fast "B2 fails at once"
seed_all

echo "== B3. a secret-id the store rejects: one login attempt, no cooldown, refusal recorded"
printf 'not-a-valid-secret-id' > "$W/app/.bao-secret-id"
run_cron; rc=$?
res "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)" nonzero "B3 cron fails"
res "$([ -f "$W/probe.env" ] && echo ran || echo not-run)" not-run "B3 backup.sh did not run"
res "$(logins)" 1 "B3 exactly one login attempt"
res "$([ "$ELAPSED" -lt 15 ] && echo fast || echo "slow ${ELAPSED}s")" fast "B3 no cooldown sleep"
res "$([ -s "$W/app/bao-state/login-refused" ] && echo recorded || echo none)" recorded "B3 the refusal is recorded"

echo "== B3b. while a refusal is recorded, nothing logs in, even with a good secret-id"
printf '%s' "$SID" > "$W/app/.bao-secret-id"
run_cron; rc=$?
res "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)" nonzero "B3b cron fails"
res "$(logins)" 0 "B3b zero login attempts"
res "$(docker exec "$TOOLS" grep -c 'refused this secret-id earlier' $LOG)" 1 "B3b the log says why"
rm -f "$W/app/bao-state/login-refused"   # what the deploy does once the secret-id is valid
run_cron; rc=$?
res "$rc" 0 "B3b after the deploy clears it, the backup runs again"

echo "== B4. no credential value on a bao argv or in the backup log"
leaks=0
for v in "$SID" pg-pass-test sp-access-test sp-secret-test dj-not-for-backups; do
  grep -qF -- "$v" "$W/allargv" && leaks=$((leaks + 1))
  grep -qF -- "$v" "$W/alllog" && leaks=$((leaks + 1))
done
res "$leaks" 0 "B4 none of 5 values in $(wc -l < "$W/allargv" | tr -d ' ') logged bao calls or the backup log"

echo "== B5. remote storage: Spaces keys only for do-spaces; the unimplemented s3 is refused"
render "$W/render-none" --data backup_remote_storage=none || { echo "NOT RUN: none render failed"; exit 2; }
res "$(grep -c SPACES_ "$W/render-none/scripts/bao-run.sh")" 0 "B5 none render: no SPACES_ key requested"
res "$(grep -c 'SPACES_ACCESS_KEY SPACES_SECRET_KEY' "$W/render/scripts/bao-run.sh")" 1 "B5 do-spaces render requests both"
render "$W/render-s3" --data backup_remote_storage=s3; rc=$?
res "$([ "$rc" -ne 0 ] && echo refused || echo rendered)" refused "B5 s3 render is refused"

echo "== B6. the real backup.sh: password on stdin, no value on any argv, owner-only files"
# The rendered backup.sh runs through the cron as on the droplet; docker and
# aws are stubs that log their argv, and the dump step's stdin is kept.
cp "$W/render/scripts/backup.sh" "$W/render/scripts/lib.sh" "$W/app/"
: > "$W/app/Caddyfile"; : > "$W/app/compose.yaml"
cat > "$W/docker" << 'SH'
#!/bin/sh
printf '%s\n' "$*" >> /w/tool-argv.log
case "$1" in
  exec) cat > /w/dump.stdin; echo "-- synthetic dump" ;;
esac
exit 0
SH
cat > "$W/aws" << 'SH'
#!/bin/sh
printf '%s\n' "$*" >> /w/tool-argv.log
case "$2" in
  cp) wc -c < "$3" | tr -d ' ' > /w/aws.size ;;
  ls) echo "2026-01-01 00:00:00 $(cat /w/aws.size) x.tar.gz" ;;
esac
SH
chmod 0755 "$W/docker" "$W/aws" "$W/app/backup.sh"
: > "$W/tool-argv.log"; chmod 0666 "$W/tool-argv.log"
docker exec "$TOOLS" sh -c 'apk add -q --no-cache coreutils > /dev/null && ln -sf /w/docker /usr/bin/docker && ln -sf /w/aws /usr/bin/aws' \
  || { echo "NOT RUN: could not set up B6 stubs"; exit 2; }
run_cron; rc=$?
res "$rc" 0 "B6 cron exits 0"
res "$(docker exec "$TOOLS" grep -c 'Remote backup verified' $LOG)" 1 "B6 the backup reached the (stubbed) bucket"
res "$(tr -d '\n' < "$W/dump.stdin" 2> /dev/null)" pg-pass-test "B6 pg_dump got the password on stdin"
leaks=0
for v in "$SID" pg-pass-test sp-access-test sp-secret-test; do grep -qF -- "$v" "$W/tool-argv.log" && leaks=$((leaks + 1)); done
res "$leaks" 0 "B6 no value in $(wc -l < "$W/tool-argv.log" | tr -d ' ') docker/aws calls"
res "$(docker exec "$TOOLS" sh -c "stat -c '%a' $APP/backups/billing-test_backup_*.tar.gz $APP/backups | sort -u | tr '\n' ' '")" "600 700 " "B6 archive 0600, backup dir 0700"

echo "== B7. db and web opt in to the refusal file (compose)"
"$PY" - "$W/render/docker/compose.prod.yaml" > "$W/b7.out" << 'PY'
import sys, yaml
svc = yaml.safe_load(open(sys.argv[1]))["services"]
for name in ("db", "web"):
    env = svc[name].get("environment") or {}
    vols = svc[name].get("volumes") or []
    ok = env.get("BAO_LOGIN_REFUSED_FILE") == "/bao-state/login-refused" and any(str(v).endswith("/bao-state:/bao-state") for v in vols)
    print(name, "yes" if ok else "no")
PY
res "$(tr '\n' ' ' < "$W/b7.out")" "db yes web yes " "B7 db and web set BAO_LOGIN_REFUSED_FILE and mount bao-state"

echo "== B8. restore takes only a backup name of the shape backup.sh makes; ssh is never reached otherwise"
mkdir -p "$W/stub"
printf '#!/bin/sh\necho called >> %s/ssh.calls\n' "$W" > "$W/stub/ssh"; chmod 0755 "$W/stub/ssh"
rst() { : > "$W/ssh.calls"; (cd "$W/render" && PATH="$W/stub:$PATH" bash scripts/restore.sh root@192.0.2.1 "$1" > /dev/null 2>&1); echo "rc=$? ssh=$(wc -l < "$W/ssh.calls" | tr -d ' ')"; }
res "$(rst 'billing-test_backup_20260101_000000"; touch /tmp/x; "')" "rc=1 ssh=0" "B8 a quote-carrying name is refused before ssh"
res "$(rst '../../etc/passwd')" "rc=1 ssh=0" "B8 a path is refused"
res "$(rst 's3://other-bucket/billing-test/billing-test_backup_20260101_000000.tar.gz')" "rc=1 ssh=0" "B8 another bucket is refused"
res "$(rst 'billing-test_backup_20260101_000000')" "rc=0 ssh=1" "B8 a real backup name reaches ssh"

echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
