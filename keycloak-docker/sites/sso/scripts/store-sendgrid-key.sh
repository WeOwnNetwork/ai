#!/usr/bin/env bash
# Store the Twilio SendGrid API key into BOTH consumers' Infisical projects,
# blind (the value never appears on screen, argv, or disk):
#   - KeycloakSSO/prod  as SENDGRID_API_KEY        (read by kc-configure-smtp.sh)
#   - GiteaGit/prod     as GITEA__mailer__PASSWD   (injected into the gitea container)
# Prereq: `infisical login` as yourself (operator session).
set -euo pipefail
KC_PROJECT="117b72e5-c084-44f6-9393-f5252b5ae0a8"   # KeycloakSSO
GIT_PROJECT="bca46c96-ba4e-4576-9ea5-eef1766db3e1"  # GiteaGit

printf 'Twilio SendGrid API key (input hidden): ' >&2
read -rs SG_KEY; echo >&2
[ -n "$SG_KEY" ] || { echo "empty input — aborting" >&2; exit 1; }

printf '%s' "$SG_KEY" | infisical secrets set SENDGRID_API_KEY --projectId="$KC_PROJECT" --env=prod --file=/dev/stdin 2>/dev/null \
  || infisical secrets set "SENDGRID_API_KEY=$SG_KEY" --projectId="$KC_PROJECT" --env=prod >/dev/null
printf '%s' "$SG_KEY" | infisical secrets set GITEA__mailer__PASSWD --projectId="$GIT_PROJECT" --env=prod --file=/dev/stdin 2>/dev/null \
  || infisical secrets set "GITEA__mailer__PASSWD=$SG_KEY" --projectId="$GIT_PROJECT" --env=prod >/dev/null
unset SG_KEY
echo "Stored: SENDGRID_API_KEY (KeycloakSSO/prod) + GITEA__mailer__PASSWD (GiteaGit/prod)"
echo "Verify names only:  infisical secrets --projectId=$KC_PROJECT --env=prod | grep -c SENDGRID"
