#!/usr/bin/env bash
# allm-admin-account.sh — create (or reset) an AnythingLLM ADMIN account on a
# deployed instance, without any secret crossing an agent's context, argv, a
# log, or the operator's screen.
#
# WHY THIS EXISTS (2026-09-01): chat.weown.dev had exactly ONE user —
# `a-cto_dev` — whose password nobody available held. Nobody could reach the
# admin UI to add a teammate, so the customer-facing bot on ocpa.group could
# not be edited at all. AnythingLLM ships no self-service admin recovery, and
# the credential is a bcrypt hash in the app DB — not something a redeploy can
# re-inject from the secret store. This is the break-glass path, committed so
# it is auditable and repeatable instead of hand-carried.
#
# It CREATES a new admin by default and never touches an existing account:
# resetting an unknown account can lock out whoever actually holds it.
# Pass --reset to deliberately overwrite the named user's password.
#
# The password is read with `read -rs` and travels operator -> ssh stdin ->
# `docker exec -i` stdin -> node. It is never an argument, never echoed, never
# written to disk, and never visible in `ps` on either machine.
#
# Usage:
#   ./allm-admin-account.sh <ssh-target> <container> <username> [--reset]
# Example:
#   ./allm-admin-account.sh root@203.0.113.10 weown_chat_sales-anythingllm-1 someone@example.com
set -euo pipefail

TARGET="${1:?usage: allm-admin-account.sh <ssh-target> <container> <username> [--reset]}"
CONTAINER="${2:?container name required (docker ps --format '{{.Names}}')}"
USERNAME="${3:?username required}"
MODE="create"
[[ "${4:-}" == "--reset" ]] && MODE="reset"

# zsh-safe prompt: `read -p` is a coprocess operator in zsh, not a prompt.
printf 'New password for %s (min 8 chars, hidden): ' "$USERNAME" >&2
read -rs PW; echo >&2
printf 'Confirm: ' >&2
read -rs PW2; echo >&2
[[ "$PW" == "$PW2" ]] || { echo "ERROR: passwords do not match" >&2; exit 1; }
[[ ${#PW} -ge 8 ]] || { echo "ERROR: AnythingLLM requires at least 8 characters" >&2; exit 1; }
unset PW2

JS_LOCAL="$(mktemp -t allm-admin)"
trap 'rm -f "$JS_LOCAL"' EXIT
cat > "$JS_LOCAL" <<'JS'
const fs = require("fs");
const bcrypt = require("bcryptjs");
const { PrismaClient } = require("@prisma/client");
const p = new PrismaClient();
const pw = fs.readFileSync(0, "utf8");
const username = process.env.ALLM_USERNAME;
const mode = process.env.ALLM_MODE;
(async () => {
  const existing = await p.users.findFirst({ where: { username } });
  if (existing && mode !== "reset") {
    console.log("EXISTS: user already present — re-run with --reset to change its password");
    process.exit(2);
  }
  // bcrypt cost 10 — the same factor AnythingLLM's own User model uses, so the
  // row is indistinguishable from one the app itself created.
  const hash = bcrypt.hashSync(pw, 10);
  const row = existing
    ? await p.users.update({ where: { id: existing.id }, data: { password: hash, role: "admin", suspended: 0 } })
    : await p.users.create({ data: { username, password: hash, role: "admin" } });
  console.log("OK: " + (mode === "reset" ? "reset" : "created") + " admin '" + row.username + "' (id " + row.id + ")");
  process.exit(0);
})().catch((e) => { console.log("ERROR: " + e.message); process.exit(1); });
JS

# Stage the helper on the box, then feed the password in on stdin. Neither hop
# carries the value in an argument.
#
# NODE_PATH is REQUIRED, not belt-and-braces: node resolves `require` from the
# SCRIPT's directory upward, not from the cwd, so a helper sitting in /tmp
# cannot see /app/server/node_modules however the shell is cd'd
# (2026-09-01: "Cannot find module 'bcryptjs'" with `cd /app/server` right
# there in the command).
#
# Cleanup runs as -u 0 because the container's app user is uid 1000 and
# `docker cp` lands the file owned by root — the in-container rm failed with
# EPERM and left the helper behind.
ssh "$TARGET" "cat > /tmp/allm-admin.js" < "$JS_LOCAL"
printf '%s' "$PW" | ssh "$TARGET" "docker cp /tmp/allm-admin.js ${CONTAINER}:/tmp/allm-admin.js >/dev/null \
  && docker exec -i -e NODE_PATH=/app/server/node_modules \
       -e ALLM_USERNAME='${USERNAME}' -e ALLM_MODE='${MODE}' ${CONTAINER} \
       node /tmp/allm-admin.js; \
  rc=\$?; \
  docker exec -u 0 ${CONTAINER} rm -f /tmp/allm-admin.js >/dev/null 2>&1; \
  rm -f /tmp/allm-admin.js; exit \$rc"
RC=$?
unset PW
exit "$RC"
