#!/usr/bin/env bash
# Behaviour test of a site's first-boot rotation (rotate-bootstrap-secret.sh in its
# cloud-init), against gitea-runner-docker/tests/stub_infisical.py (the same stand-in
# for Infisical's Universal Auth API and DigitalOcean's metadata service that the
# runner's own rotation-check.sh uses). The script is the one terraform would render
# (tofu templatefile, synthetic values); only its Infisical host, metadata URL and
# paths are pointed at the stub. Scenarios run inside a pinned Ubuntu 24.04 image
# (the droplet's bash, coreutils, curl and jq 1.7).
#
# Every scenario's expected outcome is derived from what the rotation must guarantee,
# not from the script's output: .rotation-complete exists ONLY when a login with v1
# is refused with 401 "Invalid credentials", and no secret or token ever reaches the
# log or a curl argv. Scenario W is the case "the oldest non-v2 secret is v1" got
# wrong: another, older client secret is still active, and v1 must die anyway.
# P: the proof logs in with the bootstrap client id from user_data, not the auth
# file's. J2: an empty marker (the old script's) is not taken as proof.
#
# usage: gitea-docker/tests/rotation-check.sh <site-dir>   e.g. gitea-docker/sites/git
#        (or a copier render of gitea-docker/template)
# Exit: 0 pass · 1 mismatch · 2 not run.
set -uo pipefail

# Ubuntu 24.04 with bash, curl, jq 1.7 and python3: the runner's pinned job image.
IMAGE=gitea/runner-images:ubuntu-24.04-v26.10.01@sha256:0e62e56b382ebf485bff1e51a05cbe27c708545a2e91425467fd31eb3e249521

if [ "${1:-}" != --inner ]; then
  SITE=$(cd "${1:?usage: $0 <site-dir>}" && pwd) || exit 2
  T=$(cd "$(dirname "$0")" && pwd)
  STUB_DIR=$(cd "$T/../../gitea-runner-docker/tests" && pwd) || exit 2
  [ -f "$STUB_DIR/stub_infisical.py" ] || { echo "NOT RUN: no $STUB_DIR/stub_infisical.py"; exit 2; }
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT
  command -v tofu > /dev/null || { echo "NOT RUN: tofu is not installed"; exit 2; }
  command -v docker > /dev/null || { echo "NOT RUN: docker is not installed"; exit 2; }
  # The project_name terraform passes to templatefile (hyphens already underscores).
  PROJECT=$(sed -n 's/^ *project_name *= *"\([a-z0-9_]*\)"$/\1/p' "$SITE/terraform/main.tf" | head -n 1)
  [ -n "$PROJECT" ] || { echo "NOT RUN: no project_name in $SITE/terraform/main.tf"; exit 2; }
  V1=v1aa-synthetic-bootstrap-0001
  printf 'templatefile("%s/terraform/templates/cloud-init.yaml", {project_name="%s", infisical_client_id="cid-123", infisical_client_secret="%s", infisical_project_id="pid-456", infisical_environment="prod"})\n' "$SITE" "$PROJECT" "$V1" \
    | (cd "$W" && tofu console) > "$W/raw.txt" 2>&1
  python3 - "$W" <<'PY' || { echo "NOT RUN: could not render the site's cloud-init"; head -c 600 "$W/raw.txt"; exit 2; }
import sys, re, pathlib, yaml
W = pathlib.Path(sys.argv[1])
m = re.search(r'<<EOT\n(.*)\nEOT', (W / "raw.txt").read_text(), re.S)
text = m.group(1)
files = {f["path"]: f["content"] for f in yaml.safe_load(text)["write_files"]}
app = next(p for p in files if p.endswith("/rotate-bootstrap-secret.sh")).rsplit("/", 1)[0]
(W / "rotate.sh").write_text(files[app + "/rotate-bootstrap-secret.sh"])
(W / "auth.env").write_text(files[app + "/.infisical-auth.env"])
(W / "userdata.txt").write_text(text)
(W / "app.txt").write_text(app)
PY
  docker run --rm -v "$W:/w" -v "$T:/t:ro" -v "$STUB_DIR:/s:ro" --entrypoint bash "$IMAGE" /t/rotation-check.sh --inner
  exit $?
fi

# ---------------------------------------------------------------- inside the image
W=/w
PORT=18765
APP_ON_BOX=$(cat $W/app.txt)
BAD=0
res() { if [ "$1" = "$2" ]; then echo "PASS     $3"; else echo "MISMATCH $3 (expected '$2', got '$1')"; BAD=1; fi; }

mkdir -p $W/bin
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %s/argv.log\nexec /usr/bin/curl "$@"\n' "$W" > $W/bin/curl
chmod +x $W/bin/curl

# Every path under the app dir moves to the scratch box, so a script that spells its
# paths out (no APP= line) is pointed at the stub as well as one that does not.
sed -e "s#^INFISICAL_HOST=\"https://app.infisical.com\"#INFISICAL_HOST=\"http://127.0.0.1:$PORT\"#" \
    -e "s#http://169.254.169.254/metadata/v1/user-data#http://127.0.0.1:$PORT/metadata/v1/user-data#" \
    -e "s#^LOG=/var/log/.*-rotation.log#LOG=$W/run/rotation.log#" \
    -e "s#$APP_ON_BOX#$W/run/app#g" $W/rotate.sh > $W/rotate-test.sh
for want in "INFISICAL_HOST=\"http://127.0.0.1:$PORT\"" "LOG=$W/run/rotation.log" "$W/run/app"; do
  grep -qF "$want" $W/rotate-test.sh || { echo "NOT RUN: could not point the script at the stub ($want)"; exit 2; }
done
for gone in "$APP_ON_BOX/" "169.254.169.254" "app.infisical.com"; do
  ! grep -qF "$gone" $W/rotate-test.sh || { echo "NOT RUN: the script still reaches $gone"; exit 2; }
done

echo '{"identity": "ident-1", "client_id": "cid-123", "tokens": [], "secrets": [], "userdata": ""}' > $W/state.json
python3 /s/stub_infisical.py $PORT $W/state.json 2> $W/stub.log &
STUB=$!
trap 'kill $STUB 2>/dev/null' EXIT

# state SECRETS_JSON [MODES_JSON]: a fresh identity with these client secrets
state() {
  python3 - "$1" "${2:-{\}}" <<'PY'
import json, sys
st = {"identity": "ident-1", "client_id": "cid-123", "tokens": [],
      "secrets": json.loads(sys.argv[1]), "userdata": open("/w/userdata.txt").read()}
st.update(json.loads(sys.argv[2]))
json.dump(st, open("/w/state.json", "w"))
PY
}
mode() { python3 -c 'import json,sys; s=json.load(open("/w/state.json")); s.update(json.loads(sys.argv[1])); json.dump(s, open("/w/state.json","w"))' "$1"; }
active() { python3 -c 'import json; print(",".join(s["id"] for s in json.load(open("/w/state.json"))["secrets"] if not s["revoked"]))'; }
revoked() { python3 -c 'import json,sys; print("yes" if [s for s in json.load(open("/w/state.json"))["secrets"] if s["id"]==sys.argv[1]][0]["revoked"] else "no")' "$1"; }
count() { python3 -c 'import json; print(len(json.load(open("/w/state.json"))["secrets"]))'; }
value_of() { python3 -c 'import json,sys; print([s["value"] for s in json.load(open("/w/state.json"))["secrets"] if s["id"]==sys.argv[1]][0])' "$1"; }
fresh_box() { rm -rf $W/run; mkdir -p $W/run/app; cp $W/auth.env $W/run/app/.infisical-auth.env; chmod 600 $W/run/app/.infisical-auth.env; : > $W/argv.log; }
run() { PATH="$W/bin:$PATH" bash $W/rotate-test.sh > /dev/null 2>&1; echo $?; }
live_secret() { sed -n 's/^INFISICAL_CLIENT_SECRET=//p' $W/run/app/.infisical-auth.env; }
marker() { [ -f $W/run/app/.rotation-complete ] && echo yes || echo no; }
# What ansible/deploy.yml accepts: a marker that names the proof ("v1-401 <time>").
proof() { grep -qs '^v1-401 ' $W/run/app/.rotation-complete && echo v1-401 || echo none; }
# No secret value and no token may appear in the log or on any curl argv.
leaks() {
  python3 - <<'PY'
import json
st = json.load(open("/w/state.json"))
needles = [s["value"] for s in st["secrets"]] + st["tokens"] + ["v1aa-synthetic-bootstrap-0001"]
hay = open("/w/argv.log").read() + open("/w/run/rotation.log").read()
print(sum(1 for n in needles if n and n in hay))
PY
}
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/metadata/v1/user-data" && break; sleep 0.1; done

V1_SECRET='{"id": "cs-v1", "value": "v1aa-synthetic-bootstrap-0001", "revoked": false, "createdAt": "2026-10-07T00:00:00Z"}'

echo "== A. first boot, identity may manage its secrets: v2 minted, v1 revoked and proven dead"
fresh_box; state "[$V1_SECRET]"
res "$(run)" 0 "A exits 0"
res "$(marker)" yes "A .rotation-complete written"
res "$(proof)" v1-401 "A the marker records the proof (what the deploy gate requires)"
res "$(active)" cs-2 "A only the minted v2 (cs-2) is active"
res "$(live_secret)" "$(value_of cs-2)" "A the auth file holds v2"
res "$(cat $W/run/app/.rotation-live-id 2>/dev/null)" cs-2 "A v2's id is recorded"
res "$(grep -c 'v1 refused: 401 Invalid credentials' $W/run/rotation.log)" 1 "A the log shows the 401 proof"
res "$(leaks)" 0 "A no secret or token in the log or on curl argv"

echo "== W. another, OLDER client secret is active: v1 must still be the one proven dead"
# The identity is this droplet's alone (README prerequisites), so every active secret
# but the live v2 is revoked, the older one included; what must never happen is a
# marker while v1 still logs in.
fresh_box; state "[{\"id\": \"cs-old\", \"value\": \"oldx-synthetic-0006\", \"revoked\": false, \"createdAt\": \"2026-10-06T00:00:00Z\"}, $V1_SECRET]"
res "$(run)" 0 "W exits 0"
res "$(revoked cs-v1)" yes "W v1 (cs-v1) is revoked, not mistaken for the older secret"
res "$(marker)/$(revoked cs-v1)" yes/yes "W .rotation-complete only with v1 dead"
res "$(active)" cs-3 "W only the minted v2 (cs-3) is active"
res "$(grep -c 'v1 refused: 401 Invalid credentials' $W/run/rotation.log)" 1 "W the log shows the 401 proof"
res "$(leaks)" 0 "W no secret or token in the log or on curl argv"

echo "== B. the identity may not create client secrets: nothing changes, no marker"
fresh_box; state "[$V1_SECRET]" '{"can_mint": false}'
res "$(run)" 0 "B exits 0 (cloud-init must not block)"
res "$(marker)" no "B no .rotation-complete"
res "$(live_secret)" v1aa-synthetic-bootstrap-0001 "B the auth file still holds v1"
res "$(active)" cs-v1 "B v1 is still the only active secret"
res "$(grep -c 'ROTATION FAILED: minting v2 answered 403' $W/run/rotation.log)" 1 "B the log says why"
res "$(grep -c "README 'Manual bootstrap-secret rotation'" $W/run/rotation.log)" 1 "B the log names a README section that exists"

echo "== C. revoking fails after v2 is swapped in; a rerun finishes it without minting again"
fresh_box; state "[$V1_SECRET]" '{"revoke_fails": true}'
res "$(run)" 0 "C1 exits 0"
res "$(marker)" no "C1 no .rotation-complete while v1 lives"
res "$(active)" cs-v1,cs-2 "C1 v1 and v2 both active"
res "$(live_secret)" "$(value_of cs-2)" "C1 the auth file holds v2"
mode '{"revoke_fails": false}'
res "$(run)" 0 "C2 rerun exits 0"
res "$(marker)" yes "C2 rerun: .rotation-complete written"
res "$(active)" cs-2 "C2 rerun: only v2 active"
res "$(count)" 2 "C2 rerun minted nothing new"
res "$(leaks)" 0 "C no secret or token in the log or on curl argv"

echo "== D. an orphan v2 from an interrupted earlier run is revoked too"
fresh_box; state "[$V1_SECRET, {\"id\": \"cs-orphan\", \"value\": \"orph-synthetic-0002\", \"revoked\": false, \"createdAt\": \"2026-10-07T00:00:01Z\"}]"
res "$(run)" 0 "D exits 0"
res "$(marker)" yes "D .rotation-complete written"
res "$(active)" cs-3 "D only the new v2 (cs-3) is active: v1 and the orphan revoked"

echo "== E. the client id locks out mid-run: the proof's 401 is the lockout, not 'Invalid credentials'"
fresh_box; state "[$V1_SECRET]" '{"lock_after_revoke": true}'
res "$(run)" 0 "E exits 0"
res "$(marker)" no "E no .rotation-complete: a lockout 401 proves nothing"
res "$(grep -c 'not 401 Invalid credentials' $W/run/rotation.log)" 1 "E the log says the proof failed"

echo "== F. the revoke API says 'revoked' but the secret stays active"
fresh_box; state "[$V1_SECRET]" '{"revoke_lies": true}'
res "$(run)" 0 "F exits 0"
res "$(marker)" no "F no .rotation-complete"
res "$(grep -c "active client secrets after revoking: 'cs-v1,cs-2'" $W/run/rotation.log)" 1 "F the recount caught it"

echo "== G. a human swapped in v2 (rotate-mi-manual.sh); v1 not yet revoked, then revoked"
fresh_box; state "[$V1_SECRET, {\"id\": \"cs-h\", \"value\": \"hum2-synthetic-0003\", \"revoked\": false, \"createdAt\": \"2026-10-07T00:00:02Z\"}]" '{"can_mint": false}'
sed -i 's/^INFISICAL_CLIENT_SECRET=.*/INFISICAL_CLIENT_SECRET=hum2-synthetic-0003/' $W/run/app/.infisical-auth.env
res "$(run)" 0 "G1 exits 0"
res "$(marker)" no "G1 no .rotation-complete while v1 still logs in"
res "$(active)" cs-v1,cs-h "G1 the script revoked nothing it cannot identify"
mode '{"secrets": [{"id": "cs-v1", "value": "v1aa-synthetic-bootstrap-0001", "revoked": true, "createdAt": "2026-10-07T00:00:00Z"}, {"id": "cs-h", "value": "hum2-synthetic-0003", "revoked": false, "createdAt": "2026-10-07T00:00:02Z"}]}'
res "$(run)" 0 "G2 --verify rerun exits 0"
res "$(marker)" yes "G2 .rotation-complete once v1 is revoked"
res "$(live_secret)" hum2-synthetic-0003 "G2 the human's v2 is untouched"

echo "== H. a recorded id that is not the live secret: revoke nothing"
fresh_box; state "[$V1_SECRET, {\"id\": \"cs-2\", \"value\": \"live-synthetic-0004\", \"revoked\": false, \"createdAt\": \"2026-10-07T00:00:01Z\"}, {\"id\": \"cs-x\", \"value\": \"othr-synthetic-0005\", \"revoked\": false, \"createdAt\": \"2026-10-07T00:00:02Z\"}]"
sed -i 's/^INFISICAL_CLIENT_SECRET=.*/INFISICAL_CLIENT_SECRET=live-synthetic-0004/' $W/run/app/.infisical-auth.env
echo cs-x > $W/run/app/.rotation-live-id
res "$(run)" 0 "H exits 0"
res "$(marker)" no "H no .rotation-complete"
res "$(active)" cs-v1,cs-2,cs-x "H nothing revoked (the live secret survives)"

echo "== I. the metadata service does not answer: v1 cannot be read, no marker"
fresh_box; state "[$V1_SECRET]" '{"metadata_up": false}'
res "$(run)" 0 "I exits 0"
res "$(marker)" no "I no .rotation-complete"
res "$(active)" cs-v1 "I nothing minted or revoked"

echo "== K. the swap fails after v2 is written: the v2 temp file is not left behind"
mkdir -p $W/bin-mvfail
printf '#!/bin/sh\nexit 1\n' > $W/bin-mvfail/mv
chmod +x $W/bin-mvfail/mv
fresh_box; state "[$V1_SECRET]"
res "$(PATH="$W/bin-mvfail:$W/bin:$PATH" bash $W/rotate-test.sh > /dev/null 2>&1; echo $?)" 0 "K exits 0"
res "$(marker)" no "K no .rotation-complete"
res "$(live_secret)" v1aa-synthetic-bootstrap-0001 "K the auth file still holds v1"
res "$(find $W/run/app -name '.infisical-auth.env.*' | wc -l | tr -d ' ')" 0 "K no temp auth file (holding v2) left on disk"

echo "== P. the auth file names another client id: the proof uses the bootstrap pair from user_data"
# The droplet was re-pointed by hand at identity cid-new (where a v1-valued secret is
# revoked), while the bootstrap identity cid-123 still accepts v1. Logging in with v1
# under cid-new would answer 401 "Invalid credentials" and prove nothing about cid-123.
fresh_box
state "[{\"id\": \"cs-v1\", \"value\": \"v1aa-synthetic-bootstrap-0001\", \"revoked\": true, \"createdAt\": \"2026-10-07T00:00:00Z\"}, {\"id\": \"cs-h\", \"value\": \"hum2-synthetic-0003\", \"revoked\": false, \"createdAt\": \"2026-10-07T00:00:02Z\"}]" \
  '{"client_id": "cid-new", "other_clients": {"cid-123": ["v1aa-synthetic-bootstrap-0001"]}}'
sed -i -e 's/^INFISICAL_CLIENT_ID=.*/INFISICAL_CLIENT_ID=cid-new/' -e 's/^INFISICAL_CLIENT_SECRET=.*/INFISICAL_CLIENT_SECRET=hum2-synthetic-0003/' $W/run/app/.infisical-auth.env
res "$(run)" 0 "P exits 0"
res "$(marker)" no "P no .rotation-complete while the bootstrap pair (cid-123, v1) still logs in"
res "$(grep -c 'v1 login answered 200' $W/run/rotation.log)" 1 "P the log says v1 still logs in"

echo "== J. already proven: a rerun changes nothing"
fresh_box; state "[$V1_SECRET]"; echo "v1-401 2026-10-07T00:00:09+00:00" > $W/run/app/.rotation-complete
res "$(run)" 0 "J exits 0"
res "$(active)" cs-v1 "J no API call changed anything"
res "$(wc -l < $W/argv.log | tr -d ' ')" 0 "J no request was made"

echo "== J2. an EMPTY marker (what the pre-#163 script wrote whatever happened) is not trusted"
fresh_box; state "[$V1_SECRET]"; touch $W/run/app/.rotation-complete
res "$(run)" 0 "J2 exits 0"
res "$(proof)" v1-401 "J2 the run proved v1 dead and recorded it"
res "$(active)" cs-2 "J2 v1 revoked; only the minted v2 (cs-2) is active"

exit "$BAD"
