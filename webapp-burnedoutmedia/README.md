# BurnedOutMedia Webapp (PRJ-012)

FastAPI integration service for the BurnedOutAdvisor funnel:

- LinkedIn lead intake (currently **mock/demo mode** while Lead Sync access is pending)
- Contact storage in FluentCRM
- Webinar invitation/registration through Eventbrite
- Purchase path simulation/integration through FluentCart

---

## 1) What this service does

Primary E2E pipeline:

1. Lead captured (mock LinkedIn for now)
2. Lead normalized and stored
3. Lead invited to webinar event (Eventbrite)
4. Contact synced to FluentCRM
5. Interested leads enter purchase path (FluentCart)

This supports PRJ-012 #ZeroTo100 smoke testing before full LinkedIn production credentials are enabled.

---

## 2) Project structure

- `main.py` — FastAPI routes (demo + integration endpoints)
- `config.py` — environment-based settings
- `models.py` — request schemas for demo APIs
- `services/mock_linkedin.py` — scalable synthetic lead generator
- `services/demo_store.py` — in-memory store for leads/contacts/invitations/purchases/events
- `services/demo_pipeline.py` — E2E orchestration with detailed logs
- `services/eventbrite.py` — event discovery, draft event creation, attendee registration
- `services/fluentcrm.py` — CRM contact creation
- `services/fluentcart.py` — checkout/customer/order integration (mock + real modes)
- `scripts/create_eventbrite_demo_event.sh` — create draft Eventbrite webinar + free ticket class
- `scripts/run_demo_e2e.sh` — run full demo smoke flow with logs
- `tests/test_services.py` — focused service/API smoke tests

---

## 3) Environment variables

Create/update `.env` in this folder.

### Required

- `FLUENTCRM_API_URL`
- `WP_APP_USERNAME`
- `WP_APP_PASSWORD`
- `EVENTBRITE_API_URL`
- `EVENTBRITE_PRIVATE_TOKEN`

### Strongly recommended

- `DEMO_MODE=true`
- `EVENTBRITE_ORGANIZATION_ID`
- `DEFAULT_EVENTBRITE_EVENT_ID`
- `DEFAULT_EVENTBRITE_TICKET_CLASS_ID`
- `EVENTBRITE_DEFAULT_TIMEZONE`

### Optional (for checkout integration)

- `FLUENTCART_API_URL`
- `FLUENTCART_PRODUCT_ID`

### Optional (future LinkedIn production mode)

- `LINKEDIN_CLIENT_ID`
- `LINKEDIN_CLIENT_SECRET`
- `LINKEDIN_ACCESS_TOKEN`
- `LINKEDIN_REDIRECT_URI`

---

## 4) Local setup

From this folder:

```bash
uv pip install -r requirements.txt
```

Run API:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Health check:

```bash
curl http://127.0.0.1:8000/
```

---

## 5) Demo E2E smoke testing

### A. Scripted smoke test (recommended)

```bash
./scripts/run_demo_e2e.sh
```

Run with live Eventbrite registration + order verification:

```bash
DEMO_MOCK_EXTERNAL=false ./scripts/run_demo_e2e.sh
```

Optionally force creating a real draft Eventbrite event first:

```bash
DEMO_LIVE_EVENTBRITE_DRAFT=true DEMO_MOCK_EXTERNAL=false ./scripts/run_demo_e2e.sh
```

This validates the end-to-end flow and prints step logs:

- demo reset
- mock lead creation
- draft event record creation
- pipeline run (leads → contacts → invites → purchase path)
- final state snapshot

When `DEMO_MOCK_EXTERNAL=false`, the script also calls `GET /demo/eventbrite/orders` to confirm actual Eventbrite orders/ticket registrations.

### B. Create real Eventbrite draft webinar for testing

```bash
./scripts/create_eventbrite_demo_event.sh "BurnedOutAdvisor Demo Webinar"
```

This script:

1. Uses Eventbrite token from `.env`
2. Creates a **draft** event under `EVENTBRITE_ORGANIZATION_ID`
3. Creates a free ticket class for registration tests

Then update defaults in `.env` if needed:

- `DEFAULT_EVENTBRITE_EVENT_ID`
- `DEFAULT_EVENTBRITE_TICKET_CLASS_ID`

### C. API-level smoke calls

```bash
curl -X POST "http://127.0.0.1:8000/demo/reset"
curl -X POST "http://127.0.0.1:8000/demo/linkedin/mock-leads?count=5&campaign=%23ZeroTo100"
curl -X POST "http://127.0.0.1:8000/demo/e2e/run" -H "Content-Type: application/json" -d '{"mock_external": true, "campaign": "#ZeroTo100"}'
curl "http://127.0.0.1:8000/demo/state"
```

### D. Test suite

```bash
pytest tests/test_services.py -q
```

---

## 6) Production setup guide

Use this when moving from mock/demo to live operations.

### Step 1: Security and secrets

- Do not commit real tokens/passwords
- Rotate all credentials used in testing
- Store secrets in secure manager (K8s secret/Infisical/Vault)
- Restrict API ingress (allowlist, auth, WAF where available)

### Step 2: LinkedIn go-live

- Obtain Lead Sync API approval
- Set all `LINKEDIN_*` variables
- Switch lead source endpoints from demo ingestion to LinkedIn webhook ingestion
- Validate webhook signature/challenge and replay safety

### Step 3: Eventbrite go-live

- Set correct `EVENTBRITE_ORGANIZATION_ID`
- Create production webinar event + ticket class
- Set `DEFAULT_EVENTBRITE_EVENT_ID` and `DEFAULT_EVENTBRITE_TICKET_CLASS_ID`
- Validate registration and attendee listing with real account

### Step 4: FluentCRM + FluentCart go-live

- Verify WordPress application password auth
- Validate contact write path in FluentCRM
- Validate order/checkout path in FluentCart API
- Add retry + dead-letter strategy for failed outbound writes

### Step 5: Runtime and deployment

Recommended process manager setup:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
```

For internet-facing deployment:

- Put behind reverse proxy/load balancer
- Enforce TLS
- Configure request/response timeouts
- Enable structured logs + request IDs

### Step 6: Production smoke checklist

- `GET /` returns healthy status
- Lead ingestion succeeds
- CRM contact created
- Webinar invite/registration created
- Purchase path executes for interested leads
- Failures logged with enough context for replay

---

## 7) Key endpoints

### Demo endpoints

- `POST /demo/reset`
- `GET /demo/state`
- `POST /demo/linkedin/mock-leads`
- `POST /demo/linkedin/ingest`
- `POST /demo/eventbrite/draft-event`
- `POST /demo/e2e/run`

### Integration endpoints

- `GET /linkedin/forms`
- `GET /linkedin/leads`
- `POST /webhook/linkedin`
- `POST /webhook/linkedin/e2e`
- `GET /webinars`
- `GET /webinars/availability`
- `POST /webinar/register`

---

## 8) Current mode and limitations

- LinkedIn path is intentionally in mock mode until API access is approved.
- Demo store is in-memory; data is ephemeral and resettable.
- For production, replace in-memory state with persistent storage and queue-backed retries.

---

## 9) Suggested next hardening tasks

1. Add idempotency keys for lead processing
2. Add webhook signature verification middleware
3. Add persistent DB + migration for lead/contact/invitation states
4. Add structured JSON logging + metrics endpoint
5. Add integration tests for real external APIs behind feature flags

---

## 10) Ownership

Project scope aligns with:

- PRJ-012 BurnedOutAdvisor.com
- #ZeroTo100 campaign
- BurnedOutMedia webinar conversion flow
