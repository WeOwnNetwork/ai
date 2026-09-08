#!/usr/bin/env bash
# allm-set-role.sh — change an EXISTING AnythingLLM user's role in place
# (admin | manager | default). The account, its password, workspaces and chat
# history stay intact: WeOwn's standing policy is that ALLM accounts are never
# deleted on offboarding — they are demoted and credentials rotated.
#
#   ./allm-set-role.sh <ssh-target> <container> <username> <role|suspend|unsuspend> [--yes]
#   ./allm-set-role.sh root@203.0.113.10 weown_chat_sales-anythingllm-1 a-someone_dev default --yes
#
# WHY (2026-09-08): offboarding needed an admin DEMOTED on two instances and
# nothing scripted could do it — allm-admin-account.sh creates/resets, the UI
# is a click, and a click leaves no record. Sibling of allm-user-rename.sh.
#
# Identity guard (four wrong attributions on 2026-09-07 came from look-alike
# names): the target's id / username / current role / created date / workspace
# count are PRINTED first and nothing changes without --yes. Refuses to demote
# the LAST admin (that locks everyone out). Idempotent: same role = no-op.
# `suspend` / `unsuspend` flip AnythingLLM's own `suspended` flag instead of the
# role: login refused, account/workspaces/history intact — the disable-over-delete
# shape for offboarding (a demotion alone still lets the person log in).
# No secret is read, written, or passed — the script touches `role` / `suspended`.
set -euo pipefail

TARGET="${1:?usage: allm-set-role.sh <ssh-target> <container> <username> <admin|manager|default> [--yes]}"
CONTAINER="${2:?container name required}"
USERNAME="${3:?username required}"
ROLE="${4:?role required: admin | manager | default | suspend | unsuspend}"
YES="${5:-}"
case "$ROLE" in admin|manager|default|suspend|unsuspend) ;; *) echo "ERROR: role must be admin | manager | default | suspend | unsuspend (got '$ROLE')" >&2; exit 1 ;; esac
[[ "$USERNAME" =~ ^[a-z0-9._@-]+$ ]] || { echo "ERROR: username has characters AnythingLLM rejects: $USERNAME" >&2; exit 1; }
[[ "$TARGET" =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9._:-]+$ ]] || { echo "ERROR: ssh target must be user@host" >&2; exit 1; }
[[ "$CONTAINER" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "ERROR: bad container name" >&2; exit 1; }
APPLY=0; [[ "$YES" == "--yes" ]] && APPLY=1

JS_LOCAL="$(mktemp -t allm-setrole)"
trap 'rm -f "$JS_LOCAL"' EXIT
cat > "$JS_LOCAL" <<'JS'
const { PrismaClient } = require("@prisma/client");
const p = new PrismaClient();
const U = process.env.ALLM_USER, ROLE = process.env.ALLM_ROLE, APPLY = process.env.ALLM_APPLY === "1";
(async () => {
  const u = await p.users.findFirst({ where: { username: U } });
  if (!u) { console.log("ERROR: no user named '" + U + "'"); process.exit(2); }
  const ws = await p.workspace_users.count({ where: { user_id: u.id } }).catch(() => -1);
  const admins = await p.users.findMany({ where: { role: "admin" }, select: { username: true } });
  console.log("IDENTITY id=" + u.id + " username=" + u.username + " role=" + u.role + " created=" + (u.createdAt ? u.createdAt.toISOString().slice(0,10) : "?") + " workspaces=" + ws + " suspended=" + (u.suspended ? "yes" : "no"));
  console.log("admins now: " + admins.map(a => a.username).join(", "));
  if (ROLE === "suspend" || ROLE === "unsuspend") {
    const want = ROLE === "suspend" ? 1 : 0;
    if (!!u.suspended === !!want) { console.log("NOOP: '" + U + "' already " + (want ? "suspended" : "active")); process.exit(0); }
    if (want && u.role === "admin" && admins.length <= 1) { console.log("REFUSED: '" + U + "' is the LAST admin — promote someone else first"); process.exit(4); }
    if (!APPLY) { console.log("DRY-RUN: would set suspended " + (u.suspended ? 1 : 0) + " -> " + want + " (re-run with --yes)"); process.exit(0); }
    await p.users.update({ where: { id: u.id }, data: { suspended: want } });
    console.log("OK: '" + U + "' suspended -> " + want + (want ? " (login refused; role " + u.role + " kept)" : ""));
    process.exit(0);
  }
  if (u.role === ROLE) { console.log("NOOP: '" + U + "' already has role " + ROLE); process.exit(0); }
  if (u.role === "admin" && ROLE !== "admin" && admins.length <= 1) { console.log("REFUSED: '" + U + "' is the LAST admin — promote someone else first"); process.exit(4); }
  if (!APPLY) { console.log("DRY-RUN: would set role " + u.role + " -> " + ROLE + " (re-run with --yes)"); process.exit(0); }
  await p.users.update({ where: { id: u.id }, data: { role: ROLE } });
  const after = await p.users.findFirst({ where: { id: u.id }, select: { username: true, role: true } });
  console.log("OK: '" + U + "' role " + u.role + " -> " + after.role);
  process.exit(0);
})().catch((e) => { console.log("ERROR: " + e.message); process.exit(1); });
JS

echo "==> $USERNAME -> role '$ROLE' on $TARGET / $CONTAINER ($([[ $APPLY -eq 1 ]] && echo APPLY || echo DRY-RUN))"
# Same delivery shape as allm-user-rename.sh: helper staged on the box,
# NODE_PATH so /tmp can see the app's node_modules, root-run cleanup.
ssh "$TARGET" "cat > /tmp/allm-setrole.js" < "$JS_LOCAL"
ssh "$TARGET" "docker cp /tmp/allm-setrole.js ${CONTAINER}:/tmp/allm-setrole.js >/dev/null \
  && docker exec -e NODE_PATH=/app/server/node_modules -e ALLM_USER='${USERNAME}' -e ALLM_ROLE='${ROLE}' -e ALLM_APPLY='${APPLY}' ${CONTAINER} node /tmp/allm-setrole.js; \
  rc=\$?; docker exec -u 0 ${CONTAINER} rm -f /tmp/allm-setrole.js >/dev/null 2>&1; rm -f /tmp/allm-setrole.js; exit \$rc"
