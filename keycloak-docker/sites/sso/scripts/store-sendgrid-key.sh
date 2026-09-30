#!/usr/bin/env bash
# Store the Twilio SendGrid API key into BOTH consumers' Infisical projects,
# blind (the value never appears on screen, argv, or disk):
#   - KeycloakSSO/prod  as SENDGRID_API_KEY        (read by kc-configure-smtp.sh)
#   - GiteaGit/prod     as GITEA__mailer__PASSWD   (injected into the gitea container)
# Prereq: `infisical login` as yourself (operator session), jq.
#
# How the value reaches the CLI: `infisical secrets set --file=<name>.yaml`,
# where the file is a FIFO in a private 0700 dir fed by jq (value on jq's
# stdin via --rawfile). The old form, a positional NAME plus --file=/dev/stdin,
# is rejected by the CLI (--file excludes positional secrets), so it ALWAYS fell
# back to `NAME=value` on argv. There is no argv fallback now: a failure stops.
# `.yaml` because the CLI keeps a YAML string exactly (its dotenv parser trims
# and strips quotes); `--file`, not `NAME=@file`, because @file is expanded
# only for a user login and stored literally under a machine-identity token.
set -euo pipefail
command -v jq >/dev/null || { echo "ERROR: jq not found" >&2; exit 1; }
KC_PROJECT="117b72e5-c084-44f6-9393-f5252b5ae0a8"   # KeycloakSSO
GIT_PROJECT="bca46c96-ba4e-4576-9ea5-eef1766db3e1"  # GiteaGit

printf 'Twilio SendGrid API key (input hidden): ' >&2
read -rs SG_KEY; echo >&2
[ -n "$SG_KEY" ] || { echo "empty input — aborting" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/store-sendgrid.XXXXXX")"; chmod 700 "$WORK"
trap 'rm -rf "$WORK"; unset SG_KEY' EXIT
store() { # store <project-id> <secret-name>
  local fifo="$WORK/secret.yaml" wpid rc
  rm -f "$fifo"; mkfifo -m 600 "$fifo" || return 1
  printf '%s' "$SG_KEY" | jq -n --arg k "$2" --rawfile v /dev/stdin '{($k): $v}' > "$fifo" &
  wpid=$!
  infisical secrets set --file="$fifo" --projectId="$1" --env=prod >/dev/null
  rc=$?
  # A CLI that exits before reading the FIFO leaves the writer blocked in open().
  kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
  rm -f "$fifo"
  return "$rc"
}
store "$KC_PROJECT" SENDGRID_API_KEY || { echo "FAILED to store SENDGRID_API_KEY (KeycloakSSO/prod) — nothing was sent on argv" >&2; exit 1; }
store "$GIT_PROJECT" GITEA__mailer__PASSWD || { echo "FAILED to store GITEA__mailer__PASSWD (GiteaGit/prod) — SENDGRID_API_KEY is already stored" >&2; exit 1; }
unset SG_KEY
echo "Stored: SENDGRID_API_KEY (KeycloakSSO/prod) + GITEA__mailer__PASSWD (GiteaGit/prod)"
echo "Verify names only:  infisical secrets --projectId=$KC_PROJECT --env=prod | grep -c SENDGRID"
