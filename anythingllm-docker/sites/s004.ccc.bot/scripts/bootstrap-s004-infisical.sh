#!/usr/bin/env bash
# bootstrap-s004-infisical.sh — one-shot Infisical env setup for INT-S004 (s004.ccc.bot)
#
# Prompts for every APPLICATION secret the s004 deployment needs and pushes it
# into the DEDICATED s004 Infisical project (prod env). Run it from your
# operator workstation, explicitly with bash (works the same whether your login
# shell is bash or zsh):
#
#     bash scripts/bootstrap-s004-infisical.sh
#
# Secret VALUES are read with `read -rs` — never echoed, never written to your
# shell history, and never written to disk. They live only in this process's
# memory and are unset on exit.
#
# Idempotent + safe to re-run:
#   - JWT_SECRET is GENERATED on the FIRST run and then LEFT UNTOUCHED on every
#     re-run (set once, NEVER rotate — rotating logs every user out). It is
#     never printed.
#   - For the other secrets, leave a prompt BLANK to skip it (so you can re-run
#     later to update just the OpenRouter key without re-entering everything).
#
# Login: the script confirms an Infisical session up front and runs
# `infisical login` for you if there isn't one — so a `secrets set` never
# triggers an interactive login mid-run (which looks like a hang and can drop
# the first write).
#
# Prereqs: `infisical` CLI, `openssl`.
#
# SECURITY NOTE: `infisical secrets set KEY=VALUE` passes the value as a process
# argument, so it is briefly visible in `ps`/proc on THIS machine only — never
# on disk, in shell history, or on the network. On a single-operator laptop
# that is acceptable. On a shared host, set the secrets in the Infisical UI
# instead.
#
# Infra/terraform secrets (DO token, Machine Identity, Spaces state-backend
# keys) are NOT handled here — see the site MIGRATION_RUNBOOK.md "no-disk
# terraform" snippet, which keeps them in shell memory via TF_VAR_* exports.

set -uo pipefail

ENV_SLUG="prod"
SECRET_PATH="/"
FAILED=0

# ── preflight ────────────────────────────────────────────────────────────────
command -v infisical >/dev/null 2>&1 || { echo "ERROR: infisical CLI not found. Install it first." >&2; exit 1; }
command -v openssl   >/dev/null 2>&1 || { echo "ERROR: openssl not found." >&2; exit 1; }

# Ensure a login BEFORE any secret op. The whoami/user probes just return
# non-zero when not logged in (they do not hang); `infisical login` is the
# explicit interactive step.
if infisical whoami >/dev/null 2>&1 || infisical user >/dev/null 2>&1; then
  echo "Infisical session active."
else
  echo "No active Infisical session - launching 'infisical login' (a browser/token prompt will appear)..."
  if ! infisical login; then
    echo "ERROR: 'infisical login' did not complete. Log in and re-run." >&2
    exit 1
  fi
fi

# Clear secret vars no matter how we exit.
trap 'unset JWT_SECRET OPENROUTER_API_KEY ADMIN_EMAIL SPACES_ACCESS_KEY SPACES_SECRET_KEY OPS_AUTHORIZED_KEYS 2>/dev/null || true' EXIT

read -rp "Dedicated s004 Infisical PROJECT ID: " S004_PROJECT_ID
[ -n "${S004_PROJECT_ID:-}" ] || { echo "ERROR: project id is required." >&2; exit 1; }

# _push KEY VALUE — upsert one secret; never prints VALUE.
_push() {
  if infisical secrets set "$1=$2" \
       --projectId="$S004_PROJECT_ID" --env="$ENV_SLUG" --path="$SECRET_PATH" >/dev/null 2>&1; then
    echo "  ✓ set $1"
  else
    echo "  ✗ FAILED to set $1 — verify 'infisical secrets set --help' flags and your login." >&2
    FAILED=1
  fi
}

# _exists KEY — true if the secret is already set. The value is fetched then
# discarded to /dev/null (never shown, never stored).
_exists() {
  infisical secrets get "$1" \
    --projectId="$S004_PROJECT_ID" --env="$ENV_SLUG" --path="$SECRET_PATH" >/dev/null 2>&1
}

# _maybe_push_secret KEY "prompt" — read a SECRET with read -rs; blank = skip.
_maybe_push_secret() {
  local key="$1" prompt="$2" val
  printf "  %s" "$prompt"
  read -rs val; echo
  if [ -n "${val:-}" ]; then _push "$key" "$val"; else echo "  • skipped $key (left blank)"; fi
  unset val
}

echo
echo "── App secrets → Infisical project ${S004_PROJECT_ID} (${ENV_SLUG} env) ──"

# JWT_SECRET — set ONCE, NEVER rotate. Skip if already present so re-runs don't
# silently rotate it (which would invalidate every session and log users out).
if _exists JWT_SECRET; then
  echo "  • JWT_SECRET already present — leaving it untouched (set once, never rotate)."
else
  JWT_SECRET="$(openssl rand -hex 32)"
  _push JWT_SECRET "$JWT_SECRET"
fi

# OPENROUTER_API_KEY — show the name to use (7-day expiry, EDT), then read it.
if exp_label="$(TZ=America/New_York date -d '+7 days' '+%Y-%m-%dT%H%M%Z' 2>/dev/null)"; then :; else
  exp_label="$(TZ=America/New_York date -v+7d '+%Y-%m-%dT%H%M%Z')"
fi
echo
echo "  Create a NEW OpenRouter key with a 7-day expiry, named exactly:"
echo "    OPENROUTER_API_ANYTHINGLLM_INT-S004_7D_EXP_${exp_label}"
_maybe_push_secret OPENROUTER_API_KEY "Paste the OpenRouter key value (blank to skip): "

# ADMIN_EMAIL — not secret, plain read; blank = skip.
read -rp "  ADMIN_EMAIL (blank to skip): " ADMIN_EMAIL
if [ -n "${ADMIN_EMAIL:-}" ]; then _push ADMIN_EMAIL "$ADMIN_EMAIL"; else echo "  • skipped ADMIN_EMAIL (left blank)"; fi

# SPACES_* — required for offsite backups; blank = skip.
_maybe_push_secret SPACES_ACCESS_KEY "SPACES_ACCESS_KEY (DO Spaces, for backups; blank to skip): "
_maybe_push_secret SPACES_SECRET_KEY "SPACES_SECRET_KEY (blank to skip): "

# OPS_AUTHORIZED_KEYS — team ops SSH PUBLIC keys (one per line) that ansible
# writes to root's authorized_keys on every deploy. These are PUBLIC keys (not
# secret), so this is a normal multi-line paste, not a hidden read. This is the
# single source of truth for who can SSH the box — remove a line + re-run
# deploy.sh to revoke (e.g. on termination).
echo
echo "  Team ops SSH PUBLIC keys for root access — paste one 'ssh-ed25519 …' per"
echo "  line, then press Ctrl-D. (Press Ctrl-D immediately to skip / set later in"
echo "  the Infisical UI.)"
OPS_AUTHORIZED_KEYS="$(cat)"
if [ -n "$(printf '%s' "${OPS_AUTHORIZED_KEYS:-}" | tr -d '[:space:]')" ]; then
  _push OPS_AUTHORIZED_KEYS "$OPS_AUTHORIZED_KEYS"
else
  echo "  • skipped OPS_AUTHORIZED_KEYS (set later in Infisical UI, one pub key per line)"
fi

echo
if [ "$FAILED" -ne 0 ]; then
  echo "FAILED — one or more secrets did not set (see ✗ above). Fix and re-run; JWT_SECRET is" >&2
  echo "preserved if already set. (Exiting non-zero so this isn't mistaken for success.)" >&2
  exit 1
fi
echo "Done — requested secrets are in the s004 Infisical project (${ENV_SLUG}). No value touched disk or history."
echo "Next: provision + deploy per MIGRATION_RUNBOOK.md (INFISICAL_PROJECT_ID=${S004_PROJECT_ID})."
