#!/usr/bin/env bash
# secret-lib.sh — the store-agnostic seam (DESIGN §4).
#
# ONE place the fleet resolves secrets, dispatching on $SECRET_BACKEND. Today
# every path is `infisical`; this makes "migrate the fleet" into "flip a
# per-instance variable and redeploy", and lets a migration be tested one
# instance at a time instead of all 310 call sites at once.
#
# The contract every backend MUST honour (non-negotiable, from the
# secret-handling rules):
#   - values move process-to-process, never printed, never on argv
#   - `secret_run`  → exec a command with the instance's secrets in its env
#   - `secret_get`  → print ONE secret's value to stdout for command-substitution
#                     (`X=$(secret_get KEY)`), and nothing else to stdout
#
# Source this; do not execute it.

SECRET_BACKEND="${SECRET_BACKEND:-infisical}"

_secret_die(){ echo "secret-lib: $*" >&2; return 1; }

# secret_run <cmd...> : run cmd with this instance's secrets injected as env.
secret_run() {
  case "$SECRET_BACKEND" in
    infisical)
      # Unchanged from ADR-006 — the path in production today.
      exec infisical run --path="${INFISICAL_PATH:-/}" -- "$@"
      ;;
    openbao)
      # bao agent renders the env from the AppRole; exec the real entrypoint.
      # role-id is baked into the render (not secret); secret-id arrives
      # response-wrapped at provision (§2.4) and is unwrapped into BAO_ROLE_ID/
      # BAO_SECRET_ID by the entrypoint before this is called.
      [ -n "${BAO_ADDR:-}" ] || _secret_die "BAO_ADDR unset" || return 1
      local tok
      tok="$(bao write -field=token auth/approle/login \
              role_id="${BAO_ROLE_ID:?}" secret_id="${BAO_SECRET_ID:?}")" \
        || _secret_die "approle login failed" || return 1
      # Export each key at the instance's path as an env var, then exec.
      # `-format=json | jq` keeps values out of argv; the eval never echoes them.
      local kvjson
      kvjson="$(BAO_TOKEN="$tok" bao kv get -format=json "weown/${BAO_SECRET_PATH:?}" \
                | jq -r '.data.data | to_entries[] | "export \(.key)=\(.value|@sh)"')" \
        || _secret_die "kv get failed" || return 1
      eval "$kvjson"
      unset tok kvjson
      exec "$@"
      ;;
    sops)
      # Encrypted-secrets-in-git: decrypt the instance file into env, exec.
      # No running service to depend on (DESIGN §3). Requires SOPS_FILE + a key.
      [ -f "${SOPS_FILE:-}" ] || _secret_die "SOPS_FILE not found" || return 1
      local dotenv; dotenv="$(sops -d "$SOPS_FILE")" || _secret_die "sops decrypt failed" || return 1
      set -a; eval "$dotenv"; set +a; unset dotenv
      exec "$@"
      ;;
    *)
      _secret_die "unknown SECRET_BACKEND='$SECRET_BACKEND' (infisical|openbao|sops)"
      ;;
  esac
}

# secret_get <KEY> : print one secret value to stdout (for `X=$(secret_get KEY)`).
secret_get() {
  local key="${1:?secret_get <KEY>}"
  case "$SECRET_BACKEND" in
    infisical)
      infisical secrets get "$key" --path="${INFISICAL_PATH:-/}" --plain </dev/null
      ;;
    openbao)
      local tok
      tok="$(bao write -field=token auth/approle/login \
              role_id="${BAO_ROLE_ID:?}" secret_id="${BAO_SECRET_ID:?}")" || return 1
      BAO_TOKEN="$tok" bao kv get -field="$key" "weown/${BAO_SECRET_PATH:?}"
      unset tok
      ;;
    sops)
      sops -d --extract "[\"$key\"]" "${SOPS_FILE:?}"
      ;;
    *)
      _secret_die "unknown SECRET_BACKEND='$SECRET_BACKEND'"
      ;;
  esac
}
