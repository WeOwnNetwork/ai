#!/usr/bin/env bash
# dev-weown-devbox - Skinny Backup Script (shared dev box)
# Backs up each member's home directory under /home plus a small host-config
# snapshot. This is a DEVELOPER MACHINE, not a web app: there are no docker
# volumes to capture — the durable state is people's work in their home dirs.
#
# Usage:
#   Remote mode (from your laptop):
#     ./backup.sh root@droplet-ip
#   Local mode (on the droplet, already inside `infisical run`):
#     ./backup.sh
#
# This script is designed to run WITHIN `infisical run` so that secrets
# (SPACES_ACCESS_KEY, SPACES_SECRET_KEY) are available as environment variables.
# Do NOT run directly on the droplet without Infisical injection.
#
# What is backed up (into <name>.tar.gz, which unpacks to a <name>/ dir):
#   - home/home_<login>.tar.gz : one tar per member, rooted at the CONTENTS of
#     /home/<login>, EXCLUDING heavy regenerable caches (node_modules, .cache,
#     .npm, .cargo/registry, **/.venv, .local/share/zed, .zed_server) so backups
#     stay skinny.
#   - manifest.txt : one line per member ("<login> <uid> <gid> <archive>") so a
#     restore can recover ownership by UID even if the account was reassigned.
#   - etc.tar.gz : a curated /etc slice (sshd drop-in + the project's cron,
#     logrotate, and /etc/<slug> config), rooted at /etc contents.
#   - config/ : reproducibility metadata (ansible roster snapshot + the apt
#     package selection list). Informational; not auto-restored.
#
# What is NEVER backed up (secrets):
#   - /opt/<project>/.infisical-auth.env  (the box's Machine Identity creds)
#   - any *.env file in a member home
#   - any private SSH key (id_* without a .pub suffix) in a member home
#
# Retention policy (grandfather-father-son):
#   - Daily backups: retained for 30 days
#   - Monthly backups (1st of month): retained for 12 months
#   - Yearly backups (Jan 1st): kept forever
set -euo pipefail

REMOTE="${1:-}"
# Required for remote mode: the Infisical project ID for `infisical run`.
# Local mode runs inside `infisical run` already, so env is pre-set.
if [[ -n "$REMOTE" ]]; then
  : "${INFISICAL_PROJECT_ID:?Set INFISICAL_PROJECT_ID env var (same value as terraform.tfvars infisical_project_id) before running remote backup}"
fi
INFISICAL_ENV="${INFISICAL_ENV:-prod}"

PROJECT_NAME="dev_weown_devbox"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="dev-weown-devbox_backup_$TIMESTAMP"
WORK_DIR="$BACKUP_DIR/$BACKUP_NAME"

REMOTE_STORAGE="do-spaces"
SPACES_BUCKET="weown-prod-backups"
SPACES_REGION="atl1"

run_backup() {
  local host="$1"

  read -r -d '' BACKUP_CMDS <<'SCRIPT' || true
set -euo pipefail

PROJECT_NAME="dev_weown_devbox"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="dev-weown-devbox_backup_$TIMESTAMP"
WORK_DIR="$BACKUP_DIR/$BACKUP_NAME"

REMOTE_STORAGE="do-spaces"
SPACES_BUCKET="weown-prod-backups"
SPACES_REGION="atl1"

mkdir -p "$WORK_DIR" "$WORK_DIR/home"
echo "==> Creating backup: $BACKUP_NAME"

# manifest.txt — one line per backed-up member: "<login> <uid> <gid> <archive>".
# restore.sh shows it and, if an account is absent or its UID was reassigned at
# restore time, recovers ownership from column 2. Header lines start with '#'
# (restore's awk keys on the login in column 1, so headers are ignored).
MANIFEST="$WORK_DIR/manifest.txt"
{
  echo "# dev-weown-devbox backup manifest"
  echo "# created: $TIMESTAMP"
  echo "# login uid gid home_archive"
} > "$MANIFEST"

# --- Member home backups -------------------------------------------------
# One tar per /home/<user>. We exclude regenerable caches to keep backups
# skinny, and we HARD-exclude secrets (env files + private SSH keys) so a
# credential never lands in a backup archive or in DO Spaces.
#
# Each per-member tar is rooted at the CONTENTS of that member's home
# (`tar -C "$HOME_PATH" .`) so restore.sh extracts straight into /home/<login>
# without nesting. The `*/`-prefixed excludes are depth-agnostic, so they still
# match caches/secrets anywhere in the tree (including the home root).
HOME_EXCLUDES=(
  # Heavy regenerable caches (anywhere in the tree)
  --exclude='*/node_modules'
  --exclude='*/.cache'
  --exclude='*/.npm'
  --exclude='*/.cargo/registry'
  --exclude='*/.venv'
  --exclude='*/.local/share/zed'
  --exclude='*/.zed_server'
  --exclude='*/.zed-server'
  # Secrets — NEVER back these up
  --exclude='*.env'
  --exclude='*/.infisical-auth.env'
  # Private SSH keys: exclude the whole .ssh dir EXCEPT public keys +
  # known_hosts (a member's authorized_keys is reconstructed by ansible from
  # members.yml, so losing it in a backup is harmless; private keys must never
  # leave the box).
  --exclude='*/.ssh/id_*'
  --exclude='*/.ssh/*_rsa'
  --exclude='*/.ssh/*_dsa'
  --exclude='*/.ssh/*_ecdsa'
  --exclude='*/.ssh/*_ed25519'
  --exclude='*/.gnupg/*.key'
)

if [[ -d /home ]]; then
  # Iterate real member homes only (skip lost+found and non-dirs).
  for HOME_PATH in /home/*; do
    [[ -d "$HOME_PATH" ]] || continue
    USER_NAME=$(basename "$HOME_PATH")
    [[ "$USER_NAME" == "lost+found" ]] && continue
    echo "==> Backing up home: $USER_NAME"
    # `|| echo WARNING` on tar: a file vanishing mid-backup (exit 1) or a perms
    # hiccup should not abort the whole run for every other member.
    tar czf "$WORK_DIR/home/home_${USER_NAME}.tar.gz" \
      "${HOME_EXCLUDES[@]}" \
      -C "$HOME_PATH" . || echo "    WARNING: tar reported issues for $USER_NAME (continuing)"
    # Record login -> uid/gid for restore's ownership fallback. id(1) works
    # because the account exists at backup time; stat the home dir as a fallback.
    USER_UID=$(id -u "$USER_NAME" 2>/dev/null || stat -c %u "$HOME_PATH")
    USER_GID=$(id -g "$USER_NAME" 2>/dev/null || stat -c %g "$HOME_PATH")
    echo "$USER_NAME $USER_UID $USER_GID home/home_${USER_NAME}.tar.gz" >> "$MANIFEST"
  done
else
  echo "WARNING: /home does not exist; no member homes to back up."
fi

# --- Curated /etc snapshot ------------------------------------------------
# restore.sh restores this with `tar -C /etc`, so it must be rooted at /etc
# contents. Capture the slice the box's identity depends on: the sshd hardening
# drop-in, plus the cron + logrotate + config dir this project installs. Only
# paths that exist are included (a pre-deploy box may have none, in which case
# no etc.tar.gz is written and restore.sh simply skips its /etc step).
echo "==> Capturing curated /etc snapshot..."
ETC_PATHS=()
for p in "ssh/sshd_config.d" \
         "cron.daily/${PROJECT_NAME}-backup" \
         "logrotate.d/${PROJECT_NAME}-backup" \
         "${PROJECT_NAME}"; do
  [[ -e "/etc/$p" ]] && ETC_PATHS+=("$p")
done
# NOTE: do not use a bash array-length test here — that syntax contains a
# brace-hash pair that copier/Jinja reads as a comment opener, which breaks
# rendering even inside this single-quoted heredoc. The [*] non-empty test
# below is equivalent and template-safe.
if [[ -n "${ETC_PATHS[*]:-}" ]]; then
  tar czf "$WORK_DIR/etc.tar.gz" -C /etc "${ETC_PATHS[@]}" \
    || echo "    WARNING: /etc snapshot tar reported issues (continuing)"
else
  echo "    (no curated /etc paths present yet — skipping etc.tar.gz)"
fi

# --- Reproducibility metadata (informational; not auto-restored) ----------
CONFIG_DIR="$WORK_DIR/config"
mkdir -p "$CONFIG_DIR"
# Rendered ansible roster snapshot, if deploy.yml wrote one (public keys only).
if [[ -f "$APP_DIR/members.snapshot.yml" ]]; then
  cp -a "$APP_DIR/members.snapshot.yml" "$CONFIG_DIR/members.snapshot.yml" || true
fi
# apt package selections, so the dev toolchain can be reproduced.
dpkg --get-selections > "$CONFIG_DIR/dpkg-selections.txt" 2>/dev/null || \
  echo "    WARNING: dpkg --get-selections failed (continuing)"

# --- Compress ------------------------------------------------------------
echo "==> Compressing backup..."
cd "$BACKUP_DIR"
tar czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
rm -rf "$WORK_DIR"

FINAL_SIZE=$(ls -lh "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" | awk '{print $5}')
echo "==> Local backup complete: $BACKUP_DIR/${BACKUP_NAME}.tar.gz ($FINAL_SIZE)"

# --- Remote upload (DO Spaces) -------------------------------------------
if [[ "$REMOTE_STORAGE" == "do-spaces" ]]; then
  if [[ -z "${SPACES_ACCESS_KEY:-}" ]] || [[ -z "${SPACES_SECRET_KEY:-}" ]]; then
    echo "WARNING: SPACES_ACCESS_KEY or SPACES_SECRET_KEY not set. Skipping remote upload."
  else
    echo "==> Uploading to DO Spaces (s3://${SPACES_BUCKET}/dev-weown-devbox/)..."
    AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY" \
    AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_KEY" \
    aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" \
      "s3://${SPACES_BUCKET}/dev-weown-devbox/" \
      --endpoint-url "https://${SPACES_REGION}.digitaloceanspaces.com" \
      --quiet
    echo "==> Remote backup uploaded successfully"
  fi
fi

# --- Grandfather-Father-Son retention ------------------------------------
echo "==> Applying retention policy (daily 30d / monthly 12mo / yearly forever)..."
find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" | while read -r f; do
  BASENAME=$(basename "$f")
  if [[ "$BASENAME" =~ _backup_([0-9]{8})_([0-9]{6})\.tar\.gz$ ]]; then
    FILE_DATE="${BASH_REMATCH[1]}"
    YEAR="${FILE_DATE:0:4}"
    MONTH="${FILE_DATE:4:2}"
    DAY="${FILE_DATE:6:2}"

    FILE_EPOCH=$(date -d "$YEAR-$MONTH-$DAY" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    AGE_DAYS=$(( (NOW_EPOCH - FILE_EPOCH) / 86400 ))

    KEEP=false
    if [[ $AGE_DAYS -lt 30 ]]; then
      KEEP=true
    elif [[ $AGE_DAYS -lt 365 && "$DAY" == "01" ]]; then
      KEEP=true
    elif [[ "$DAY" == "01" && "$MONTH" == "01" ]]; then
      KEEP=true
    fi

    if [[ "$KEEP" == "false" ]]; then
      echo "    Removing $BASENAME (${AGE_DAYS}d old)"
      rm -f "$f"
    fi
  fi
done
echo "==> Retention cleanup complete"
SCRIPT

  if [[ -n "$host" ]]; then
    echo "==> Running backup on remote: ${host}"
    # Wrap in `infisical run` so SPACES_ACCESS_KEY / SPACES_SECRET_KEY are
    # in the inner shell's env when the S3 upload step runs. The Machine
    # Identity creds live at /opt/<project>/.infisical-auth.env (0600 root)
    # written by cloud-init.
    # Invoke the DROPLET'S backup.sh (uploaded earlier by ansible) inside
    # `infisical run` so SPACES_* secrets are in env. Passing the script
    # body via `bash -c '$BACKUP_CMDS'` would break here because BACKUP_CMDS
    # contains literal single quotes (the tar exclude patterns).
    ssh "$host" \
      "INFISICAL_PROJECT_ID='$INFISICAL_PROJECT_ID' INFISICAL_ENV='$INFISICAL_ENV' PROJECT_NAME='$PROJECT_NAME' bash -s" <<'EOF'
set -euo pipefail
source "/opt/$PROJECT_NAME/.infisical-auth.env"
infisical login --method=universal-auth \
  --clientId="$INFISICAL_CLIENT_ID" \
  --clientSecret="$INFISICAL_CLIENT_SECRET" \
  --silent
exec infisical run --projectId="$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENV" \
  -- "/opt/$PROJECT_NAME/backup.sh"
EOF

    # Optionally pull the backup locally
    read -p "Pull backup to local machine? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      LOCAL_BACKUP_DIR="$(dirname "$SCRIPT_DIR")/backups"
      mkdir -p "$LOCAL_BACKUP_DIR"

      LATEST_BACKUP=$(ssh "$host" "ls -t ${BACKUP_DIR}/*.tar.gz 2>/dev/null | head -1")
      if [[ -n "$LATEST_BACKUP" ]]; then
        echo "==> Downloading: $(basename "$LATEST_BACKUP")"
        scp "$host:$LATEST_BACKUP" "$LOCAL_BACKUP_DIR/"
        echo "==> Saved to: $LOCAL_BACKUP_DIR/$(basename "$LATEST_BACKUP")"
      else
        echo "WARNING: No backup files found on remote"
      fi
    fi
  else
    echo "==> Running backup locally"
    # Run the body as a real script (not `eval`) so there is no second shell
    # parse of copier-rendered values. The body is self-contained and reads
    # secrets (SPACES_*) from the environment, which the child shell inherits.
    local _bk_tmp
    _bk_tmp="$(mktemp "${TMPDIR:-/tmp}/dev-weown-devbox-backup.XXXXXX")"
    printf '%s\n' "$BACKUP_CMDS" > "$_bk_tmp"
    bash "$_bk_tmp"
    rm -f "$_bk_tmp"
  fi
}

# Main
run_backup "$REMOTE"

echo ""
echo "=== BACKUP FINISHED ==="
echo ""
echo "To restore from this backup:"
echo "  ./scripts/restore.sh ${REMOTE:-<host>} $BACKUP_NAME"
echo ""
echo "To list remote backups (DO Spaces):"
echo "  aws s3 ls s3://${SPACES_BUCKET}/dev-weown-devbox/ --endpoint-url https://${SPACES_REGION}.digitaloceanspaces.com"
