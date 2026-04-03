#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_DIR="${SCRIPT_DIR:h}"
ENV_FILE="${APP_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[ERROR] Missing .env file at ${ENV_FILE}"
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

if [[ -z "${EVENTBRITE_PRIVATE_TOKEN:-}" ]]; then
  echo "[ERROR] EVENTBRITE_PRIVATE_TOKEN is not set"
  exit 1
fi

if [[ -z "${EVENTBRITE_ORGANIZATION_ID:-}" ]]; then
  echo "[INFO] EVENTBRITE_ORGANIZATION_ID missing; discovering via /users/me/organizations"
  ORG_JSON=$(curl -sS https://www.eventbriteapi.com/v3/users/me/organizations/ \
    -H "Authorization: Bearer ${EVENTBRITE_PRIVATE_TOKEN}")
  echo "[INFO] Organization lookup response received"
  echo "${ORG_JSON}"
  echo "[ACTION] Copy the correct organization id into EVENTBRITE_ORGANIZATION_ID in .env and rerun"
  exit 0
fi

EVENT_NAME="${1:-BurnedOutAdvisor Demo Webinar}"
START_UTC=$(date -u -v+7d +"%Y-%m-%dT18:00:00Z")
END_UTC=$(date -u -v+7d +"%Y-%m-%dT19:00:00Z")
TIMEZONE="${EVENTBRITE_DEFAULT_TIMEZONE:-America/Denver}"

PAYLOAD=$(cat <<EOF
{
  "event": {
    "name": {
      "html": "${EVENT_NAME}"
    },
    "summary": "Draft webinar for BurnedOutAdvisor demo pipeline.",
    "start": {
      "timezone": "${TIMEZONE}",
      "utc": "${START_UTC}"
    },
    "end": {
      "timezone": "${TIMEZONE}",
      "utc": "${END_UTC}"
    },
    "currency": "USD",
    "online_event": true,
    "listed": false,
    "invite_only": true,
    "capacity": 50
  }
}
EOF
)

echo "[STEP] Creating draft Eventbrite event"
EVENT_JSON=$(curl -sS -X POST "https://www.eventbriteapi.com/v3/organizations/${EVENTBRITE_ORGANIZATION_ID}/events/" \
  -H "Authorization: Bearer ${EVENTBRITE_PRIVATE_TOKEN}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

echo "[RESULT] Draft event response:"
echo "${EVENT_JSON}"

EVENT_ID=$(echo "${EVENT_JSON}" | tr -d '\n' | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"?([0-9A-Za-z_-]+)"?.*/\1/')

if [[ -n "${EVENT_ID}" && "${EVENT_ID}" != "${EVENT_JSON}" ]]; then
  echo "[STEP] Creating free ticket class for event ${EVENT_ID}"
  TICKET_JSON=$(curl -sS -X POST "https://www.eventbriteapi.com/v3/events/${EVENT_ID}/ticket_classes/" \
    -H "Authorization: Bearer ${EVENTBRITE_PRIVATE_TOKEN}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d '{
      "ticket_class": {
        "name": "General Admission",
        "quantity_total": 50,
        "free": true
      }
    }')
  echo "[RESULT] Ticket class response:"
  echo "${TICKET_JSON}"
else
  echo "[WARN] Could not determine event id from response; skipping ticket class creation"
fi
