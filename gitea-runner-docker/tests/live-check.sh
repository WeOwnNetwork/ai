#!/usr/bin/env bash
# live-check.sh — run a rendered gitea-runner-docker site's stack on local Docker
# BEFORE deploying it, especially after bumping an image pin:
#   1. the runner cycle (scripts/runner-cycle.sh, as written, in the job image's Ubuntu
#      userland): a fresh dind comes up healthy, the saved job image loads under the
#      label's tag, and what one job leaves behind (a container, a volume) is gone in
#      the next cycle's daemon;
#   2. the runner's path reaches dind over verified TLS (the pinned "dind" SAN);
#   3. a job with config.yaml's options drives dind with the job image's own docker
#      CLI, and a job without them cannot (the control);
#   4. the job image has node 24, python3 and apt;
#   5. act_runner parses config.yaml;
#   6. the Infisical wrapper: a registered runner never calls Infisical, an unregistered
#      one runs with the auth file's project and env, and no Machine Identity
#      credential reaches the runner's environment;
#   7. the metadata probe (the deploy task's own shell): a refused connection is
#      BLOCKED, the forge is REACHED, and a timeout or a missing wget is neither.
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
RUNNER=$(sed -n 's/^    image: \(gitea\/act_runner:.*\)$/\1/p' "$COMPOSE")
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
echo "dind=$DIND"; echo "job=$JOB"; echo "job options: $OPTS"

W=$(mktemp -d)
# shellcheck disable=SC2329  # invoked by the EXIT trap
cleanup() {
  docker compose -f "$W/app/compose.yaml" -p "$P" down -v > /dev/null 2>&1
  rm -rf "$W"
}
trap cleanup EXIT
mkdir -p "$W/app/images"
cp "$COMPOSE" "$W/app/compose.yaml"
cp "$SITE/scripts/probe-url.sh" "$W/app/probe-url.sh"
# runner-cycle.sh exactly as rendered, except its last line (the runner would register).
sed 's/^exec docker compose -f compose.yaml run --rm --no-deps -T runner$/echo CYCLE_READY/' \
  "$SITE/scripts/runner-cycle.sh" > "$W/app/runner-cycle.sh"
grep -q '^echo CYCLE_READY$' "$W/app/runner-cycle.sh" || { echo "NOT RUN: runner-cycle.sh's last line changed"; exit 2; }

# The deploy's save step: pull by digest, tag, save, checksum.
docker pull -q "$JOB" > /dev/null || { echo "NOT RUN: could not pull $JOB"; exit 2; }
if ! { docker tag "$JOB" "$TAG" && docker save -o "$W/app/images/job-image.tar" "$TAG"; }; then
  echo "NOT RUN: docker save failed"; exit 2
fi
(cd "$W/app" && docker run --rm -v "$W/app:/a" -w /a --entrypoint sha256sum "$JOB" images/job-image.tar > images/job-image.tar.sha256)

# 1. one cycle, run by the job image's Ubuntu userland against this Docker, the app dir
#    mounted at its real path so compose names everything as on the droplet.
cycle() {
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$W/app:$APP_ON_BOX" \
    --entrypoint bash "$JOB" "$APP_ON_BOX/runner-cycle.sh" 2>&1 | tail -n 1
}
in_dind() { docker exec "$P-dind-1" "$@" 2>&1; }
res "$(cycle)" CYCLE_READY "cycle 1: down -v, a fresh dind (healthy), the job image loaded and its tag present"
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
printf '%064d  images/job-image.tar\n' 0 > "$W/app/images/job-image.tar.sha256"
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

# 6. the Infisical wrapper, in the act_runner image, with a stand-in infisical CLI that
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
res "$(wrap)" "0 token=tok-synthetic " "unregistered: the runner gets INFISICAL_TOKEN and no Machine Identity credential"
res "$(grep -c '^infisical login --method=universal-auth --plain --silent | ua_id=cid-1 ua_secret=set$' "$W/wrap/log")" 1 "unregistered: login used the auth file's client id and secret"
res "$(grep -c '^infisical run --projectId=pid-from-file --env=staging -- ' "$W/wrap/log")" 1 "unregistered: run used the auth file's project and env (not render-time values)"
echo '{"id": 1}' > "$W/wrap/data/.runner"
res "$(wrap)" "0 token=none " "registered: the runner starts with no Infisical token and no credential"
res "$(wc -l < "$W/wrap/log" | tr -d ' ')" 0 "registered: Infisical is never called"

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
res "$(probe 'sh /p.sh http://10.255.255.1/ 2' | cut -c1-6)" "OTHER(" "a timeout is OTHER, never BLOCKED"
res "$(probe 'PATH=/nonexistent /bin/sh /p.sh http://127.0.0.1:1/ 2')" NO_WGET "no wget is NO_WGET, never BLOCKED"
exit "$BAD"
