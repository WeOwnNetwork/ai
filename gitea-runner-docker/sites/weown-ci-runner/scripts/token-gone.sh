#!/usr/bin/env bash
# weown-ci-runner — is GITEA_RUNNER_REGISTRATION_TOKEN gone from the runner's Infisical project?
#
# ansible/deploy.yml starts the runner (and so lets it take jobs) only on PRESENT=0.
# Until the token is deleted (README step 7), a job that escaped to this host could
# use the Machine Identity here to read it. Prints exactly one line:
#   PRESENT=0               the token is gone
#   PRESENT=<n>             it is still there
#   CHECK_FAILED: <step>    the check could not run (that proves nothing)
# Never prints a value: the export goes through a pipe into awk, which only counts
# the key's line (`infisical export` dotenv lines are KEY='value').
set -uo pipefail

AUTH=/opt/weown_ci_runner/.infisical-auth.env
# shellcheck disable=SC1090
. "$AUTH" 2> /dev/null || { echo "CHECK_FAILED: cannot read $AUTH"; exit 0; }

TOKEN=$(INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="${INFISICAL_CLIENT_ID:-}" \
  INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="${INFISICAL_CLIENT_SECRET:-}" \
  infisical login --method=universal-auth --plain --silent 2> /dev/null)
[ -n "$TOKEN" ] || { echo "CHECK_FAILED: Infisical login"; exit 0; }

if N=$(INFISICAL_TOKEN="$TOKEN" infisical export --projectId="${INFISICAL_PROJECT_ID:-}" \
    --env="${INFISICAL_ENV_SLUG:-prod}" --format=dotenv 2> /dev/null \
    | awk -F= '$1 == "GITEA_RUNNER_REGISTRATION_TOKEN" { n++ } END { print n + 0 }'); then
  echo "PRESENT=$N"
else
  echo "CHECK_FAILED: infisical export"
fi
