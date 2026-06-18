#!/usr/bin/env bash
# dev-weown-devbox - Per-user Zed AI (OpenRouter) setup
#
# Run this ON the dev box, AS YOURSELF (your own member account) - never as
# root, never for someone else:
#
#     setup-zed
#
# What it does (simple path, works with zero Infisical setup):
#   1. Prompts for YOUR OpenRouter API key (https://openrouter.ai/keys) and
#      writes it to ~/.config/dev_weown_devbox/openrouter.env (chmod 600).
#      The key is written to THAT FILE ONLY - never echoed, never logged, never
#      passed on a command line, never stored in Zed's settings.json.
#   2. Makes your login shell source that env file (idempotent guard), so
#      OPENROUTER_API_KEY / OPENAI_API_KEY are present for any process you start
#      - including the Zed remote server.
#   3. Adds an OpenAI-compatible "openrouter" language-model provider to your
#      ~/.config/zed/settings.json pointing at https://openrouter.ai/api/v1.
#      Only the provider/base_url config is written there; Zed reads the actual
#      key from the OPENAI_API_KEY env var at runtime.

#
# Optional (Infisical) path:
#   If you'd rather keep your key in YOUR OWN Infisical account (so you can
#   rotate it centrally), pass --infisical. That logs you in to Infisical,
#   stores the key as a secret in a personal project, and installs a
#   ~/.local/bin/zed-infisical launcher that runs `infisical run -- zed` so the
#   key is injected fresh on every launch instead of living in a dotfile.

#
# SECURITY: per-user OpenRouter keys NEVER live in this template, in terraform,
# or in any shared location. Each member owns their own key on their own account.

set -euo pipefail

# --- Constants -------------------------------------------------------------
SLUG="dev_weown_devbox"
ENV_DIR="$HOME/.config/$SLUG"
ENV_FILE="$ENV_DIR/openrouter.env"
ZED_DIR="$HOME/.config/zed"
ZED_SETTINGS="$ZED_DIR/settings.json"
OPENROUTER_BASE_URL="https://openrouter.ai/api/v1"
# Guard line we add to the shell rc; grepped for to stay idempotent.
RC_GUARD="# >>> dev-weown-devbox openrouter env >>>"
RC_GUARD_END="# <<< dev-weown-devbox openrouter env <<<"


USE_INFISICAL=false
if [[ "${1:-}" == "--infisical" ]]; then
  USE_INFISICAL=true
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: setup-zed [--infisical]"
  echo "  (no args)     Simple path: store your OpenRouter key in $ENV_FILE."
  echo "  --infisical   Keep your key in your own Infisical account + launcher."
  exit 0
fi


# Refuse to run as root: this configures a PER-USER key. Running as root would
# write the key into /root and is never what we want on a shared box.
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "ERROR: run setup-zed as your own user, not root." >&2
  echo "       Your OpenRouter key is personal; it must live in your home dir." >&2
  exit 1
fi

log() { printf '==> %s\n' "$*"; }

# --- Step 1: prompt for the OpenRouter key ---------------------------------
# zsh-form first (read -rs "VAR?prompt"), bash-form fallback. The key is read
# silently; we trap EXIT to unset it so it never outlives this process, and we
# never echo it, log it, or place it in argv.
log "Setting up your OpenRouter API key for Zed AI"
echo "    Get a key at https://openrouter.ai/keys (starts with 'sk-or-')."
read -rs "OPENROUTER_API_KEY?Paste your OpenRouter API key: " 2>/dev/null \
  || read -rsp "Paste your OpenRouter API key: " OPENROUTER_API_KEY
echo
trap 'unset OPENROUTER_API_KEY' EXIT

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "ERROR: no key entered; nothing written." >&2
  exit 1
fi

# --- Step 2: write the key to the per-user env file (0600) -----------------
# umask 077 guarantees the file is created private even before chmod, closing
# the brief window where a freshly-created file could be world-readable.
mkdir -p "$ENV_DIR"
chmod 700 "$ENV_DIR" 2>/dev/null || true
(
  umask 077
  cat > "$ENV_FILE" <<EOF
# dev-weown-devbox per-user OpenRouter credentials for Zed AI.
# Written by setup-zed; DO NOT commit, share, or paste this anywhere.
# OPENAI_API_KEY is an alias because OpenRouter is OpenAI-API-compatible, so
# Zed's OpenAI-compatible provider can read the same key.
export OPENROUTER_API_KEY="$OPENROUTER_API_KEY"
export OPENAI_API_KEY="$OPENROUTER_API_KEY"
EOF
)
chmod 600 "$ENV_FILE"
log "Wrote your key to $ENV_FILE (mode 600, this account only)"

# --- Step 3: make the login shell source that env file (idempotent) --------
# default_shell is a copier var; we target the matching rc but also cover the
# other common one if it exists, so the env is present however you log in.

SHELL_RCS=("$HOME/.bashrc")
[[ -f "$HOME/.zshrc" ]] && SHELL_RCS+=("$HOME/.zshrc")


for rc in "${SHELL_RCS[@]}"; do
  if [[ -f "$rc" ]] && grep -qF "$RC_GUARD" "$rc"; then
    continue
  fi
  {
    printf '\n%s\n' "$RC_GUARD"
    printf '%s\n' "[ -f \"$ENV_FILE\" ] && . \"$ENV_FILE\""
    printf '%s\n' "$RC_GUARD_END"
  } >> "$rc"
  log "Sourced $ENV_FILE from $(basename "$rc")"
done

# Make it active in the CURRENT shell too, so the rest of this script (and an
# immediate `zed`/Infisical login) sees the key without re-login.
# shellcheck disable=SC1090
. "$ENV_FILE"

# --- Step 4: configure the Zed openrouter provider (NO key in settings) ----
# We only write the provider + base_url. Zed reads the key from OPENAI_API_KEY
# at runtime, so the secret never lands in settings.json.
mkdir -p "$ZED_DIR"
[[ -f "$ZED_SETTINGS" ]] || printf '{}\n' > "$ZED_SETTINGS"

# The desired provider block, as a JSON object we can merge or print.
read -r -d '' OPENROUTER_PROVIDER_JSON <<JSON || true
{
  "language_models": {
    "openai_compatible": {
      "openrouter": {
        "api_url": "$OPENROUTER_BASE_URL",
        "available_models": [
          {
            "name": "anthropic/claude-3.7-sonnet",
            "display_name": "Claude 3.7 Sonnet (OpenRouter)",
            "max_tokens": 200000
          },
          {
            "name": "openai/gpt-4o",
            "display_name": "GPT-4o (OpenRouter)",
            "max_tokens": 128000
          }
        ]
      }
    }
  }
}
JSON

if command -v jq >/dev/null 2>&1; then
  # Deep-merge our provider block into the existing settings, preserving any
  # other keys the member already set. `* ` is jq's recursive object merge.
  TMP_SETTINGS="$(mktemp "${ZED_SETTINGS}.XXXXXX")"
  if jq -e . "$ZED_SETTINGS" >/dev/null 2>&1; then
    jq --argjson add "$OPENROUTER_PROVIDER_JSON" '. * $add' "$ZED_SETTINGS" > "$TMP_SETTINGS" \
      && mv "$TMP_SETTINGS" "$ZED_SETTINGS" \
      && log "Merged the openrouter provider into $ZED_SETTINGS"
  else
    rm -f "$TMP_SETTINGS"
    echo "WARNING: $ZED_SETTINGS is not valid JSON; not touching it." >&2
    echo "         Add this block manually (no API key goes here):" >&2
    printf '%s\n' "$OPENROUTER_PROVIDER_JSON"
  fi
else
  log "jq not found; add this block to $ZED_SETTINGS manually (no API key goes here):"
  printf '%s\n' "$OPENROUTER_PROVIDER_JSON"
fi


# --- Optional: Infisical-backed path ---------------------------------------
# Secondary to the simple path above. Stores the key in the member's OWN
# Infisical account and installs a launcher that injects it at runtime.
if [[ "$USE_INFISICAL" == "true" ]]; then
  if ! command -v infisical >/dev/null 2>&1; then
    echo "ERROR: infisical CLI not found on this box; cannot use --infisical." >&2
    echo "       Use the simple path instead: run setup-zed with no arguments." >&2
    exit 1
  fi

  log "Optional Infisical path selected"
  echo "    This logs YOU in to YOUR Infisical account and stores the key there."
  read -r -p "    Your Infisical project ID (to hold the key): " INFISICAL_PROJECT_ID
  INFISICAL_ENV="${INFISICAL_ENV:-dev}"
  if [[ -z "${INFISICAL_PROJECT_ID:-}" ]]; then
    echo "ERROR: no project ID given; skipping Infisical setup. Simple path is already done." >&2
    exit 1
  fi

  # Interactive browser/device login under the MEMBER's own identity. We do not
  # capture or store any Infisical token here - the CLI manages its own session.
  log "Logging in to Infisical (follow the prompts)..."
  infisical login

  # Store the key as a secret WITHOUT putting it in argv (which would leak via
  # `ps`/shell history). `infisical secrets set` supports `NAME=@/path/to/file`,
  # reading the value from a file. We write the value to a private temp file
  # (umask 077), set both names from it, then shred it.
  SECRET_TMP="$(umask 077; mktemp)"
  printf '%s' "$OPENROUTER_API_KEY" > "$SECRET_TMP"
  if infisical secrets set "OPENROUTER_API_KEY=@$SECRET_TMP" "OPENAI_API_KEY=@$SECRET_TMP" \
        --projectId="$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENV" >/dev/null 2>&1; then
    log "Stored OPENROUTER_API_KEY + OPENAI_API_KEY in Infisical project $INFISICAL_PROJECT_ID ($INFISICAL_ENV)"
  else
    echo "WARNING: could not store secrets in Infisical (check your access)." >&2
    echo "         Your simple-path env file at $ENV_FILE still works." >&2
  fi
  rm -f "$SECRET_TMP"

  # Install a launcher that injects the key fresh from Infisical on each run,
  # so rotating the secret in Infisical takes effect without editing dotfiles.
  LAUNCHER_DIR="$HOME/.local/bin"
  LAUNCHER="$LAUNCHER_DIR/zed-infisical"
  mkdir -p "$LAUNCHER_DIR"
  cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
# Launch Zed with your OpenRouter key injected fresh from YOUR Infisical project.
# Installed by setup-zed --infisical for dev-weown-devbox.
set -euo pipefail
exec infisical run --projectId="$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENV" -- zed "\$@"
EOF
  chmod 0755 "$LAUNCHER"
  log "Installed launcher $LAUNCHER (run 'zed-infisical' to launch Zed with the injected key)"

  case ":$PATH:" in
    *":$LAUNCHER_DIR:"*) : ;;
    *) echo "    NOTE: $LAUNCHER_DIR is not on your PATH; add it or call $LAUNCHER directly." ;;
  esac
fi


# --- Closing note ----------------------------------------------------------
echo
log "Done. Your OpenRouter key is configured for the Zed remote server on this box."
cat <<'NOTE'

    IMPORTANT - Zed Remote Development is two-sided:
    Your LOCAL Zed connects over SSH and runs the remote server here, but Zed's
    AI assistant panel (the agent UI) runs CLIENT-SIDE, on your laptop. The key
    you just set lives only on this box. To use the assistant in your LOCAL Zed,
    configure the same provider there WITHOUT putting the key in settings.json:

      - In your LOCAL ~/.config/zed/settings.json add the OpenAI-compatible
        "openrouter" provider with ONLY the api_url (https://openrouter.ai/api/v1)
        and no key (exactly what this box just did for you), then
      - provide the key one of two safe ways:
          * enter it in Zed's Agent panel provider settings (Zed stores it in your
            OS keychain, encrypted -- NOT in settings.json), or
          * export OPENAI_API_KEY in the shell you launch your LOCAL Zed from.

    Never paste your key into settings.json or any shared/committed file.
NOTE
