#!/usr/bin/env bash
# entrypoint-bao-check.sh — behaviour test of billing-docker's OpenBao entrypoint
# (template/docker/...entrypoint-bao.sh.jinja) against a REAL OpenBao dev server.
#
# Synthetic values only, in a throwaway dev store; nothing leaves this machine.
# The entrypoint is rendered from the template with sed (it uses exactly three
# template expressions), its store URL is filled in as the deploy would, and it
# runs in the images billing uses: postgres:16 (--keys) and python:3.12-slim
# (--document). Each container shares the dev server's network namespace, so the
# dev server's generated CA (valid for 127.0.0.1) verifies.
#
# Every expected outcome is stated from what the entrypoint must guarantee, not
# read back from its output: the app gets exactly the stored values (quotes and
# newlines intact), a missing or hostile key refuses the start before the command
# runs, a wrong credential is retried a bounded number of times and never runs
# the command, the login token is revoked, and the secret-id never reaches argv.
#
#   billing-docker/tests/entrypoint-bao-check.sh
# Exit: 0 pass · 1 mismatch · 2 not run.
set -uo pipefail

BAO_IMAGE=quay.io/openbao/openbao:2.7.0
PG_IMAGE=postgres:16
PY_IMAGE=python:3.12-slim
ROLE_ID=role-test-123

T=$(cd "$(dirname "$0")/.." && pwd)
# The template's file name contains "}", so it cannot sit inside ${...:-...}.
DEFAULT_SRC="$T/template/docker/{% if secret_backend == 'openbao' %}entrypoint-bao.sh{% endif %}.jinja"
SRC="${ENTRYPOINT_SRC:-$DEFAULT_SRC}"
[ -f "$SRC" ] || { echo "NOT RUN: $SRC missing"; exit 2; }
command -v docker > /dev/null || { echo "NOT RUN: docker is not installed"; exit 2; }

W=$(mktemp -d)
BAO=ebcheck-bao-$$
cleanup() { docker rm -f "$BAO" > /dev/null 2>&1; find "$W" -delete 2> /dev/null; }
trap cleanup EXIT
PASS=0; FAIL=0
res() { if [ "$1" = "$2" ]; then echo "PASS     $3"; PASS=$((PASS + 1)); else echo "MISMATCH $3 (expected '$2', got '$1')"; FAIL=$((FAIL + 1)); fi; }

render() {  # render <secret_path> <out>
  sed -e 's/{{ project_name }}/weown-billing/g' -e "s/{{ bao_role_id }}/$ROLE_ID/g" \
      -e "s#{{ bao_secret_path }}#$1#g" \
      -e 's#__BAO_ADDR_FILLED_AT_DEPLOY__#https://127.0.0.1:8200#' "$SRC" > "$2"
  if grep -q -E '\{\{|\{%' "$2"; then echo "NOT RUN: unrendered template expression in $2"; exit 2; fi
  chmod 0755 "$2"
}
render platform/billing "$W/e-billing.sh"
render platform/hostile1 "$W/e-hostile1.sh"
render platform/hostile2 "$W/e-hostile2.sh"
cp "$W/e-billing.sh" "$W/e-unfilled.sh"
sed -i.bak 's#^BAO_ADDR="https://127.0.0.1:8200"#BAO_ADDR="__BAO_ADDR_FILLED_AT_DEPLOY__"#' "$W/e-unfilled.sh"

# --- the dev store ----------------------------------------------------------
docker run -d --name "$BAO" --cap-add=IPC_LOCK --tmpfs /certs:mode=1777 "$BAO_IMAGE" \
  bao server -dev -dev-tls -dev-tls-cert-dir=/certs -dev-root-token-id=root \
  -dev-listen-address=127.0.0.1:8200 > /dev/null || { echo "NOT RUN: dev server did not start"; exit 2; }
for _ in $(seq 30); do docker exec "$BAO" sh -c 'ls /certs/*ca*.pem' > /dev/null 2>&1 && break; sleep 1; done
CA=$(docker exec "$BAO" sh -c 'ls /certs/*ca*.pem 2>/dev/null | head -1')
[ -n "$CA" ] || { echo "NOT RUN: no dev CA in /certs"; exit 2; }
# docker cp cannot read a tmpfs mount; cat can.
docker exec "$BAO" cat "$CA" > "$W/ca.pem"
[ -s "$W/ca.pem" ] || { echo "NOT RUN: could not read the dev CA"; exit 2; }
docker cp "$BAO:/usr/bin/bao" "$W/bao-real" > /dev/null
adm() { docker exec -i -e BAO_ADDR=https://127.0.0.1:8200 -e BAO_CACERT="$CA" -e BAO_TOKEN=root "$BAO" bao "$@"; }
for _ in $(seq 30); do adm status > /dev/null 2>&1 && break; sleep 1; done
adm secrets enable -path=weown kv-v2 > /dev/null
adm auth enable approle > /dev/null
printf 'path "weown/data/platform/*" { capabilities = ["read"] }\n' | adm policy write svc-test - > /dev/null
adm write auth/approle/role/svc-test token_policies=svc-test token_ttl=1h > /dev/null
adm write auth/approle/role/svc-test/role-id role_id="$ROLE_ID" > /dev/null
adm write -f -field=secret_id auth/approle/role/svc-test/secret-id > "$W/sid"
[ -s "$W/sid" ] || { echo "NOT RUN: could not mint a secret-id"; exit 2; }
echo "not-a-valid-secret-id" > "$W/sid-wrong"
: > "$W/sid-empty"

# Values chosen to break naive quoting: a quote of each kind, a $, a backslash,
# a newline, and a value that looks like shell.
PW='p'"'"'w"$x\y'
SK=$'line one\nline two'
adm kv put -mount=weown platform/billing POSTGRES_DB=billingdb POSTGRES_USER=billing \
  POSTGRES_PASSWORD="$PW" DJANGO_SECRET_KEY="$SK" STRIPE_PRICE_ID='$(touch /tmp/pwned)' > /dev/null
# The NAME carries the payload: bao splits key=value at the first '='.
adm kv put -mount=weown platform/hostile1 'A;touch /tmp/pwned;B=1' > /dev/null
adm kv put -mount=weown platform/hostile2 PYTHONSTARTUP=/tmp/evil.py OK_KEY=1 > /dev/null

# argv logger: a `bao` that records its arguments, then runs the real one.
cat > "$W/bao" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> /w/argv.log
exec /w/bao-real "$@"
SH
chmod 0755 "$W/bao"
: > "$W/argv.log"; chmod 0666 "$W/argv.log"

run() {  # run <image> <entrypoint> <sid-file> <entrypoint args...>
  local img=$1 ep=$2 sid=$3; shift 3
  docker run --rm --network "container:$BAO" -v "$W:/w" \
    -v "$W/$ep:/entrypoint-bao.sh:ro" -v "$W/ca.pem:/.bao-ca.crt:ro" -v "$W/$sid:/.bao-secret-id:ro" \
    -v "$W/bao:/usr/bin/bao:ro" -e BAO_LOGIN_COOLDOWN=1 \
    --entrypoint /entrypoint-bao.sh "$img" "$@"
}
# Expected digests, derived from the literal inputs above (never from the
# entrypoint's output), in a separate container.
EXPECT=$(docker run --rm "$PY_IMAGE" python3 -c 'import hashlib,json,sys
pw, sk = sys.argv[1], sys.argv[2]
h = lambda x, n: hashlib.sha256(x.encode()).hexdigest()[:n]
v = {"POSTGRES_DB": "billingdb", "POSTGRES_USER": "billing", "POSTGRES_PASSWORD": pw, "DJANGO_SECRET_KEY": sk, "STRIPE_PRICE_ID": "$(touch /tmp/pwned)"}
print("billingdb|billing|" + h(pw, 16))
print(json.dumps({k: h(x, 12) for k, x in v.items()}, sort_keys=True))' "$PW" "$SK")
WANT_A=$(echo "$EXPECT" | sed -n 1p)
WANT_C=$(echo "$EXPECT" | sed -n 2p)
[ -n "$WANT_A" ] && [ -n "$WANT_C" ] || { echo "NOT RUN: could not compute the expected values"; exit 2; }
tokens() { adm list -format=json auth/token/accessors 2> /dev/null | tr -d '[] \n' | tr ',' '\n' | grep -c . ; }

echo "== A. --keys in postgres:16: exactly the listed values reach the command"
before=$(tokens)
out=$(run "$PG_IMAGE" e-billing.sh sid --keys "POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD" -- \
  sh -c 'printf "%s|%s|" "$POSTGRES_DB" "$POSTGRES_USER"; printf "%s" "$POSTGRES_PASSWORD" | sha256sum | cut -c1-16; echo "stripe=${STRIPE_PRICE_ID:-unset}"' 2>/dev/null); rc=$?
res "$rc" 0 "A exits 0"
res "$(echo "$out" | head -1)" "$WANT_A" "A db, user and the quote-laden password arrive intact"
res "$(echo "$out" | grep -o 'stripe=.*')" "stripe=unset" "A an unlisted key is NOT exported"
res "$(tokens)" "$before" "A the login token is revoked (accessor count unchanged)"

echo "== B. --keys with a key the document lacks: refused, command never runs"
out=$(run "$PG_IMAGE" e-billing.sh sid --keys "POSTGRES_DB NOPE_KEY" -- sh -c 'touch /w/ran-B' 2>&1); rc=$?
res "$([ "$rc" -ne 0 ] && echo refused || echo ran)" refused "B exits non-zero"
res "$([ -e "$W/ran-B" ] && echo yes || echo no)" no "B the command did not run"
res "$(echo "$out" | grep -c 'NOPE_KEY is missing')" 1 "B names the missing key"

echo "== C. --document in python:3.12-slim: every key, values exact"
out=$(run "$PY_IMAGE" e-billing.sh sid --document -- python3 -c 'import os,hashlib,json
k=["POSTGRES_DB","POSTGRES_USER","POSTGRES_PASSWORD","DJANGO_SECRET_KEY","STRIPE_PRICE_ID"]
print(json.dumps({x: hashlib.sha256(os.environ[x].encode()).hexdigest()[:12] for x in k}, sort_keys=True))' 2>&1); rc=$?
res "$rc" 0 "C exits 0"
res "$(echo "$out" | tail -1)" "$WANT_C" "C quotes, \$, backslash, newline and a \$(...) value all arrive byte-exact"

echo "== D. --document with a hostile key NAME: refused, nothing runs"
out=$(run "$PY_IMAGE" e-hostile1.sh sid --document -- sh -c 'touch /w/ran-D' 2>&1); rc=$?
res "$([ "$rc" -ne 0 ] && echo refused || echo ran)" refused "D exits non-zero"
res "$([ -e "$W/ran-D" ] && echo yes || echo no)" no "D the command did not run"
res "$(echo "$out" | grep -c 'not a plain identifier')" 1 "D says why, without printing the name"
res "$(echo "$out" | grep -c 'touch /tmp/pwned')" 0 "D the hostile name is not echoed"

echo "== E. --document with PYTHONSTARTUP: refused (it would make python run code)"
out=$(run "$PY_IMAGE" e-hostile2.sh sid --document -- sh -c 'touch /w/ran-E' 2>&1); rc=$?
res "$([ "$rc" -ne 0 ] && [ ! -e "$W/ran-E" ] && echo refused || echo ran)" refused "E refused before the command"

echo "== F. wrong secret-id: bounded retries, then refuse; command never runs"
out=$(run "$PG_IMAGE" e-billing.sh sid-wrong --keys "POSTGRES_DB" -- sh -c 'touch /w/ran-F' 2>&1); rc=$?
res "$([ "$rc" -ne 0 ] && echo refused || echo ran)" refused "F exits non-zero"
res "$([ -e "$W/ran-F" ] && echo yes || echo no)" no "F the command did not run"
res "$(echo "$out" | grep -c 'login failed (attempt')" 2 "F two retries announced (3 attempts in all)"
res "$(echo "$out" | grep -c 'FAILED after 3 attempts')" 1 "F says it gave up after 3"

echo "== G. empty secret-id file: refused at once"
out=$(run "$PG_IMAGE" e-billing.sh sid-empty --keys "POSTGRES_DB" -- sh -c 'touch /w/ran-G' 2>&1); rc=$?
res "$([ "$rc" -ne 0 ] && [ ! -e "$W/ran-G" ] && echo refused || echo ran)" refused "G refused"
res "$(echo "$out" | grep -c 'is empty')" 1 "G says the file is empty"

echo "== H. a copy whose store URL was never filled in refuses to start"
out=$(run "$PG_IMAGE" e-unfilled.sh sid --keys "POSTGRES_DB" -- sh -c 'touch /w/ran-H' 2>&1); rc=$?
res "$([ "$rc" -ne 0 ] && [ ! -e "$W/ran-H" ] && echo refused || echo ran)" refused "H refused"

echo "== I. --document in an image without python3: refused with the reason"
out=$(run "$PG_IMAGE" e-billing.sh sid --document -- sh -c 'touch /w/ran-I' 2>&1); rc=$?
res "$([ "$rc" -ne 0 ] && [ ! -e "$W/ran-I" ] && echo refused || echo ran)" refused "I refused"
res "$(echo "$out" | grep -c 'needs python3')" 1 "I names the missing python3"

echo "== J. the secret-id never reached a bao argv (every call above logged)"
res "$(grep -c -F -- "$(cat "$W/sid")" "$W/argv.log")" 0 "J secret-id absent from $(wc -l < "$W/argv.log" | tr -d ' ') logged bao calls"
res "$(grep -c 'secret_id=-' "$W/argv.log" | awk '{print ($1 > 0) ? "yes" : "no"}')" yes "J logins read the secret-id from stdin"
res "$([ -e /tmp/pwned ] || docker exec "$BAO" test -e /tmp/pwned 2>/dev/null && echo yes || echo no)" no "J no stored value or name was executed"

echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
