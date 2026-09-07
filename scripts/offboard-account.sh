#!/usr/bin/env bash
# offboard-account.sh — ONE checked-in script for account offboarding across the
# WeOwn fleet: Keycloak (SSO), Gitea, GitHub orgs, the shared devbox.
#
# POLICY (Nik, 2026-09-07): DISABLE over DELETE. Disabling is the default and is
# reversible (--enable); --delete is a separate, explicit phase to run only after
# the account has soaked disabled (the openbao migration's 48h-soak / 30-day
# rollback shape). Every hand-over is a checked-in script, never UI clicks.
#
# Usage:
#   ./scripts/offboard-account.sh [--disable|--enable|--delete] [--dry-run] [--yes]
#                                 [--gitea-user <login>] [--github-user <handle>]
#                                 [--devbox root@<host>:<login>]
#                                 [--skip keycloak,gitea,github,devbox] <username>
#
#   <username>      the Keycloak realm-weown username. ⚠️ Read the identity line the
#                   script prints BEFORE confirming: `nik` in realm weown is NOT Nik
#                   Cimino (`cto`) — that collision (A585) has already cost six days.
#   --gitea-user    Gitea login when it differs from the Keycloak username (Gitea
#                   accounts auto-create on first SSO login and may have been renamed).
#   --github-user   GitHub handle when it differs from the Keycloak username.
#   --devbox        also lock/unlock the Linux account on the shared devbox.
#   --dry-run       read every system and print what WOULD change; mutate nothing.
#   --yes           required for any mutation (default is a dry run without it).
#
# What each phase does, per system:
#   keycloak  disable: enabled=false + revoke all sessions   enable: enabled=true
#             delete: remove the realm user (after soak; refuses without --yes)
#   gitea     disable: prohibit_login=true (Gitea then refuses web, API tokens AND
#             ssh-key git — SSH keys/tokens are LOCAL to Gitea and never consult the
#             IdP, so a Keycloak disable alone leaves git access working)
#             enable: prohibit_login=false   delete: remove the user (non-purge; fails
#             if they still own repos — transfer first, by design)
#   github    no disable exists. disable: DRY-RUN of scripts/github-remove-org-member.sh
#             (13 orgs) so the removal list is on record; delete: run it for real.
#   devbox    disable: lock + expire the Linux account, kill sessions  enable: unlock
#             delete: points at devbox-docker/.../offboard-user.sh (archive + remove)
#   openbao   printed step: openbao/scripts/weown-grant-operator.sh --revoke (prompts
#             for the KC admin password, so it is not driven from here)
#
# Secrets: Keycloak admin creds are read INSIDE the sso-keycloak ssh session from
# Infisical (never on argv, never printed). The Gitea admin token is minted on the
# Gitea box for this run and deleted at the end; it never leaves that shell.
#
# Prints, at the end: DID / COULD NOT REACH / MANUAL. Logs to ./offboard-logs/.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
KC_SSH_HOST="${KC_SSH_HOST:-sso-keycloak}"          # ~/.ssh/config alias (keycloak-docker/sites/sso)
KC_REALM="${KC_REALM:-weown}"
GITEA_SSH_HOST="${GITEA_SSH_HOST:-root@git.weown.tools}"
GITEA_URL="${GITEA_URL:-https://git.weown.tools}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-cto}"           # Gitea admin whose one-shot token drives the API
GITHUB_SCRIPT="$SCRIPT_DIR/github-remove-org-member.sh"
DEVBOX_OFFBOARD="$REPO_DIR/devbox-docker/sites/dev-weown-devbox/scripts/offboard-user.sh"

PHASE=disable; DRY=1; YES=0; GITEA_USER=""; GITHUB_USER=""; DEVBOX=""; SKIP=""
usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }
while [[ $# -gt 0 ]]; do case "$1" in
  --disable|--enable|--delete) PHASE="${1#--}"; shift ;;
  --dry-run) DRY=1; shift ;;
  --yes) YES=1; shift ;;
  --gitea-user) GITEA_USER="${2:-}"; shift 2 ;;
  --github-user) GITHUB_USER="${2:-}"; shift 2 ;;
  --devbox) DEVBOX="${2:-}"; shift 2 ;;
  --skip) SKIP=",${2:-},"; shift 2 ;;
  -h|--help) usage 0 ;;
  -*) echo "✗ unknown flag $1" >&2; usage 1 ;;
  *) USERNAME="${1}"; shift ;;
esac; done
[[ -n "${USERNAME:-}" ]] || usage 1
[[ "$USERNAME" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || { echo "✗ invalid username '$USERNAME'" >&2; exit 1; }
GITEA_USER="${GITEA_USER:-$USERNAME}"
GITHUB_USER="${GITHUB_USER:-$USERNAME}"
[[ "$GITHUB_USER" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}$ ]] || { echo "✗ invalid --github-user" >&2; exit 1; }
[[ "$GITEA_USER" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { echo "✗ invalid --gitea-user" >&2; exit 1; }
[[ $YES -eq 1 ]] && DRY=0
skip() { [[ "$SKIP" == *",$1,"* ]]; }

mkdir -p "$REPO_DIR/offboard-logs"
LOG="$REPO_DIR/offboard-logs/${USERNAME}-${PHASE}-$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$LOG") 2>&1
echo "== offboard-account: user=$USERNAME phase=$PHASE $([[ $DRY -eq 1 ]] && echo DRY-RUN || echo APPLY) $(date -u +%FT%TZ)"
echo "   log: $LOG"

DID=(); UNREACHED=(); MANUAL=()
did() { DID+=("$1"); echo "  ✓ $1"; }
unreached() { UNREACHED+=("$1"); echo "  ✗ $1"; }
manual() { MANUAL+=("$1"); }
plan() { echo "  ▸ would: $1"; }

# ── Keycloak ──────────────────────────────────────────────────────────────────
if ! skip keycloak; then
  echo; echo "── Keycloak (realm $KC_REALM via $KC_SSH_HOST)"
  KC_OUT="$(ssh -o BatchMode=yes -o ConnectTimeout=20 "$KC_SSH_HOST" 'bash -s' -- "$USERNAME" "$KC_REALM" "$PHASE" "$DRY" 2>&1 <<'REMOTE'
set -euo pipefail
USERNAME="$1"; REALM="$2"; PHASE="$3"; DRY="$4"
cd /opt/sso_keycloak
source ./.infisical-auth.env
INFISICAL_ENV="${INFISICAL_ENV:-prod}"
INFISICAL_PROJECT_ID="${INFISICAL_PROJECT_ID:-117b72e5-c084-44f6-9393-f5252b5ae0a8}"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="$INFISICAL_CLIENT_ID"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="$INFISICAL_CLIENT_SECRET"
export INFISICAL_TOKEN
INFISICAL_TOKEN=$(infisical login --method=universal-auth --plain --silent </dev/null 2>/dev/null)
KC_ADMIN=$(infisical secrets get KEYCLOAK_ADMIN --projectId="$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENV" --plain </dev/null 2>/dev/null)
KC_PASS=$(infisical secrets get KEYCLOAK_ADMIN_PASSWORD --projectId="$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENV" --plain </dev/null 2>/dev/null)
KC() { docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@" </dev/null; }
KC config credentials --server http://localhost:8080 --realm master --user "$KC_ADMIN" --password "$KC_PASS" >/dev/null 2>&1
unset KC_PASS
ID=$(KC get users -r "$REALM" -q username="$USERNAME" -q exact=true --fields id,username 2>/dev/null | grep -B1 "\"username\" : \"$USERNAME\"" | grep -o '"id" : "[^"]*' | head -1 | cut -d'"' -f4)
[ -n "$ID" ] || { echo "KC_NOTFOUND"; exit 0; }
J=$(KC get "users/$ID" -r "$REALM" --fields username,email,firstName,lastName,enabled 2>/dev/null)
echo "KC_IDENTITY $(echo "$J" | tr -d '\n ' )"
case "$PHASE" in
  disable) [ "$DRY" = 1 ] && { echo "KC_PLAN enabled=false + logout sessions"; exit 0; }
           KC update "users/$ID" -r "$REALM" -s enabled=false >/dev/null && KC create "users/$ID/logout" -r "$REALM" >/dev/null 2>&1 || true
           echo "KC_DONE enabled=false, sessions revoked" ;;
  enable)  [ "$DRY" = 1 ] && { echo "KC_PLAN enabled=true"; exit 0; }
           KC update "users/$ID" -r "$REALM" -s enabled=true >/dev/null && echo "KC_DONE enabled=true" ;;
  delete)  [ "$DRY" = 1 ] && { echo "KC_PLAN DELETE realm user $ID"; exit 0; }
           KC delete "users/$ID" -r "$REALM" >/dev/null && echo "KC_DONE realm user deleted" ;;
esac
REMOTE
)"; rc=$?
  if [[ $rc -ne 0 ]]; then unreached "keycloak: ssh/kcadm failed (rc=$rc): $(echo "$KC_OUT" | grep -viE 'token|password' | tail -1)"
  elif grep -q KC_NOTFOUND <<<"$KC_OUT"; then unreached "keycloak: user '$USERNAME' not found in realm $KC_REALM"
  else
    echo "  identity: $(grep KC_IDENTITY <<<"$KC_OUT" | sed 's/KC_IDENTITY //')"
    grep -q KC_PLAN <<<"$KC_OUT" && plan "keycloak $(grep KC_PLAN <<<"$KC_OUT" | sed 's/KC_PLAN //')"
    grep -q KC_DONE <<<"$KC_OUT" && did "keycloak: $(grep KC_DONE <<<"$KC_OUT" | sed 's/KC_DONE //')"
  fi
fi

# ── Gitea ─────────────────────────────────────────────────────────────────────
if ! skip gitea; then
  echo; echo "── Gitea ($GITEA_URL, login '$GITEA_USER', via $GITEA_SSH_HOST)"
  PUB="$(curl -s -m 10 -o /dev/null -w '%{http_code} %{redirect_url}' "$GITEA_URL/api/v1/users/$GITEA_USER")"
  case "${PUB%% *}" in
    404) unreached "gitea: no account '$GITEA_USER' (never logged in via SSO, or a different login — pass --gitea-user)";;
    307) unreached "gitea: '$GITEA_USER' is a RENAMED login that now redirects to ${PUB##*/} — pass --gitea-user with the real login";;
    200)
      KEYS=$(curl -s -m 10 "$GITEA_URL/api/v1/users/$GITEA_USER/keys" | jq -r 'if type=="array" then length else "?" end' 2>/dev/null || echo "?")
      echo "  public ssh keys on account: $KEYS (each one authenticates git WITHOUT the IdP until prohibit_login is set)"
      G_OUT="$(ssh -o BatchMode=yes -o ConnectTimeout=20 "$GITEA_SSH_HOST" 'bash -s' -- "$GITEA_USER" "$GITEA_ADMIN_USER" "$GITEA_URL" "$PHASE" "$DRY" 2>&1 <<'REMOTE'
set -uo pipefail
U="$1"; ADMIN="$2"; URL="$3"; PHASE="$4"; DRY="$5"
C=$(docker ps --format '{{.Names}}' | grep -iE 'gitea' | grep -viE 'db|postgres|caddy' | head -1)
[ -n "$C" ] || { echo "G_ERR no gitea container"; exit 2; }
G() { docker exec -u git "$C" gitea "$@"; }
TN="offboard-$(date +%s)"
TOK=$(G admin user generate-access-token --username "$ADMIN" --token-name "$TN" --scopes write:admin,read:user --raw 2>/dev/null | tail -1)
[ -n "$TOK" ] || { echo "G_ERR could not mint admin token for $ADMIN"; exit 3; }
cleanup() { G admin user delete-access-token --username "$ADMIN" "$TN" >/dev/null 2>&1 || echo "G_WARN one-shot token $TN for $ADMIN could not be auto-deleted — delete it in $ADMIN's Settings > Applications"; }
trap cleanup EXIT
api() { curl -s -m 15 -H "Authorization: token $TOK" -H 'Content-Type: application/json' "$@"; }
J=$(api "$URL/api/v1/admin/users/$U" 2>/dev/null); [ -n "$J" ] || J=$(api "$URL/api/v1/users/$U")
echo "G_STATE $(echo "$J" | jq -c '{login,full_name,email,active,prohibit_login,is_admin,last_login}' 2>/dev/null)"
case "$PHASE" in
  disable) [ "$DRY" = 1 ] && { echo "G_PLAN prohibit_login=true"; exit 0; }
           R=$(api -X PATCH "$URL/api/v1/admin/users/$U" -d '{"prohibit_login":true}' -o /dev/null -w '%{http_code}'); [ "$R" = 200 ] && echo "G_DONE prohibit_login=true (web, tokens, ssh git all refused)" || echo "G_ERR patch http $R" ;;
  enable)  [ "$DRY" = 1 ] && { echo "G_PLAN prohibit_login=false"; exit 0; }
           R=$(api -X PATCH "$URL/api/v1/admin/users/$U" -d '{"prohibit_login":false}' -o /dev/null -w '%{http_code}'); [ "$R" = 200 ] && echo "G_DONE prohibit_login=false" || echo "G_ERR patch http $R" ;;
  delete)  [ "$DRY" = 1 ] && { echo "G_PLAN DELETE user (non-purge; fails if they own repos)"; exit 0; }
           R=$(api -X DELETE "$URL/api/v1/admin/users/$U" -o /dev/null -w '%{http_code}'); [ "$R" = 204 ] && echo "G_DONE user deleted" || echo "G_ERR delete http $R (owns repos? transfer them first)" ;;
esac
REMOTE
)"; rc=$?
      if [[ $rc -ne 0 ]] || grep -q G_ERR <<<"$G_OUT"; then unreached "gitea: $(grep -E 'G_ERR|Host key|denied|timed out' <<<"$G_OUT" | head -1 | sed 's/G_ERR //')"
      else
        echo "  state: $(grep G_STATE <<<"$G_OUT" | sed 's/G_STATE //')"
        grep -q G_PLAN <<<"$G_OUT" && plan "gitea $(grep G_PLAN <<<"$G_OUT" | sed 's/G_PLAN //')"
        grep -q G_DONE <<<"$G_OUT" && did "gitea: $(grep G_DONE <<<"$G_OUT" | sed 's/G_DONE //')"
        grep -q G_WARN <<<"$G_OUT" && manual "$(grep G_WARN <<<"$G_OUT" | sed 's/G_WARN //')"
      fi ;;
    *) unreached "gitea: $GITEA_URL unreachable (http ${PUB%% *})";;
  esac
fi

# ── GitHub orgs ───────────────────────────────────────────────────────────────
if ! skip github; then
  echo; echo "── GitHub (orgs enumerated via $(basename "$GITHUB_SCRIPT"), handle '$GITHUB_USER')"
  GH_NAME=$(gh api "users/$GITHUB_USER" --jq '.name // "(no display name)"' 2>/dev/null || echo "")
  GH_ORGS=$(gh api --paginate user/memberships/orgs --jq '.[]|select(.state=="active")|.organization.login' 2>/dev/null | while read -r o; do gh api "orgs/$o/members/$GITHUB_USER" >/dev/null 2>&1 && echo "$o"; done | tr '\n' ' ')
  echo "  identity: github '$GITHUB_USER' = \"${GH_NAME:-unresolved}\"; member of: ${GH_ORGS:-NONE}"
  if [[ -z "$GH_NAME" ]]; then unreached "github: handle '$GITHUB_USER' does not resolve (gh not authed, or no such user)"
  elif [[ -z "$GH_ORGS" ]]; then unreached "github: REFUSED — '$GITHUB_USER' (\"$GH_NAME\") is in none of the operator's orgs; wrong handle? (pass --github-user)"
  elif [[ ! -x "$GITHUB_SCRIPT" ]]; then unreached "github: $GITHUB_SCRIPT missing/not executable"
  elif [[ "$PHASE" == enable ]]; then manual "github: re-invite '$GITHUB_USER' to the orgs they need (no scripted path)"
  elif [[ "$PHASE" == disable || $DRY -eq 1 ]]; then
    echo "  GitHub has no 'disable'; recording the removal list (dry-run) — removal happens in --delete."
    "$GITHUB_SCRIPT" "$GITHUB_USER" --dry-run 2>&1 | grep -E 'Target:|member of|Would remove|REFUSED|rror' | sed 's/^/    /' || true
    plan "github: remove '$GITHUB_USER' from every org listed above (on --delete)"
  else
    "$GITHUB_SCRIPT" "$GITHUB_USER" 2>&1 | grep -E 'Target:|member of|emoved|REFUSED|rror' | sed 's/^/    /'; [[ ${PIPESTATUS[0]} -eq 0 ]] && did "github: org removals run (see above)" || unreached "github: removal script failed"
  fi
fi

# ── Devbox (optional) ─────────────────────────────────────────────────────────
if [[ -n "$DEVBOX" ]] && ! skip devbox; then
  DB_HOST="${DEVBOX%%:*}"; DB_LOGIN="${DEVBOX##*:}"
  echo; echo "── Devbox ($DB_HOST, linux login '$DB_LOGIN')"
  [[ "$DB_LOGIN" =~ ^[a-z][a-z0-9-]{1,31}$ ]] || { unreached "devbox: invalid login '$DB_LOGIN'"; DB_LOGIN=""; }
  if [[ -n "$DB_LOGIN" ]]; then case "$PHASE" in
    disable) [[ $DRY -eq 1 ]] && plan "devbox: usermod -L -e 1 $DB_LOGIN + kill sessions" || {
               ssh -o BatchMode=yes -o ConnectTimeout=20 "$DB_HOST" 'bash -s' -- "$DB_LOGIN" <<'R' && did "devbox: account locked+expired, sessions killed" || unreached "devbox: lock failed"
set -e; L="$1"; id "$L" >/dev/null; usermod -L -e 1 "$L"; pkill -KILL -u "$L" 2>/dev/null || true; echo locked
R
             } ;;
    enable)  [[ $DRY -eq 1 ]] && plan "devbox: usermod -U -e '' $DB_LOGIN" || {
               ssh -o BatchMode=yes -o ConnectTimeout=20 "$DB_HOST" 'bash -s' -- "$DB_LOGIN" <<'R' && did "devbox: account unlocked" || unreached "devbox: unlock failed"
set -e; L="$1"; usermod -U -e '' "$L"; echo unlocked
R
             } ;;
    delete)  manual "devbox: run $DEVBOX_OFFBOARD $DB_HOST $DB_LOGIN (archives /home first, then removes via members.yml)" ;;
  esac; fi
fi

# ── OpenBao role (printed, needs the KC admin password prompt) ────────────────
[[ "$PHASE" != enable ]] && manual "openbao: cd ~/projects/openbao && ./scripts/weown-grant-operator.sh --revoke bao-operator $USERNAME   (and --revoke bao-developer if held)"
manual "infisical: Org → Access Control → Members: remove '$USERNAME' if present (no CLI path for member removal)"

echo; echo "== SUMMARY ($PHASE, $([[ $DRY -eq 1 ]] && echo 'DRY-RUN — nothing changed; re-run with --yes' || echo APPLIED))"
echo "DID:";           for x in "${DID[@]:-}";       do [[ -n "$x" ]] && echo "  ✓ $x"; done
echo "COULD NOT REACH:"; for x in "${UNREACHED[@]:-}"; do [[ -n "$x" ]] && echo "  ✗ $x"; done
echo "MANUAL:";        for x in "${MANUAL[@]:-}";    do [[ -n "$x" ]] && echo "  ☐ $x"; done
[[ "$PHASE" == disable && $DRY -eq 0 ]] && echo "Soak policy: leave disabled; run --delete only after the soak window (48h+), with --yes."
[[ ${#UNREACHED[@]} -gt 0 ]] && exit 2 || exit 0
