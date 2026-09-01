#!/usr/bin/env bash
# allm-user-rename.sh — rename an AnythingLLM user in place (username only;
# password, role, workspaces and chat history are untouched).
#
#   ./allm-user-rename.sh <ssh-target> <container> <old-username> <new-username>
#
# WHY (2026-09-01): WeOwn's FedArc convention D35 names person accounts
# `a-<ccc>_dev` (admin class) / `u-<ccc>_user` (daily-user class) — never an
# email address. Two instances were bootstrapped with email-shaped accounts
# before that was read; AnythingLLM has no rename in its UI, and deleting +
# recreating loses the account's workspace memberships and history. This is
# the committed, reviewable way to correct a name. No secret is read or
# written: it touches the `username` column and prints the user list after.
set -euo pipefail

TARGET="${1:?usage: allm-user-rename.sh <ssh-target> <container> <old-username> <new-username>}"
CONTAINER="${2:?container name required}"
OLD="${3:?old username required}"
NEW="${4:?new username required}"
[[ "$NEW" =~ ^[a-z0-9._@-]+$ ]] || { echo "ERROR: new username has characters AnythingLLM rejects: $NEW" >&2; exit 1; }

JS_LOCAL="$(mktemp -t allm-rename)"
trap 'rm -f "$JS_LOCAL"' EXIT
cat > "$JS_LOCAL" <<'JS'
const { PrismaClient } = require("@prisma/client");
const p = new PrismaClient();
const OLD = process.env.ALLM_OLD, NEW = process.env.ALLM_NEW;
(async () => {
  const u = await p.users.findFirst({ where: { username: OLD } });
  if (!u) { console.log("ERROR: no user named '" + OLD + "'"); process.exit(2); }
  if (await p.users.findFirst({ where: { username: NEW } })) { console.log("ERROR: '" + NEW + "' already exists"); process.exit(3); }
  await p.users.update({ where: { id: u.id }, data: { username: NEW } });
  const all = await p.users.findMany({ select: { id: true, username: true, role: true } });
  console.log("OK: renamed '" + OLD + "' -> '" + NEW + "' (id " + u.id + ", role " + u.role + ")");
  console.log("users now: " + all.map(x => x.username + "(" + x.role + ")").join(", "));
  process.exit(0);
})().catch((e) => { console.log("ERROR: " + e.message); process.exit(1); });
JS

# Same delivery shape as allm-admin-account.sh: helper staged on the box,
# NODE_PATH so /tmp can see the app's node_modules, root-run cleanup.
ssh "$TARGET" "cat > /tmp/allm-rename.js" < "$JS_LOCAL"
ssh "$TARGET" "docker cp /tmp/allm-rename.js ${CONTAINER}:/tmp/allm-rename.js >/dev/null \
  && docker exec -e NODE_PATH=/app/server/node_modules -e ALLM_OLD='${OLD}' -e ALLM_NEW='${NEW}' ${CONTAINER} node /tmp/allm-rename.js; \
  rc=\$?; docker exec -u 0 ${CONTAINER} rm -f /tmp/allm-rename.js >/dev/null 2>&1; rm -f /tmp/allm-rename.js; exit \$rc"
