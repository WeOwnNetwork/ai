import os
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

os.environ["DEMO_MODE"] = "true"
os.environ["FLUENTCRM_API_URL"] = "http://mock-crm.local"
os.environ["WP_APP_USERNAME"] = "test_user"
os.environ["WP_APP_PASSWORD"] = "test_pass"
os.environ["FLUENTCART_API_URL"] = "http://mock-cart.local/wp-json/fluent-cart/v2"
os.environ["FLUENTCART_PRODUCT_ID"] = "prod_123"
os.environ["EVENTBRITE_API_URL"] = "http://mock-eb.local"
os.environ["EVENTBRITE_PRIVATE_TOKEN"] = "test_token"
os.environ["EVENTBRITE_ORGANIZATION_ID"] = "org_123"
os.environ["DEFAULT_EVENTBRITE_EVENT_ID"] = "evt_123"
os.environ["DEFAULT_EVENTBRITE_TICKET_CLASS_ID"] = "ticket_456"

from main import app
from services.demo_store import store
from services.eventbrite import EventbriteService
from services.fluentcart import FluentCartService

client = TestClient(app)


@pytest.fixture(autouse=True)
def reset_demo_store():
    store.reset()
    yield
    store.reset()


@pytest.fixture
def mock_requests_post():
    with patch("requests.post") as mock_post:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {"id": "external_1", "status": "success"}
        mock_post.return_value = mock_response
        yield mock_post


def test_eventbrite_register_attendee_formatting(mock_requests_post):
    svc = EventbriteService()

    svc.register_attendee(
        first_name="John",
        last_name="Doe",
        email="john@example.com",
        event_id="123",
        ticket_class_id="456",
        availability_preference="2026-04-10",
    )

    mock_requests_post.assert_called_once()
    args, kwargs = mock_requests_post.call_args
    assert args[0] == "http://mock-eb.local/events/123/orders/"
    assert kwargs["headers"]["Authorization"] == "Bearer test_token"
    assert kwargs["json"]["orders"][0]["ticket_class_ids"] == ["456"]
    assert kwargs["json"]["orders"][0]["attendee"]["email"] == "john@example.com"
    assert kwargs["json"]["orders"][0]["questions"][0]["answer"] == "2026-04-10"


def test_fluentcart_mock_checkout_path():
    svc = FluentCartService()
    payload = svc.build_demo_checkout_payload(
        {
            "first_name": "Jane",
            "last_name": "Smith",
            "email": "jane@example.com",
            "phone": "555-0000",
            "campaign": "#ZeroTo100",
        },
        product_id="prod_123",
    )
    result = svc.process_checkout(payload, mock=True)

    assert result["success"] is True
    assert result["data"]["payment_status"] == "paid"
    assert result["data"]["items"][0]["product_id"] == "prod_123"


def test_create_mock_linkedin_leads_endpoint():
    response = client.post("/demo/linkedin/mock-leads?count=3&campaign=%23ZeroTo100")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["count"] == 3
    assert len(data["leads"]) == 3
    assert data["leads"][0]["source"] == "linkedin-mock"


def test_run_demo_e2e_with_mock_external_services():
    response = client.post(
        "/demo/e2e/run",
        json={
            "count": 4,
            "mock_external": True,
            "campaign": "#ZeroTo100",
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["summary"]["lead_count"] == 4
    assert data["summary"]["contacts_stored"] == 4
    assert data["summary"]["webinar_invitations"] == 4
    assert data["summary"]["purchase_paths"] == 2
    assert any("Stored contact" in log for log in data["logs"])
    assert any("Invited" in log for log in data["logs"])


def test_ingest_custom_leads_and_state_snapshot():
    response = client.post(
        "/demo/linkedin/ingest",
        json={
            "leads": [
                {
                    "first_name": "Alex",
                    "last_name": "Burnout",
                    "email": "alex@example.com",
                    "job_title": "Senior Financial Advisor",
                    "company_name": "Aspen Private Wealth",
                    "availability_dates": ["2026-04-09", "2026-04-11"],
                    "interest_level": "high"
                }
            ]
        },
    )

    assert response.status_code == 200
    state_response = client.get("/demo/state")
    state = state_response.json()["state"]
    assert len(state["leads"]) == 1
    assert state["leads"][0]["email"] == "alex@example.com"
