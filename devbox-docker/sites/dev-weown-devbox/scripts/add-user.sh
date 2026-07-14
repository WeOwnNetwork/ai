#!/usr/bin/env bash
# dev-weown-devbox — Onboard a member (add-user)
#
# Thin wrapper around scripts/deploy.sh (which runs ansible/deploy.yml). It does
# NOT create the account itself — the source of truth is ansible/members.yml.
# This script just (1) checks the login you name is actually in members.yml and
# marked present, then (2) reconciles the box so the account exists, and finally
# (3) prints the member's first-login instructions.
#
# Onboarding flow:
#   1. Add the member to ansible/members.yml (login = CCC Short ID lowercased,
#      a stable uid >= 1000, and their PUBLIC ssh key(s)). See
#      ansible/members.example.yml for the field reference.
#   2. INFISICAL_PROJECT_ID=<id> ./scripts/add-user.sh <login> [user@host]
#
# Usage:
#   INFISICAL_PROJECT_ID=<id> ./scripts/add-user.sh <login> [user@host]
#
# Examples:
#   INFISICAL_PROJECT_ID=abc123 ./scripts/add-user.sh ccc-alice
#   INFISICAL_PROJECT_ID=abc123 ./scripts/add-user.sh ccc-alice root@203.0.113.10
#
# If you omit [user@host], the host is read from `tofu output -raw droplet_ip`
# (run from terraform/) and the SSH user defaults to root (the break-glass
# admin). Members never deploy — only an operator with the admin key does.
#
# Optional env vars:
#   INFISICAL_ENV   Infisical environment slug (default: prod)
#   SSH_USER        SSH user when host is auto-resolved (default: root)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MEMBERS_FILE="$PROJECT_DIR/ansible/members.yml"
DEPLOY_SH="$SCRIPT_DIR/deploy.sh"

usage() {
  echo "Usage: INFISICAL_PROJECT_ID=<id> $0 <login> [user@host]"
  echo ""
  echo "Examples:"
  echo "  INFISICAL_PROJECT_ID=abc123 $0 ccc-alice"
  echo "  INFISICAL_PROJECT_ID=abc123 $0 ccc-alice root@203.0.113.10"
  echo ""
  echo "Optional env vars:"
  echo "  INFISICAL_ENV   Infisical environment slug (default: prod)"
  echo "  SSH_USER        SSH user when host is auto-resolved (default: root)"
  exit "${1:-1}"
}

LOGIN="${1:-}"
REMOTE="${2:-}"
[[ -z "$LOGIN" ]] && usage 1

# Validate <login> strictly. It is interpolated into log lines and a grep
# pattern below, and must match a real Linux account name, so enforce the
# same rules members.yml documents: lowercase, starts with a letter, then
# letters/digits/hyphen, length-capped (sysctl/useradd reject longer).
if [[ ! "$LOGIN" =~ ^[a-z][a-z0-9-]{1,31}$ ]]; then
  echo "ERROR: invalid login '$LOGIN'." >&2
  echo "       Must be lowercase, start with a letter, only [a-z0-9-], <= 32 chars" >&2
  echo "       (login = the member's CCC Short ID lowercased, e.g. ccc-alice)." >&2
  exit 1
fi

# members.yml is the roster source of truth. Fail friendly if it's missing.
if [[ ! -f "$MEMBERS_FILE" ]]; then
  echo "ERROR: roster not found at $MEMBERS_FILE" >&2
  echo "       Create it first:  cp $PROJECT_DIR/ansible/members.example.yml $MEMBERS_FILE" >&2
  echo "       then add '$LOGIN' (login + uid + ssh_keys) and re-run." >&2
  exit 1
fi

# Confirm the login is actually in members.yml before deploying — otherwise the
# deploy would silently no-op for this person and the operator would think they
# onboarded someone who isn't on the roster. Prefer a YAML-aware check (yq) so a
# login that appears only in a comment doesn't count; fall back to a structured
# grep on the active (non-comment) `- login:` lines.
member_present() {
  local want="$1"
  if command -v yq >/dev/null 2>&1; then
    # state defaults to present; treat present/missing as "present", absent as not.
    local hit
    hit="$(yq eval \
      ".members[] | select(.login == \"$want\") | (.state // \"present\")" \
      "$MEMBERS_FILE" 2>/dev/null | head -1)"
    [[ "$hit" == "present" ]]
    return
  fi
  # No yq: scan active list entries. Strip comments, match `- login: <want>`
  # (optionally quoted). This won't see a per-member `state: absent`, so warn.
  grep -Eq "^[[:space:]]*-[[:space:]]+login:[[:space:]]+[\"']?${want}[\"']?[[:space:]]*(#.*)?$" \
    < <(sed 's/[[:space:]]#.*$//' "$MEMBERS_FILE")
}

if ! member_present "$LOGIN"; then
  echo "ERROR: '$LOGIN' is not an active member in $MEMBERS_FILE" >&2
  echo "       Add an entry under 'members:' (see ansible/members.example.yml):" >&2
  echo "" >&2
  echo "         - login: $LOGIN" >&2
  echo "           full_name: \"...\"" >&2
  echo "           uid: <unique, >= 1000>" >&2
  echo "           ssh_keys:" >&2
  echo "             - \"ssh-ed25519 AAAA... ${LOGIN}@device\"" >&2
  echo "" >&2
  echo "       If '$LOGIN' is present but state: absent, set state: present (or" >&2
  echo "       remove the state line) to re-enable the account, then re-run." >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "NOTE: 'yq' not found — verified '$LOGIN' is listed, but could not check" >&2
  echo "      its state. If it is marked 'state: absent' the deploy will REMOVE" >&2
  echo "      the account. Install yq to enable the state check." >&2
fi

if [[ ! -x "$DEPLOY_SH" ]]; then
  echo "ERROR: deploy script not found / not executable at $DEPLOY_SH" >&2
  exit 1
fi

# Resolve the host if the operator didn't pass one: read the reserved IP from
# terraform outputs and default the SSH user to root (break-glass admin).
if [[ -z "$REMOTE" ]]; then
  SSH_USER="${SSH_USER:-root}"
  HOST_IP=""
  if command -v tofu >/dev/null 2>&1; then
    HOST_IP="$(tofu -chdir="$PROJECT_DIR/terraform" output -raw droplet_ip 2>/dev/null || true)"
  elif command -v terraform >/dev/null 2>&1; then
    HOST_IP="$(terraform -chdir="$PROJECT_DIR/terraform" output -raw droplet_ip 2>/dev/null || true)"
  fi
  if [[ -z "$HOST_IP" ]]; then
    echo "ERROR: no host given and could not read droplet_ip from terraform output." >&2
    echo "       Pass the host explicitly, e.g.:" >&2
    echo "         INFISICAL_PROJECT_ID=<id> $0 $LOGIN ${SSH_USER}@203.0.113.10" >&2
    exit 1
  fi
  REMOTE="${SSH_USER}@${HOST_IP}"
  echo "==> Resolved host from terraform output: $REMOTE"
fi

echo "==> Onboarding '$LOGIN' on $REMOTE"
echo "    Reconciling the box from $MEMBERS_FILE via deploy.sh ..."
echo ""

# deploy.sh enforces the INFISICAL_PROJECT_ID contract and runs the full
# playbook (idempotent — it reconciles ALL members, then re-deploys Zed config,
# the toolchain, and backups). Run it, but don't let `set -e` swallow the exit
# code: we want to print follow-up steps only on success.
if "$DEPLOY_SH" "$REMOTE"; then
  HOST_ONLY="${REMOTE##*@}"
  cat <<EOF

=== ONBOARDING COMPLETE: $LOGIN ===

Send '$LOGIN' these first-login instructions:

  1. SSH into your account (your SSH key opens only this account):
       ssh ${LOGIN}@${HOST_ONLY}

  2. Configure Zed AI with your own OpenRouter key (one time):
       setup-zed

  3. Then connect with Zed Remote Development from your LAPTOP:
       Zed -> open the remote project over SSH to ${LOGIN}@${HOST_ONLY}
       (Zed auto-provisions its remote server; nothing to install on the box.)

Notes:
  - Members get NO sudo. docker access is opt-in (members.yml docker: true) and
    is root-equivalent — only request it if you genuinely need local containers.
  - To rotate your SSH key later: update your entry in ansible/members.yml and
    an operator re-runs this script (authorized_keys is exclusive to members.yml).
EOF
else
  rc=$?
  echo "" >&2
  echo "ERROR: deploy.sh exited with status $rc — '$LOGIN' was NOT onboarded." >&2
  echo "       Re-run after resolving the error above (the deploy is idempotent)." >&2
  exit "$rc"
fi
