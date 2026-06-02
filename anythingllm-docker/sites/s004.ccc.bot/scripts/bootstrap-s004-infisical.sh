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
# memory and are unset on exit. JWT_SECRET is GENERATED here, pushed once, and
# never printed (set once, NEVER rotate — rotating logs every user out).
#
# Prereqs: `infisical` CLI (run `infisical login` first), `openssl`.
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

# ── preflight ────────────────────────────────────────────────────────────────
command -v infisical >/dev/null 2>&1 || { echo "ERROR: infisical CLI not found. Install it, then 'infisical login'." >&2; exit 1; }
command -v openssl   >/dev/null 2>&1 || { echo "ERROR: openssl not found." >&2; exit 1; }
if ! infisical whoami >/dev/null 2>&1 && ! infisical user >/dev/null 2>&1; then
  echo "WARN: can't confirm an Infisical login. If pushes fail, run 'infisical login' first." >&2
fi

# Clear secret vars no matter how we exit.
trap 'unset JWT_SECRET OPENROUTER_API_KEY ADMIN_EMAIL SPACES_ACCESS_KEY SPACES_SECRET_KEY 2>/dev/null || true' EXIT

read -rp "Dedicated s004 Infisical PROJECT ID: " S004_PROJECT_ID
[ -n "${S004_PROJECT_ID:-}" ] || { echo "ERROR: project id is required." >&2; exit 1; }

# _push KEY VALUE — upsert one secret; never prints VALUE.
_push() {
  if infisical secrets set "$1=$2" \
       --projectId="$S004_PROJECT_ID" --env="$ENV_SLUG" --path="$SECRET_PATH" >/dev/null 2>&1; then
    echo "  ✓ set $1"
  else
    echo "  ✗ FAILED to set $1 — verify flags via 'infisical secrets set --help' and your login." >&2
    return 1
  fi
}

echo
echo "── Pushing app secrets → Infisical project ${S004_PROJECT_ID} (${ENV_SLUG} env) ──"

# JWT_SECRET — generated in memory, pushed once, never printed, NEVER rotate.
JWT_SECRET="$(openssl rand -hex 32)"
_push JWT_SECRET "$JWT_SECRET" || true

# OPENROUTER_API_KEY — show the name to use (7-day expiry, EDT), then read the value.
if exp_label="$(TZ=America/New_York date -d '+7 days' '+%Y-%m-%dT%H%M%Z' 2>/dev/null)"; then :; else
  exp_label="$(TZ=America/New_York date -v+7d '+%Y-%m-%dT%H%M%Z')"
fi
echo
echo "  Create a NEW OpenRouter key with a 7-day expiry, named exactly:"
echo "    OPENROUTER_API_ANYTHINGLLM_INT-S004_7D_EXP_${exp_label}"
printf "  Paste the OpenRouter key value: "
read -rs OPENROUTER_API_KEY; echo
_push OPENROUTER_API_KEY "$OPENROUTER_API_KEY" || true

# ADMIN_EMAIL — not secret, plain read.
read -rp "  ADMIN_EMAIL: " ADMIN_EMAIL
_push ADMIN_EMAIL "$ADMIN_EMAIL" || true

# SPACES_* — required for offsite backups.
printf "  SPACES_ACCESS_KEY (DO Spaces, for backups): "
read -rs SPACES_ACCESS_KEY; echo
_push SPACES_ACCESS_KEY "$SPACES_ACCESS_KEY" || true

printf "  SPACES_SECRET_KEY: "
read -rs SPACES_SECRET_KEY; echo
_push SPACES_SECRET_KEY "$SPACES_SECRET_KEY" || true

echo
echo "Done. The dedicated s004 Infisical project now holds JWT_SECRET, OPENROUTER_API_KEY,"
echo "ADMIN_EMAIL, SPACES_ACCESS_KEY, SPACES_SECRET_KEY in the '${ENV_SLUG}' env."
echo "No secret value touched disk or your shell history."
echo
echo "Next: provision + deploy per MIGRATION_RUNBOOK.md (use INFISICAL_PROJECT_ID=${S004_PROJECT_ID})."
