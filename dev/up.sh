#!/usr/bin/env bash
# up.sh — bring the whole local stack up and bootstrap it, idempotently.
#
#   ./dev/up.sh            # start + bootstrap (safe to re-run)
#   ./dev/up.sh --down     # stop, keep data
#   ./dev/up.sh --destroy  # stop and DELETE the local volumes
#
# What it does that a bare `docker compose up` cannot: AnythingLLM ships with no
# admin and no API key, and the dashboard cannot start usefully without one. So
# this mints the key through ALLM's own bootstrap window, creates the support
# admin, closes the window by enabling multi-user mode, creates the two
# workspaces the dashboard expects, and hashes a dashboard password — the same
# sequence scripts/allm-bootstrap-admin.sh runs against a real droplet.
#
# SECRETS: every credential is GENERATED locally into dev/.env.dev (gitignored,
# 0600) and never printed. Read them with `cat dev/.env.dev` when you need them.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ENVF=".env.dev"
COMPOSE=(docker compose --env-file "$ENVF" -f compose.dev.yaml)

case "${1:-}" in
  --down)    exec docker compose --env-file "$ENVF" -f compose.dev.yaml down ;;
  --destroy) exec docker compose --env-file "$ENVF" -f compose.dev.yaml down -v ;;
esac

# ── 1. local credentials, generated once ─────────────────────────────────────
if [[ ! -f "$ENVF" ]]; then
  echo "==> generating $ENVF (local throwaway credentials, never committed)"
  umask 077
  rnd() { openssl rand -base64 33 | tr -d '/+=' | cut -c1-28; }
  cat > "$ENVF" <<EOF
# Local development only. Generated $(date -u +%FT%TZ). Never commit this file.
POSTGRES_DB=billing
POSTGRES_USER=billing
POSTGRES_PASSWORD=$(rnd)
DJANGO_SECRET_KEY=$(rnd)
BILLING_BREAK_GLASS_PASSWORD=$(rnd)
ALLM_JWT_SECRET=$(rnd)
DASHBOARD_SESSION_SECRET=$(rnd)
DASHBOARD_PASSWORD=$(rnd)
ALLM_ADMIN_USER=support@weown.net
ALLM_ADMIN_PASSWORD=$(rnd)
# Production runs a PRIVATE-registry build pinned to v1.15.0 that you cannot
# pull. This is the closest public tag — see README "Where local differs".
ANYTHINGLLM_IMAGE=mintplexlabs/anythingllm:1.16.1
WS_PUBLIC_SLUG=ws-public
WS_PRIVATE_SLUG=ws-private
EOF
  chmod 600 "$ENVF"
else
  echo "==> reusing existing $ENVF"
fi

# NOTE the `|| true`: with `set -o pipefail` a missing key makes grep exit 1,
# which fails the whole pipeline, which aborts the script under `set -e` the
# moment you write `x=$(get KEY)`. Reading an absent key is normal here.
get() { { grep -E "^$1=" "$ENVF" || true; } | head -1 | cut -d= -f2-; }
set_kv() { # set_kv KEY VALUE — value never echoed
  if grep -qE "^$1=" "$ENVF"; then
    tmp=$(mktemp); grep -vE "^$1=" "$ENVF" > "$tmp"; printf '%s=%s\n' "$1" "$2" >> "$tmp"
    mv "$tmp" "$ENVF"; chmod 600 "$ENVF"
  else
    printf '%s=%s\n' "$1" "$2" >> "$ENVF"
  fi
}

# ── 1b. host ports, chosen once and recorded ─────────────────────────────────
# Every published port here is a guess about someone else's machine. 8000 in
# particular is the Django default, so any other local Django project owns it
# first; when that happened the compose up died mid-run and the bootstrap below
# never ran, leaving the dashboard crash-looping on a missing API key with
# nothing pointing at the real cause. So: pick free ports, write them down, and
# say plainly when one we already recorded has been taken by something else.
port_busy() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3<&- 3>&-; return 0; }; return 1; }
ours_publishes() { docker ps --filter "label=com.docker.compose.project=weown-dev" \
    --format '{{.Ports}}' 2>/dev/null | grep -q ":$1->"; }

ensure_port() { # ensure_port KEY PREFERRED
  local key="$1" pref="$2" cur p
  cur=$(get "$key")
  if [[ -n "$cur" ]]; then
    if port_busy "$cur" && ! ours_publishes "$cur"; then
      echo "  ✗ port $cur (recorded as $key) is taken by something else." >&2
      echo "    Free it, or edit $key in $ENVF and re-run." >&2
      return 1
    fi
    return 0
  fi
  for (( p=pref; p<pref+40; p++ )); do
    # A port our own stack already publishes is free FOR US — re-running up.sh
    # against a live stack must not shuffle every port by one.
    if ! port_busy "$p" || ours_publishes "$p"; then
      set_kv "$key" "$p"
      [[ "$p" == "$pref" ]] || echo "  • $pref was busy — using $p for $key"
      return 0
    fi
  done
  echo "  ✗ no free port in $pref..$((pref+39)) for $key" >&2; return 1
}

ensure_port BILLING_PORT   8010
ensure_port ALLM_PORT      3001
ensure_port DASHBOARD_PORT 3002

BILLING_PORT=$(get BILLING_PORT); ALLM_PORT=$(get ALLM_PORT); DASHBOARD_PORT=$(get DASHBOARD_PORT)

# ── 2. up ────────────────────────────────────────────────────────────────────
echo "==> starting containers"
"${COMPOSE[@]}" up -d --build

wait_http() { # wait_http <url> <label> [tries]
  local url="$1" label="$2" tries="${3:-60}" code
  for _ in $(seq 1 "$tries"); do
    # No `|| echo 000`: curl ALREADY prints 000 via -w when it cannot connect,
    # so appending another made a hard failure read as the string "000000",
    # which is != "000" and was reported as SUCCESS. Match a real status.
    code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$url" 2>/dev/null || true)
    [[ "$code" =~ ^[1-5][0-9][0-9]$ ]] && { echo "  ✓ $label answering ($code)"; return 0; }
    sleep 3
  done
  echo "  ✗ $label never answered at $url" >&2; return 1
}
wait_http "http://localhost:$ALLM_PORT/api/ping" "anythingllm" 80
wait_http "http://localhost:$BILLING_PORT/healthz"  "billing"     60

# ── 3. AnythingLLM: key first, THEN close the window ─────────────────────────
# Order is load-bearing: /api/system/* is unauthenticated only until multi-user
# mode is on, and the JWT from /api/request-token does NOT authorize it after.
if [[ -z "$(get ALLM_ADMIN_API_KEY)" ]]; then
  echo "==> minting the AnythingLLM Developer API key"
  KEY=$(curl -s -m 20 -X POST -H 'Content-Type: application/json' \
        http://localhost:$ALLM_PORT/api/system/generate-api-key | jq -r '.apiKey.secret // empty')
  if [[ -z "$KEY" ]]; then
    KEY=$("${COMPOSE[@]}" exec -T anythingllm node -e \
      'const{PrismaClient}=require("@prisma/client");new PrismaClient().api_keys.findFirst().then(k=>process.stdout.write(k?k.secret:""))' 2>/dev/null || true)
  fi
  [[ -n "$KEY" ]] || { echo "✗ could not mint an API key — is multi-user already on? see README" >&2; exit 1; }
  set_kv ALLM_ADMIN_API_KEY "$KEY"; unset KEY
  echo "  ✓ stored in $ENVF"
fi

echo "==> ensuring the support admin exists + multi-user mode is on"
RESP=$(curl -s -m 20 -X POST -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg u "$(get ALLM_ADMIN_USER)" --arg p "$(get ALLM_ADMIN_PASSWORD)" '{username:$u,password:$p}')" \
  http://localhost:$ALLM_PORT/api/system/enable-multi-user || true)
if grep -q '"success":true' <<<"$RESP"; then echo "  ✓ support admin created, multi-user ON"
elif grep -qiE 'no auth token|already|multi-user' <<<"$RESP"; then echo "  • multi-user already enabled"
else echo "  ⚠️  unexpected reply from enable-multi-user (continuing): $(tr -d '\n' <<<"$RESP" | cut -c1-120)"; fi

# ── 4. the two workspaces the dashboard expects ──────────────────────────────
api() { curl -s -m 20 -H "Authorization: Bearer $(get ALLM_ADMIN_API_KEY)" -H 'Content-Type: application/json' "$@"; }
for pair in "Public Website Assistant:$(get WS_PUBLIC_SLUG)" "Private Business Assistant:$(get WS_PRIVATE_SLUG)"; do
  name="${pair%%:*}"; want="${pair##*:}"
  have=$(api http://localhost:$ALLM_PORT/api/v1/workspaces | jq -r --arg s "$want" '.workspaces[]?|select(.slug==$s)|.slug' | head -1)
  if [[ -n "$have" ]]; then echo "  • workspace $want exists"; else
    got=$(api -X POST http://localhost:$ALLM_PORT/api/v1/workspace/new -d "$(jq -nc --arg n "$name" '{name:$n}')" | jq -r '.workspace.slug // empty')
    [[ -n "$got" ]] && echo "  ✓ created workspace '$name' ($got)" || echo "  ⚠️  could not create '$name'"
    [[ -n "$got" && "$got" != "$want" ]] && { set_kv "$( [[ $want == $(get WS_PUBLIC_SLUG) ]] && echo WS_PUBLIC_SLUG || echo WS_PRIVATE_SLUG )" "$got"; echo "    (slug is '$got' — recorded)"; }
  fi
done

# ── 5. dashboard break-glass password hash (scrypt, same shape as production) ─
if [[ -z "$(get DASHBOARD_PASSWORD_HASH)" ]]; then
  echo "==> hashing the dashboard password"
  HASH=$(DP="$(get DASHBOARD_PASSWORD)" node -e \
    'const c=require("crypto");const s=c.randomBytes(16);const h=c.scryptSync(process.env.DP,s,32);process.stdout.write("scrypt$"+s.toString("hex")+"$"+h.toString("hex"))')
  [[ ${#HASH} -gt 40 ]] || { echo "✗ scrypt hash failed (is node on PATH?)" >&2; exit 1; }
  set_kv DASHBOARD_PASSWORD_HASH "$HASH"; unset HASH
  echo "  ✓ stored in $ENVF"
fi

echo "==> restarting the dashboard so it picks up the new env"
"${COMPOSE[@]}" up -d dashboard
wait_http "http://localhost:$DASHBOARD_PORT/app/healthz" "dashboard" 40

cat <<DONE

────────────────────────────────────────────────────────────────
  Local stack is up.

  Billing        http://localhost:$BILLING_PORT/         (admin: /admin/)
  AnythingLLM    http://localhost:$ALLM_PORT/         (support-person login)
  Dashboard      http://localhost:$DASHBOARD_PORT/app/     (the customer UI you edit)

  Every credential is in dev/.env.dev — \`cat dev/.env.dev\`.
  Nothing is printed here on purpose.

  Edit anythingllm-docker/template/dashboard/** then:
      docker compose --env-file dev/.env.dev -f dev/compose.dev.yaml restart dashboard
────────────────────────────────────────────────────────────────
DONE
