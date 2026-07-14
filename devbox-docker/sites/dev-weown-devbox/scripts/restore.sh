#!/usr/bin/env bash
# dev-weown-devbox - Skinny Restore Script
# Restores a skinny backup produced by scripts/backup.sh: member home
# directories (/home/<login>) and the /etc config snapshot.
#
# Usage:
#   Remote mode (from your laptop):
#     INFISICAL_PROJECT_ID=<id> ./restore.sh root@droplet-ip <backup-name>
#   Local mode (on the droplet, already inside `infisical run`):
#     ./restore.sh <backup-name>
#
# This script restores DATA, not the box itself. The droplet, the `devs`
# group, and the member accounts are created by Terraform + ansible — re-run
# `tofu apply` then `ansible-playbook` first if the box was rebuilt, THEN run
# this to put each member's home directory back. Home archives are restored to
# /home/<login> with ownership taken from the live account (so it works even
# if UIDs were reassigned), falling back to the UID recorded in the manifest.
#
# Remote mode wraps the DROPLET's own restore.sh in `infisical run` so the
# DO Spaces fetch keys (SPACES_ACCESS_KEY / SPACES_SECRET_KEY) are injected at
# runtime — exactly like backup.sh. Local mode assumes it is already running
# inside `infisical run` (so its env already has SPACES_*).
#
# Backups can be specified as:
#   - Local backup name:  dev-weown-devbox_backup_20260115_120000
#     (the script fetches <name>.tar.gz from DO Spaces if not present locally)
set -euo pipefail

REMOTE=""
BACKUP_NAME=""

if [[ $# -eq 2 ]]; then
  REMOTE="$1"
  BACKUP_NAME="$2"
elif [[ $# -eq 1 ]]; then
  BACKUP_NAME="$1"
else
  echo "Usage (remote): INFISICAL_PROJECT_ID=<id> $0 [user@host] <backup-name>"
  echo "Usage (local):  $0 <backup-name>   # run on the droplet, already inside infisical run"
  echo ""
  echo "Examples:"
  echo "  INFISICAL_PROJECT_ID=abc123 $0 root@203.0.113.42 dev-weown-devbox_backup_20260115_120000"
  echo "  $0 dev-weown-devbox_backup_20260115_120000"
  exit 1
fi

# Remote mode needs the Infisical project ID to wrap the droplet's restore.sh
# in `infisical run`. Local mode is already running inside `infisical run`
# (operator invokes via `infisical run -- ./restore.sh`) so its parent env
# already has SPACES_* — the script does not need to know the projectId.
if [[ -n "$REMOTE" ]]; then
  : "${INFISICAL_PROJECT_ID:?Set INFISICAL_PROJECT_ID env var before running remote restore (same value as terraform.tfvars infisical_project_id)}"
fi
INFISICAL_ENV="${INFISICAL_ENV:-prod}"

# Validate BACKUP_NAME FIRST — it is interpolated into the remote `ssh ... bash`
# heredoc and into shell-glob/path contexts below. backup.sh names archives
# `<project>_backup_YYYYMMDD_HHMMSS` so a strict allowlist (no `/`, no spaces,
# no shell metacharacters) is both sufficient and injection-proof.
if [[ ! "$BACKUP_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: invalid BACKUP_NAME (allowed: [A-Za-z0-9._-]): $BACKUP_NAME" >&2
  exit 1
fi

PROJECT_NAME="dev_weown_devbox"
APP_DIR="/opt/$PROJECT_NAME"
BACKUP_DIR="$APP_DIR/backups"
REMOTE_STORAGE="do-spaces"
SPACES_BUCKET="weown-prod-backups"
SPACES_REGION="atl1"

run_restore() {
  local host="$1"
  local backup_name="$2"

  # The body that actually runs ON the droplet. backup_name is substituted by
  # the OUTER shell here (the heredoc is unquoted), but it has already passed
  # the strict ^[A-Za-z0-9._-]+$ allowlist above, so the interpolation is safe.
  # Everything that must survive to the INNER shell is escaped with `\$`.
  read -r -d '' RESTORE_CMDS <<SCRIPT || true
set -euo pipefail

PROJECT_NAME="dev_weown_devbox"
APP_DIR="/opt/\$PROJECT_NAME"
BACKUP_DIR="\$APP_DIR/backups"

BACKUP_NAME="$backup_name"
BACKUP_FILE="\$BACKUP_DIR/\${BACKUP_NAME}.tar.gz"
WORK_DIR="\$BACKUP_DIR/\${BACKUP_NAME}"

REMOTE_STORAGE="do-spaces"
SPACES_BUCKET="weown-prod-backups"
SPACES_REGION="atl1"

# Restoring DATA requires root: we write into other users' home directories
# and chown them. Local mode is invoked under \`infisical run\` which preserves
# the invoking user — make the requirement explicit instead of failing on the
# first permission error.
if [[ "\$(id -u)" -ne 0 ]]; then
  echo "ERROR: restore must run as root (writes to /home/<login> and chowns). Use sudo / the break-glass root account." >&2
  exit 1
fi

# --- Fetch backup from DO Spaces if not present locally ---
if [[ ! -f "\$BACKUP_FILE" && "\$REMOTE_STORAGE" == "do-spaces" && -n "\${SPACES_ACCESS_KEY:-}" && -n "\${SPACES_SECRET_KEY:-}" ]]; then
  echo "==> Backup not found locally, fetching from DO Spaces..."
  mkdir -p "\$BACKUP_DIR"
  AWS_ACCESS_KEY_ID="\$SPACES_ACCESS_KEY" \\
  AWS_SECRET_ACCESS_KEY="\$SPACES_SECRET_KEY" \\
  aws s3 cp "s3://\${SPACES_BUCKET}/dev-weown-devbox/\${BACKUP_NAME}.tar.gz" \\
    "\$BACKUP_FILE" \\
    --endpoint-url "https://\${SPACES_REGION}.digitaloceanspaces.com" \\
    --quiet
  echo "==> Downloaded from DO Spaces"
fi

if [[ ! -f "\$BACKUP_FILE" ]]; then
  echo "ERROR: Backup not found: \$BACKUP_FILE"
  echo "Available local backups:"
  ls -1 "\$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "  (none)"
  exit 1
fi

echo "==> Restoring dev-weown-devbox from \$BACKUP_NAME"
echo ""

# --- Extract the outer archive into the work dir ---
echo "==> Extracting archive..."
cd "\$BACKUP_DIR"
rm -rf "\$WORK_DIR"
tar xzf "\${BACKUP_NAME}.tar.gz"
# backup.sh wraps everything in a top-level dir == \$BACKUP_NAME. Tolerate an
# archive that was created without that wrapping (contents at the root).
if [[ ! -d "\$WORK_DIR" ]]; then
  WORK_DIR="\$BACKUP_DIR"
fi

# --- Show what the backup contains (manifest is informational only) ---
if [[ -f "\$WORK_DIR/manifest.txt" ]]; then
  echo "==> Backup manifest:"
  sed 's/^/    /' "\$WORK_DIR/manifest.txt"
  echo ""
fi

# --- Restore member home directories ---
# backup.sh stores one archive per member at home/home_<login>.tar.gz, each
# rooted at the contents of that member's home (created with \`tar -C /home/<login> .\`).
# We restore into /home/<login> and chown to that account.
HOME_ARCHIVE_DIR="\$WORK_DIR/home"
restored_any=false
if [[ -d "\$HOME_ARCHIVE_DIR" ]]; then
  for archive in "\$HOME_ARCHIVE_DIR"/home_*.tar.gz; do
    [[ -e "\$archive" ]] || continue   # nullglob-safe: skip the literal pattern
    base="\$(basename "\$archive")"
    # Strip the home_ prefix and .tar.gz suffix to recover the login.
    login="\${base#home_}"
    login="\${login%.tar.gz}"

    # Defensive: only restore well-formed Linux logins (the archive name is
    # operator/backup-controlled, but validate before using it as a path).
    if [[ ! "\$login" =~ ^[a-z_][a-z0-9_-]*\$ ]]; then
      echo "    WARN: skipping archive with unexpected login '\$login' (\$base)"
      continue
    fi

    target="/home/\$login"
    echo "==> Member: \$login  (-> \$target)"

    # Resolve ownership from the LIVE account first (survives UID reassignment);
    # fall back to the UID recorded in the manifest if the account is absent.
    if id "\$login" >/dev/null 2>&1; then
      owner_uid="\$(id -u "\$login")"
      owner_gid="\$(id -g "\$login")"
    else
      owner_uid="\$(awk -v u="\$login" '\$1==u {print \$2}' "\$WORK_DIR/manifest.txt" 2>/dev/null || true)"
      owner_gid=""
      if [[ -z "\$owner_uid" ]]; then
        echo "    WARN: account '\$login' does not exist and no UID in manifest."
        echo "          Create the account (edit ansible/members.yml + re-run deploy) and re-run restore."
        echo "          Skipping \$login."
        continue
      fi
      echo "    NOTE: account '\$login' absent; restoring with UID \$owner_uid from manifest."
    fi

    mkdir -p "\$target"

    # Confirm-before-overwrite: a non-empty home means we are about to clobber
    # live data. Default to NO. CONFIRM_OVERWRITE=yes skips the prompt (for the
    # operator who has already decided), e.g. a full DR restore onto a fresh box.
    if [[ -n "\$(ls -A "\$target" 2>/dev/null)" ]]; then
      if [[ "\${CONFIRM_OVERWRITE:-}" == "yes" ]]; then
        echo "    \$target is non-empty; CONFIRM_OVERWRITE=yes -> overwriting."
      else
        printf '    %s already contains files. Overwrite from backup? [y/N] ' "\$target"
        read -r reply </dev/tty 2>/dev/null || reply=""
        if [[ ! "\$reply" =~ ^[Yy]\$ ]]; then
          echo "    Skipped \$login (left existing home untouched)."
          continue
        fi
      fi
    fi

    # Extract the member's home contents into their home directory.
    tar xzf "\$archive" -C "\$target"

    # Fix ownership. -R is correct: every file in a home dir belongs to the
    # member. Use numeric uid[:gid] so it works whether or not the group exists.
    if [[ -n "\$owner_gid" ]]; then
      chown -R "\$owner_uid:\$owner_gid" "\$target"
    else
      chown -R "\$owner_uid" "\$target"
    fi
    echo "    Restored \$login"
    restored_any=true
  done
else
  echo "==> No home/ directory in backup — nothing to restore for member homes."
fi

# --- Restore /etc config snapshot (optional, prompted) ---
# The skinny backup snapshots a curated slice of /etc (sshd drop-in, cron,
# logrotate). Restoring it over a LIVE, reconciled box is rarely what you want
# (ansible owns those files), so it is opt-in and defaults to NO.
if [[ -f "\$WORK_DIR/etc.tar.gz" ]]; then
  do_etc=false
  if [[ "\${RESTORE_ETC:-}" == "yes" ]]; then
    do_etc=true
  else
    printf '==> Backup contains an /etc snapshot. Restore it over the live /etc? [y/N] '
    read -r reply </dev/tty 2>/dev/null || reply=""
    [[ "\$reply" =~ ^[Yy]\$ ]] && do_etc=true
  fi
  if [[ "\$do_etc" == true ]]; then
    echo "==> Restoring /etc snapshot..."
    tar xzf "\$WORK_DIR/etc.tar.gz" -C /etc
    echo "    /etc snapshot restored. Re-run ansible to reconcile managed files,"
    echo "    and 'sshd -t && systemctl restart ssh' if you changed sshd config."
  else
    echo "==> Skipped /etc snapshot (ansible owns those files; re-run deploy instead)."
  fi
fi

# --- Cleanup ---
echo "==> Cleaning up..."
if [[ "\$WORK_DIR" != "\$BACKUP_DIR" ]]; then
  rm -rf "\$WORK_DIR"
fi

echo ""
echo "=== RESTORE COMPLETE ==="
echo "    Backup: \$BACKUP_NAME"
if [[ "\$restored_any" == true ]]; then
  echo "    Member homes restored. Ask each member to reconnect their Zed remote"
  echo "    session and re-run 'setup-zed' if their OpenRouter env was not in the backup."
else
  echo "    No member homes were restored (none in backup, or all skipped)."
fi
echo ""
SCRIPT

  if [[ -n "$host" ]]; then
    echo "==> Running restore on remote: ${host}"
    # Invoke the DROPLET's restore.sh (uploaded by ansible) inside
    # `infisical run`, mirroring backup.sh. Passing the script body via
    # `bash -c '$RESTORE_CMDS'` would be unsafe AND broken (it contains literal
    # single quotes), so instead we ssh a small bootstrap heredoc that:
    #   1. sources /opt/<project>/.infisical-auth.env (Machine Identity, 0600 root,
    #      written by cloud-init),
    #   2. `infisical login` to seed the CLI session,
    #   3. exec's the droplet's restore.sh inside `infisical run` with the
    #      backup name as a positional arg (already allowlist-validated above).
    # `-t` allocates a TTY so the confirm-before-overwrite prompt (read </dev/tty)
    # works through the SSH session.
    ssh -t "$host" \
      "INFISICAL_PROJECT_ID='$INFISICAL_PROJECT_ID' INFISICAL_ENV='$INFISICAL_ENV' PROJECT_NAME='dev_weown_devbox' BACKUP_NAME='$BACKUP_NAME' CONFIRM_OVERWRITE='${CONFIRM_OVERWRITE:-}' RESTORE_ETC='${RESTORE_ETC:-}' bash -s" <<'EOF'
set -euo pipefail
source "/opt/$PROJECT_NAME/.infisical-auth.env"
infisical login --method=universal-auth \
  --clientId="$INFISICAL_CLIENT_ID" \
  --clientSecret="$INFISICAL_CLIENT_SECRET" \
  --silent
exec infisical run --projectId="$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENV" \
  -- env CONFIRM_OVERWRITE="$CONFIRM_OVERWRITE" RESTORE_ETC="$RESTORE_ETC" \
  "/opt/$PROJECT_NAME/restore.sh" "$BACKUP_NAME"
EOF
  else
    echo "==> Running restore locally"
    # Run the body as a real script (not `eval`) — no second shell parse of the
    # rendered/validated values. The body reads SPACES_* / CONFIRM_OVERWRITE /
    # RESTORE_ETC from the environment, which the child shell inherits.
    local _rs_tmp
    _rs_tmp="$(mktemp "${TMPDIR:-/tmp}/dev-weown-devbox-restore.XXXXXX")"
    printf '%s\n' "$RESTORE_CMDS" > "$_rs_tmp"
    bash "$_rs_tmp"
    rm -f "$_rs_tmp"
  fi
}

echo "==> Restore requested: $BACKUP_NAME"
run_restore "$REMOTE" "$BACKUP_NAME"
