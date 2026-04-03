#!/usr/bin/env zsh
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8000}"
MOCK_EXTERNAL="${DEMO_MOCK_EXTERNAL:-true}"
LIVE_EVENTBRITE_DRAFT="${DEMO_LIVE_EVENTBRITE_DRAFT:-false}"
EVENT_ID_OVERRIDE="${DEMO_EVENT_ID:-}"

log() {
  echo "[$(date +%H:%M:%S)] $1"
}

json_get() {
  local json="$1"
  local expr="$2"
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r "$expr"
  else
    /opt/homebrew/bin/python3 - << 'PY' "$json" "$expr"
import json,sys
obj=json.loads(sys.argv[1])
expr=sys.argv[2]
if expr=='.count':
    print(obj.get('count',''))
elif expr=='.summary':
    print(json.dumps(obj.get('summary',{}), indent=2))
elif expr=='.status':
    print(obj.get('status',''))
else:
    print('')
PY
  fi
}

pretty_print() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq
  else
    echo "$json"
  fi
}

extract_event_id() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r '.event.event.id // .event.id // empty'
  else
    echo "$json" | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*"?([0-9A-Za-z_-]+)"?.*/\1/'
  fi
}

extract_order_count() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r '.order_count // 0'
  else
    echo "0"
  fi
}

log "STEP 1: Reset demo state"
curl -sS -X POST "${BASE_URL}/demo/reset"
echo

echo
log "STEP 2: Create mock LinkedIn leads"
LEADS_JSON=$(curl -sS -X POST "${BASE_URL}/demo/linkedin/mock-leads?count=4&campaign=%23ZeroTo100")
LEAD_COUNT=$(json_get "$LEADS_JSON" '.count')
echo "Created leads: ${LEAD_COUNT}"
if command -v jq >/dev/null 2>&1; then
  echo "$LEADS_JSON" | jq -r '.leads[] | "- \(.email) [\(.interest_level)]"'
fi

echo
if [[ "$LIVE_EVENTBRITE_DRAFT" == "true" ]]; then
  log "STEP 3: Create REAL Eventbrite draft webinar event"
  EVENT_JSON=$(curl -sS -X POST "${BASE_URL}/demo/eventbrite/draft-event?create_live_in_eventbrite=true")
else
  log "STEP 3: Create mock draft webinar event record"
  EVENT_JSON=$(curl -sS -X POST "${BASE_URL}/demo/eventbrite/draft-event")
fi
EVENT_ID=$(extract_event_id "$EVENT_JSON")
if [[ -n "$EVENT_ID_OVERRIDE" ]]; then
  EVENT_ID="$EVENT_ID_OVERRIDE"
fi
echo "Using event_id: ${EVENT_ID:-unknown}"
if command -v jq >/dev/null 2>&1; then
  echo "$EVENT_JSON" | jq '{status, event: .event.mode, event_id: (.event.event.id // .event.id // "n/a")}'
fi

echo
if [[ "$MOCK_EXTERNAL" == "true" ]]; then
  log "STEP 4: Run end-to-end pipeline with mock external systems"
else
  log "STEP 4: Run end-to-end pipeline with LIVE external systems"
fi

PAYLOAD=$(cat <<EOF
{
  "mock_external": ${MOCK_EXTERNAL},
  "campaign": "#ZeroTo100",
  "event_id": "${EVENT_ID}"
}
EOF
)

PIPELINE_JSON=$(curl -sS -X POST "${BASE_URL}/demo/e2e/run" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

if command -v jq >/dev/null 2>&1; then
  echo "$PIPELINE_JSON" | jq '{status, summary, logs}'
else
  echo "$PIPELINE_JSON"
fi

echo
log "STEP 5: Fetch final demo state"
STATE_JSON=$(curl -sS "${BASE_URL}/demo/state")
if command -v jq >/dev/null 2>&1; then
  echo "$STATE_JSON" | jq '{status, counts: {leads: (.state.leads|length), contacts: (.state.contacts|length), invitations: (.state.invitations|length), purchases: (.state.purchases|length), events: (.state.events|length)}}'
else
  echo "$STATE_JSON"
fi

if [[ "$MOCK_EXTERNAL" == "false" && -n "$EVENT_ID" ]]; then
  echo
  log "STEP 6: Verify live registrations in Eventbrite orders"
  ORDERS_JSON=$(curl -sS "${BASE_URL}/demo/eventbrite/orders?event_id=${EVENT_ID}")
  ORDER_COUNT=$(extract_order_count "$ORDERS_JSON")
  echo "Eventbrite order_count: ${ORDER_COUNT}"
  if command -v jq >/dev/null 2>&1; then
    echo "$ORDERS_JSON" | jq '{status, event_id, order_count, emails}'
  fi
fi

echo
log "COMPLETE: Demo flow covered leads -> contacts -> webinar invites -> FluentCart purchase paths"
log "TIP: Set DEMO_MOCK_EXTERNAL=false to create real Eventbrite registrations"
