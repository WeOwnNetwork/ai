#!/usr/bin/env bash
# live-check.sh — run a rendered gitea-runner-docker site's stack on local Docker
# BEFORE deploying it, especially after bumping an image pin:
#   - the real dind service from docker/compose.prod.yaml comes up healthy;
#   - the runner's path reaches dind over verified TLS (the pinned "dind" SAN);
#   - a job started with config.yaml's options can drive dind's docker, and a job
#     without them cannot (the control);
#   - the ubuntu-latest job image has node, python3 and apt;
#   - act_runner parses config.yaml.
# Not covered (they need a real droplet; ansible/deploy.yml checks the first two):
# the Infisical wrapper, the metadata block, and cloud-init.
#
#   gitea-runner-docker/tests/live-check.sh [sites/<name>]   # default sites/weown-ci-runner
#
# No token, no forge; it pulls the pinned images. Exit: 0 pass · 1 mismatch · 2 not run.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SITE=$(cd "${1:-$HERE/../sites/weown-ci-runner}" && pwd) || { echo "NOT RUN: no site"; exit 2; }
P=live-check-runner
CERTS=$(sed -n 's/^  \(.*_certs_client\):$/\1/p' "$SITE/docker/compose.prod.yaml")
DIND=$(sed -n 's/^    image: \(docker:.*\)$/\1/p' "$SITE/docker/compose.prod.yaml")
RUNNER=$(sed -n 's/^    image: \(gitea\/act_runner:.*\)$/\1/p' "$SITE/docker/compose.prod.yaml")
JOB=$(sed -n 's/^    - "ubuntu-latest:docker:\/\/\(.*\)"$/\1/p' "$SITE/docker/config.yaml")
OPTS=$(sed -n 's/^  options: "\(.*\)"$/\1/p' "$SITE/docker/config.yaml")
BAD=0
res() { if [ "$1" = "$2" ]; then echo "PASS     $3"; else echo "MISMATCH $3 (expected '$2', got '$1')"; BAD=1; fi; }
cleanup() { docker compose -f "$SITE/docker/compose.prod.yaml" -p "$P" down -v >/dev/null 2>&1; }
trap cleanup EXIT
[ -n "$DIND" ] && [ -n "$RUNNER" ] && [ -n "$JOB" ] && [ -n "$OPTS" ] && [ -n "$CERTS" ] || { echo "NOT RUN: could not read images/options from the render"; exit 2; }
echo "dind=$DIND"; echo "job=$JOB"; echo "job options: $OPTS"

docker compose -f "$SITE/docker/compose.prod.yaml" -p "$P" up -d dind >/dev/null 2>&1 || { echo "NOT RUN: dind did not start"; exit 2; }
for _ in $(seq 1 60); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$P-dind-1" 2>/dev/null)" = healthy ] && break; sleep 2; done
res "$(docker inspect -f '{{.State.Health.Status}}' "$P-dind-1")" healthy "dind is healthy (docker info inside it)"

# 2. the runner's path: on runnernet, client certs volume, DOCKER_HOST=tcp://dind:2376 with TLS verify
V=$(docker run --rm --network "${P}_runnernet" -v "${P}_${CERTS}:/certs/client:ro" \
      -e DOCKER_HOST=tcp://dind:2376 -e DOCKER_TLS_VERIFY=1 -e DOCKER_CERT_PATH=/certs/client \
      --entrypoint docker "$DIND" version --format '{{.Server.Version}}' 2>&1)
res "$V" "27.5.1" "the runner's path reaches dind over verified TLS (SAN 'dind')"

# 3. a job inside dind, with config.yaml's options, can drive dind's daemon (job_docker_access)
# shellcheck disable=SC2086  # OPTS is the option string act_runner splits the same way
J=$(docker exec "$P-dind-1" docker run --rm $OPTS --entrypoint docker "$DIND" version --format '{{.Server.Version}}' 2>&1 | tail -1)
res "$J" "27.5.1" "a job container (config.yaml options) uses the dind daemon over verified TLS"
# and without those options it cannot (the control)
C=$(docker exec "$P-dind-1" docker run --rm --entrypoint docker "$DIND" version --format '{{.Server.Version}}' 2>&1 | tail -1)
case "$C" in 27.5.1) r=reached ;; *) r=refused ;; esac; res "$r" refused "CONTROL: a job without the options has no docker daemon"

# 4. the ubuntu-latest job image: node for actions/checkout, python3 and apt for the workflows
N=$(docker exec "$P-dind-1" docker run --rm "$JOB" sh -c 'node --version; python3 --version; apt-get --version | head -1' 2>&1 | tail -3 | tr '\n' '|')
case "$N" in v24.*\|Python\ 3.*\|apt\ *) r=ok ;; *) r="$N" ;; esac; res "$r" ok "the job image has node 24, python3 and apt"

# 5. act_runner parses config.yaml: it gets past the config to the missing registration
A=$(docker run --rm -v "$SITE/docker/config.yaml:/config.yaml:ro" --entrypoint act_runner "$RUNNER" daemon --config /config.yaml 2>&1 | tail -3 | tr '\n' ' ')
case "$A" in *"registration file not found"*|*".runner"*) r=parsed ;; *) r="$A" ;; esac; res "$r" parsed "act_runner parses config.yaml (stops at the missing registration, as expected)"
exit "$BAD"
