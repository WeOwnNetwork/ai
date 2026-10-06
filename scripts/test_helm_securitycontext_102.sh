#!/usr/bin/env bash
# weown-fleet#102 — Matomo Deployment and Nextcloud CronJobs must render securityContext.
# Fails before the template wire-up; passes after.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

need() {
  local hay="$1" needle="$2" label="$3"
  if ! grep -qF "$needle" <<<"$hay"; then
    echo "FAIL: $label — missing: $needle" >&2
    fail=1
  else
    echo "ok: $label"
  fi
}

# --- Matomo Deployment ---
matomo_out="$(helm template matomo "$ROOT/matomo/helm" --namespace matomo 2>/dev/null)" || {
  echo "FAIL: helm template matomo" >&2; exit 1
}
# Isolate the Deployment (not the CronJob, which already had pod SC)
matomo_dep="$(awk '/^kind: Deployment$/{p=1} p{print} /^---$/{if(p&&seen++){exit}}' <<<"$matomo_out")"
# Prefer a simpler split:
matomo_dep="$(printf '%s\n' "$matomo_out" | awk '
  /^kind: Deployment$/{grab=1; buf=$0"\n"; next}
  grab && /^---$/{print buf; exit}
  grab{buf=buf $0 "\n"}
  END{if(grab) print buf}
')"

need "$matomo_dep" "runAsNonRoot: true" "matomo Deployment has runAsNonRoot"
need "$matomo_dep" "runAsUser: 33" "matomo Deployment has runAsUser 33"
need "$matomo_dep" "allowPrivilegeEscalation: false" "matomo Deployment drops privilege escalation"
# Main container must not be the only place — pod or container SC both count; require drop ALL somewhere in Deployment
need "$matomo_dep" "drop:" "matomo Deployment drops capabilities"

# Init must still be able to chown: explicit root override on config-fix
if ! printf '%s\n' "$matomo_dep" | awk '/name: config-fix/{p=1} p&&/runAsUser: 0/{found=1} p&&/^      - name:/{if($0!~/config-fix/){exit}} END{exit !found}'; then
  echo "FAIL: matomo config-fix initContainer must override runAsUser: 0 (chown www-data)" >&2
  fail=1
else
  echo "ok: matomo config-fix runs as root override for chown"
fi

# --- Nextcloud CronJobs ---
# Chart may need required values — use --set for domain-like fields if present
nc_set=(--set global.domain=example.test --set nextcloud.domain=example.test)
nc_out="$(helm template nextcloud "$ROOT/nextcloud/helm" --namespace nextcloud "${nc_set[@]}" 2>/dev/null)" || {
  # try without extras
  nc_out="$(helm template nextcloud "$ROOT/nextcloud/helm" --namespace nextcloud 2>&1)" || {
    echo "FAIL: helm template nextcloud: $nc_out" >&2; exit 1
  }
}

extract_cron() {
  local component="$1"
  printf '%s\n' "$nc_out" | awk -v c="$component" '
    /^kind: CronJob$/{grab=0; buf=""}
    /^kind: CronJob$/{grab=1; buf=$0"\n"; next}
    grab && /app.kubernetes.io\/component: '"$component"'/{want=1}
    grab{buf=buf $0 "\n"}
    grab && /^---$/{
      if(want){print buf; exit}
      grab=0; want=0; buf=""
    }
    END{if(grab && want) print buf}
  '
}

cron_out="$(extract_cron cron)"
backup_out="$(extract_cron backup)"

need "$cron_out" "allowPrivilegeEscalation: false" "nextcloud cron CronJob has allowPrivilegeEscalation false"
need "$cron_out" "drop:" "nextcloud cron CronJob drops capabilities"

need "$backup_out" "runAsNonRoot: true" "nextcloud backup CronJob runAsNonRoot"
need "$backup_out" "runAsUser: 1001" "nextcloud backup CronJob runAsUser 1001 (postgres)"
need "$backup_out" "allowPrivilegeEscalation: false" "nextcloud backup CronJob allowPrivilegeEscalation false"

if [[ "$fail" -ne 0 ]]; then
  echo "test_helm_securitycontext_102: FAILED" >&2
  exit 1
fi
echo "test_helm_securitycontext_102: ok"
