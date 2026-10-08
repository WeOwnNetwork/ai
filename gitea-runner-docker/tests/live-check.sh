#!/usr/bin/env bash
# live-check.sh — run a rendered gitea-runner-docker site's stack on local Docker
# BEFORE deploying it, especially after bumping an image pin:
#   0. the deploy's own "Save the job image" step (its shell, from ansible/deploy.yml),
#      and that a second deploy leaves the copy unchanged;
#   1. the runner cycle (scripts/runner-cycle.sh, as written, in the job image's Ubuntu
#      userland) against THAT copy: a fresh dind comes up healthy, the saved job image
#      loads under the label's tag, and what one job leaves behind (a container, a
#      volume) is gone in the next cycle's daemon;
#   2. the runner's path reaches dind over verified TLS (the pinned "dind" SAN);
#   3. a job with config.yaml's options drives dind with the job image's own docker
#      CLI, and a job without them cannot (the control);
#   4. the job image has node 24, python3 and apt;
#   5. act_runner parses config.yaml;
#   6. the credential boundary: only the one-shot `register` service mounts the
#      Infisical CLI and auth file, the job-handling `runner` mounts neither; the
#      wrapper registers with the auth file's project and env, passes no Machine
#      Identity credential on, and never calls Infisical once data/.runner exists; the
#      register command hands the token to act_runner on stdin, never argv (the real
#      act_runner accepts it that way);
#   7. the metadata probe (the deploy task's own shell): a refused connection is
#      BLOCKED, the forge is REACHED, and a timeout or a missing wget is neither;
#   8. token-gone.sh, the deploy's gate before the runner takes jobs: PRESENT=1 while
#      the token is in the project, PRESENT=0 once it is gone, CHECK_FAILED when it
#      cannot tell, and never the value; and the cycle refuses an unregistered box.
# Not covered (they need a real droplet): the DOCKER-USER rule itself, cloud-init's
# installs, and Infisical (tests/rotation-check.sh covers the rotation logic).
#
#   gitea-runner-docker/tests/live-check.sh [sites/<name>]   # default sites/weown-ci-runner
#
# No token, no forge write; it pulls the pinned images and reads the forge's
# /api/healthz. Exit: 0 pass · 1 mismatch · 2 not run.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SITE=$(cd "${1:-$HERE/../sites/weown-ci-runner}" && pwd) || { echo "NOT RUN: no site"; exit 2; }
COMPOSE=$SITE/docker/compose.prod.yaml
APP_ON_BOX=$(sed -n 's/^cd \(\/opt\/[a-z0-9_]*\)$/\1/p' "$SITE/scripts/runner-cycle.sh")
P=$(basename "$APP_ON_BOX")
CERTS=$(sed -n 's/^  \(.*_certs_client\):$/\1/p' "$COMPOSE")
DIND=$(sed -n 's/^    image: \(docker:.*\)$/\1/p' "$COMPOSE")
RUNNER=$(sed -n 's/^    image: \(gitea\/act_runner:.*\)$/\1/p' "$COMPOSE" | head -n 1)
JOB=$(sed -n 's/^    job_image: \(.*@sha256:[0-9a-f]*\)$/\1/p' "$SITE/ansible/deploy.yml")
TAG=$(sed -n 's/^    - "ubuntu-latest:docker:\/\/\(.*\)"$/\1/p' "$SITE/docker/config.yaml")
OPTS=$(sed -n 's/^  options: "\(.*\)"$/\1/p' "$SITE/docker/config.yaml")
FORGE=$(sed -n 's/^      GITEA_INSTANCE_URL: "\(.*\)"$/\1/p' "$COMPOSE")
BAD=0
res() { if [ "$1" = "$2" ]; then echo "PASS     $3"; else echo "MISMATCH $3 (expected '$2', got '$1')"; BAD=1; fi; }
for v in APP_ON_BOX CERTS DIND RUNNER JOB TAG OPTS FORGE; do
  [ -n "${!v}" ] || { echo "NOT RUN: could not read $v from the render"; exit 2; }
done
[ "${JOB%@*}" = "$TAG" ] || { echo "NOT RUN: config.yaml's label ($TAG) is not the job image's tag (${JOB%@*})"; exit 2; }
[ -e "$APP_ON_BOX" ] && { echo "NOT RUN: $APP_ON_BOX exists on this machine; refusing to touch it"; exit 2; }
# The cycle and the cleanup run `compose -p $P down -v` on THIS Docker: refuse if any
# container, volume or network already belongs to a compose project of that name.
for kind in container volume network; do
  if [ -n "$(docker "$kind" ls -q --filter "label=com.docker.compose.project=$P" 2>/dev/null)" ]; then
    echo "NOT RUN: this Docker already has a ${kind} in compose project '$P'; refusing to touch it"; exit 2
  fi
done
echo "dind=$DIND"; echo "job=$JOB"; echo "job options: $OPTS"

W=$(mktemp -d)
# shellcheck disable=SC2329  # invoked by the EXIT trap
cleanup() {
  docker compose -f "$W/app/compose.yaml" -p "$P" down -v > /dev/null 2>&1
  rm -rf "$W"
}
trap cleanup EXIT
mkdir -p "$W/app/images" "$W/app/data"
# Registered already: the cycle skips the one-shot `register` (it needs Infisical).
echo '{"id": 0}' > "$W/app/data/.runner"
cp "$COMPOSE" "$W/app/compose.yaml"
cp "$SITE/scripts/probe-url.sh" "$W/app/probe-url.sh"
cp "$SITE/scripts/token-gone.sh" "$W/app/token-gone.sh"
# runner-cycle.sh exactly as rendered, except its last line (the runner would register).
sed 's/^exec docker compose -f compose.yaml run --rm --no-deps -T runner$/echo CYCLE_READY/' \
  "$SITE/scripts/runner-cycle.sh" > "$W/app/runner-cycle.sh"
grep -q '^echo CYCLE_READY$' "$W/app/runner-cycle.sh" || { echo "NOT RUN: runner-cycle.sh's last line changed"; exit 2; }

# 0. The deploy's OWN save step: the task's shell from ansible/deploy.yml, its ansible
#    variables filled in, run in the job image's Ubuntu userland against this Docker,
#    with the app dir at its real path. (The pull before it is the deploy's pull task.)
docker pull -q "$JOB" > /dev/null || { echo "NOT RUN: could not pull $JOB"; exit 2; }
python3 - "$SITE/ansible/deploy.yml" "$APP_ON_BOX" "$JOB" "$TAG" > "$W/save-step.sh" <<'PY' || { echo "NOT RUN: no save task in deploy.yml"; exit 2; }
import sys, yaml
play = yaml.safe_load(open(sys.argv[1]))[0]
t = next(t for t in play["tasks"] if t["name"] == "Save the job image for runner-cycle.sh")
s = t["ansible.builtin.shell"]
for var, val in (("app_dir", sys.argv[2]), ("job_image_tag", sys.argv[4]), ("job_image", sys.argv[3])):
    s = s.replace("{{ %s }}" % var, val)
assert "{{" not in s, s
print(s)
PY
save() {
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$W/app:$APP_ON_BOX" \
    -v "$W/save-step.sh:/save-step.sh:ro" --entrypoint bash "$JOB" /save-step.sh 2>&1 | tail -n 1
}
res "$(save)" saved "the deploy's save step writes the job image copy and its checksum"
res "$(save)" unchanged "a second deploy finds the copy unchanged (checksum verifies from images/)"

# 1. one cycle, run by the job image's Ubuntu userland against this Docker, the app dir
#    mounted at its real path so compose names everything as on the droplet.
cycle() {
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$W/app:$APP_ON_BOX" \
    --entrypoint bash "$JOB" "$APP_ON_BOX/runner-cycle.sh" 2>&1 | tail -n 1
}
in_dind() { docker exec "$P-dind-1" "$@" 2>&1; }
res "$(cycle)" CYCLE_READY "cycle 1 on the deploy's copy: down -v, the checksum, a fresh dind (healthy), the job image loaded under its tag"
res "$(docker inspect -f '{{.State.Health.Status}}' "$P-dind-1" 2>&1)" healthy "the cycle's dind is healthy"
# A job leaves things behind in its daemon ...
in_dind docker volume create leftover-volume > /dev/null
in_dind docker run -d --name leftover-container "$TAG" sleep 600 > /dev/null
res "$(in_dind docker ps -q --filter name=leftover-container | wc -l | tr -d ' ')" 1 "CONTROL: a job's container is running in cycle 1's daemon"
# ... and the next cycle's daemon has none of it.
res "$(cycle)" CYCLE_READY "cycle 2 ran"
res "$(in_dind docker ps -aq | wc -l | tr -d ' ')" 0 "cycle 2's daemon has no containers left from cycle 1"
res "$(in_dind docker volume ls -q | grep -c leftover-volume)" 0 "cycle 2's daemon has no volume left from cycle 1"
res "$(in_dind docker image inspect -f ok "$TAG")" ok "cycle 2's daemon has the job image again, under the label's tag"
# A tampered copy stops the cycle before anything runs.
cp "$W/app/images/job-image.tar.sha256" "$W/sha.keep"
printf '%064d  job-image.tar\n' 0 > "$W/app/images/job-image.tar.sha256"
res "$(cycle | grep -c CYCLE_READY)" 0 "a checksum mismatch ends the cycle"
res "$(docker inspect "$P-dind-1" > /dev/null 2>&1 && echo present || echo absent)" absent "... before any dind (or runner) starts"
cp "$W/sha.keep" "$W/app/images/job-image.tar.sha256"
res "$(cycle)" CYCLE_READY "cycle 3 ran (checksum restored)"

# 2. the runner's path: on runnernet, client certs volume, DOCKER_HOST=tcp://dind:2376 with TLS verify
V=$(docker run --rm --network "${P}_runnernet" -v "${P}_${CERTS}:/certs/client:ro" \
      -e DOCKER_HOST=tcp://dind:2376 -e DOCKER_TLS_VERIFY=1 -e DOCKER_CERT_PATH=/certs/client \
      --entrypoint docker "$DIND" version --format '{{.Server.Version}}' 2>&1)
DVER=${DIND#docker:}; DVER=${DVER%%-*}
res "$V" "$DVER" "the runner's path reaches dind over verified TLS (SAN 'dind')"

# 3. a job inside dind, with config.yaml's options, drives dind with the job image's own CLI
# shellcheck disable=SC2086  # OPTS is the option string act_runner splits the same way
J=$(in_dind docker run --rm $OPTS "$TAG" docker version --format '{{.Server.Version}}' | tail -1)
res "$J" "$V" "a job (config.yaml options, the job image's docker CLI) uses the dind daemon over verified TLS"
C=$(in_dind docker run --rm "$TAG" docker version --format '{{.Server.Version}}' | tail -1)
case "$C" in "$V") r=reached ;; *) r=refused ;; esac; res "$r" refused "CONTROL: a job without the options has no docker daemon"

# 4. the job image: node for actions/checkout, python3 and apt for the workflows
N=$(in_dind docker run --rm "$TAG" sh -c 'node --version; python3 --version; apt-get --version | head -1' | tail -3 | tr '\n' '|')
case "$N" in v24.*\|Python\ 3.*\|apt\ *) r=ok ;; *) r="$N" ;; esac; res "$r" ok "the job image has node 24, python3 and apt"

# 5. act_runner parses config.yaml: it gets past the config to the missing registration
A=$(docker run --rm -v "$SITE/docker/config.yaml:/config.yaml:ro" --entrypoint act_runner "$RUNNER" daemon --config /config.yaml 2>&1 | tail -3 | tr '\n' ' ')
case "$A" in *"registration file not found"*|*".runner"*) r=parsed ;; *) r="$A" ;; esac; res "$r" parsed "act_runner parses config.yaml (stops at the missing registration, as expected)"

# 6. the credential boundary. First the compose file: which service mounts what.
python3 - "$COMPOSE" > "$W/mounts.txt" <<'PY'
import sys, yaml
svc = yaml.safe_load(open(sys.argv[1]))["services"]
def has(name, needle):
    return any(needle in v for v in svc[name].get("volumes", []))
for name in ("register", "runner"):
    print(name, "auth=%s" % has(name, ".infisical-auth.env"), "cli=%s" % has(name, "/usr/bin/infisical"),
          "entrypoint=%s" % ("entrypoint" in svc[name]))
PY
res "$(sed -n 's/^register //p' "$W/mounts.txt")" "auth=True cli=True entrypoint=True" "register (one-shot) alone mounts the auth file and the Infisical CLI"
res "$(sed -n 's/^runner //p' "$W/mounts.txt")" "auth=False cli=False entrypoint=False" "runner (handles jobs) mounts neither, and runs the image's own entrypoint"
#    Then the wrapper, in the act_runner image, with a stand-in infisical CLI that
#    records its calls and, for `run`, execs the command after `--`.
mkdir -p "$W/wrap/data"
cat > "$W/wrap/infisical" <<'EOF'
#!/bin/sh
echo "infisical $* | ua_id=${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:-} ua_secret=${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET:+set}" >> /calls/log
case "$1" in
  login) echo tok-synthetic ;;
  run) while [ "$1" != "--" ]; do shift; done; shift; exec "$@" ;;
esac
EOF
chmod +x "$W/wrap/infisical"
printf 'INFISICAL_PROJECT_ID=pid-from-file\nINFISICAL_CLIENT_ID=cid-1\nINFISICAL_CLIENT_SECRET=mi-synthetic-0001\nINFISICAL_ENV_SLUG=staging\n' > "$W/wrap/auth.env"
wrap() {
  : > "$W/wrap/log"
  docker run --rm -v "$SITE/scripts/entrypoint-infisical.sh:/wrapper.sh:ro" -v "$W/wrap/infisical:/usr/bin/infisical:ro" \
    -v "$W/wrap/auth.env:/.infisical-auth.env:ro" -v "$W/wrap/data:/data" -v "$W/wrap:/calls" \
    -e INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET=from-container-env \
    --entrypoint /bin/sh "$RUNNER" /wrapper.sh sh -c 'env | grep -c -E "^INFISICAL_(CLIENT_SECRET|CLIENT_ID|UNIVERSAL_AUTH_CLIENT_SECRET|UNIVERSAL_AUTH_CLIENT_ID)=" ; echo "token=${INFISICAL_TOKEN:-none}"' 2>&1 | tr '\n' ' '
}
res "$(wrap)" "0 token=tok-synthetic " "unregistered: registration gets INFISICAL_TOKEN and no Machine Identity credential"
res "$(grep -c '^infisical login --method=universal-auth --plain --silent | ua_id=cid-1 ua_secret=set$' "$W/wrap/log")" 1 "unregistered: login used the auth file's client id and secret"
res "$(grep -c '^infisical run --projectId=pid-from-file --env=staging -- ' "$W/wrap/log")" 1 "unregistered: run used the auth file's project and env (not render-time values)"
echo '{"id": 1}' > "$W/wrap/data/.runner"
res "$(wrap)" "already registered (/data/.runner exists); not contacting Infisical " "registered: the wrapper exits without running the command"
res "$(wc -l < "$W/wrap/log" | tr -d ' ')" 0 "registered: Infisical is never called"

#    And the register command itself (from the compose file, as compose runs it): the
#    token must reach act_runner on stdin, never on its argv or in its environment.
python3 - "$COMPOSE" > "$W/register-cmd.sh" <<'PY'
import sys, yaml
cmd = yaml.safe_load(open(sys.argv[1]))["services"]["register"]["command"]
assert cmd[:2] == ["sh", "-c"], cmd
print(cmd[2].replace("$$", "$"))
PY
mkdir -p "$W/reg/data" "$W/reg/bin"
: > "$W/reg/data/.runner"   # an EMPTY leftover: the command must remove it
cat > "$W/reg/bin/act_runner" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > /calls/argv
cat > /calls/stdin
env > /calls/env
EOF
chmod +x "$W/reg/bin/act_runner"
PROBE_VALUE=probe-value-synthetic   # stands in for the registration token
docker run --rm -v "$W/reg/bin/act_runner:/usr/local/bin/act_runner:ro" -v "$W/reg:/calls" -v "$W/reg/data:/data" \
  -v "$W/register-cmd.sh:/register-cmd.sh:ro" -e GITEA_RUNNER_REGISTRATION_TOKEN="$PROBE_VALUE" \
  -e GITEA_INSTANCE_URL=https://forge.example -e GITEA_RUNNER_NAME=probe -e GITEA_RUNNER_LABELS=ubuntu-latest:docker://x:y \
  --entrypoint sh "$RUNNER" /register-cmd.sh > /dev/null 2>&1
res "$(grep -c "$PROBE_VALUE" "$W/reg/argv")" 0 "register: the token is not on act_runner's argv"
res "$(cat "$W/reg/stdin")" "$PROBE_VALUE" "register: the token reaches act_runner on stdin"
res "$(grep -c "$PROBE_VALUE" "$W/reg/env")" 0 "register: the token is not in act_runner's environment"
res "$(cat "$W/reg/argv")" "register --config /config.yaml --instance https://forge.example --name probe --labels ubuntu-latest:docker://x:y" "register: instance, name and labels as flags"
res "$([ -e "$W/reg/data/.runner" ] && echo present || echo removed)" removed "register: an empty leftover .runner is removed first"
#    The REAL act_runner reads a token from stdin without a TTY (an unreachable instance
#    then fails the ping); without one it stops at "Enter the runner token" (EOF).
printf 'runner:\n  file: /tmp/.runner\n  labels:\n    - "ubuntu-latest:docker://x:y"\n' > "$W/reg/config.yaml"
real() {
  # --init: a real PID 1, so `timeout` can stop the registration's ping loop.
  docker run --rm --init -v "$W/reg/config.yaml:/config.yaml:ro" -v "$W/register-cmd.sh:/register-cmd.sh:ro" \
    -e GITEA_RUNNER_REGISTRATION_TOKEN="$1" -e GITEA_INSTANCE_URL=http://127.0.0.1:1 -e GITEA_RUNNER_NAME=probe \
    -e GITEA_RUNNER_LABELS=ubuntu-latest:docker://x:y --entrypoint sh "$RUNNER" -c 'timeout 6 sh /register-cmd.sh' 2>&1
}
case "$(real tok-real-synthetic)" in *"Cannot ping the Gitea instance"*) r=accepted ;; *) r=other ;; esac
res "$r" accepted "register (real act_runner): the stdin token is accepted and registration starts"
case "$(real "")" in *"Enter the runner token"*EOF*) r=asked ;; *) r=other ;; esac
res "$r" asked "CONTROL: with no token on stdin the real act_runner asks for one and fails (EOF)"

# 7. the deploy task's own shell, its metadata URL swapped for a refused one on this
#    machine; then a timeout and a missing wget, which must not read as BLOCKED.
TASK=$(python3 - "$SITE/ansible/deploy.yml" "$W/app" "$DIND" <<'PY'
import sys, yaml
play = yaml.safe_load(open(sys.argv[1]))[0]
t = next(t for t in play["tasks"] if t["name"].startswith("Prove a container is refused the metadata service"))
s = t["ansible.builtin.shell"]
s = s.replace("{{ app_dir }}", sys.argv[2]).replace("{{ dind_image }}", sys.argv[3])
print(s.replace("http://169.254.169.254/metadata/v1/id", "http://127.0.0.1:1/metadata/v1/id"))
PY
)
OUT=$(bash -c "$TASK" | tr '\n' '|')
res "$OUT" "http://127.0.0.1:1/metadata/v1/id BLOCKED|$FORGE/api/healthz REACHED|" "the deploy probe: refused = BLOCKED, the forge control = REACHED"
probe() { docker run --rm -v "$W/app/probe-url.sh:/p.sh:ro" --entrypoint sh "$DIND" -c "$1" 2>&1 | tail -1; }
res "$(probe 'sh /p.sh http://192.0.2.1/ 2' | cut -c1-6)" "OTHER(" "an unanswered address (RFC 5737 TEST-NET-1) is OTHER, never BLOCKED"
res "$(probe 'PATH=/nonexistent /bin/sh /p.sh http://127.0.0.1:1/ 2')" NO_WGET "no wget is NO_WGET, never BLOCKED"

# 8. token-gone.sh with a stand-in infisical CLI whose export prints the real dotenv
#    shape (KEY='value', Infisical CLI packages/cmd/export.go formatAsDotEnv).
mkdir -p "$W/gate"
cat > "$W/gate/infisical" <<'EOF'
#!/bin/sh
case "$1:$(cat /gate/mode)" in
  login:login-fails) exit 1 ;;
  login:*) echo access-synthetic ;;
  export:export-fails) echo "error: unauthorized" >&2; exit 1 ;;
  export:present) printf "OTHER_KEY='x'\nGITEA_RUNNER_REGISTRATION_TOKEN='gate-value-synthetic'\n" ;;
  export:gone) printf "OTHER_KEY='x'\n" ;;
esac
EOF
chmod +x "$W/gate/infisical"
printf 'INFISICAL_PROJECT_ID=p\nINFISICAL_CLIENT_ID=c\nINFISICAL_CLIENT_SECRET=s\nINFISICAL_ENV_SLUG=prod\n' > "$W/gate/auth.env"
gate() {
  echo "$1" > "$W/gate/mode"
  docker run --rm -v "$W/gate:/gate" -v "$W/gate/infisical:/usr/local/bin/infisical:ro" \
    -v "$W/gate/auth.env:$APP_ON_BOX/.infisical-auth.env:ro" -v "$W/app/token-gone.sh:/token-gone.sh:ro" \
    --entrypoint bash "$JOB" /token-gone.sh 2>&1
}
res "$(gate present)" PRESENT=1 "token gate: the token still in the project reads PRESENT=1 (the deploy stops the runner)"
res "$(gate gone)" PRESENT=0 "token gate: the token gone reads PRESENT=0 (the only answer that starts the runner)"
res "$(gate export-fails)" "CHECK_FAILED: infisical export" "token gate: a failed export is CHECK_FAILED, never PRESENT=0"
res "$(gate login-fails)" "CHECK_FAILED: Infisical login" "token gate: a failed login is CHECK_FAILED, never PRESENT=0"
res "$(gate present | grep -c gate-value-synthetic)" 0 "token gate: the value is never printed"
#    The cycle refuses a box with no data/.runner before starting anything.
rm -f "$W/app/data/.runner"
res "$(cycle)" "not registered (no data/.runner): run scripts/deploy.sh" "an unregistered box: the cycle refuses"
res "$(docker inspect "$P-dind-1" > /dev/null 2>&1 && echo present || echo absent)" absent "... and starts no dind"
exit "$BAD"
