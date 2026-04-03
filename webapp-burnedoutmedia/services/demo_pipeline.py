from __future__ import annotations

from typing import Any, Dict, List, Optional

from config import settings
from services.demo_store import store
from services.eventbrite import EventbriteService
from services.fluentcart import FluentCartService
from services.fluentcrm import FluentCRMService
from services.mock_linkedin import MockLinkedInService


class DemoPipelineService:
    def __init__(self) -> None:
        self.mock_linkedin = MockLinkedInService()
        self.fluentcrm = FluentCRMService()
        self.eventbrite = EventbriteService()
        self.fluentcart = FluentCartService()

    def ingest_mock_leads(self, count: int = 5, campaign: str = "#ZeroTo100") -> List[Dict[str, Any]]:
        leads = self.mock_linkedin.generate_mock_leads(count=count, campaign=campaign)
        return store.add_leads(leads)

    def ingest_custom_leads(self, leads: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        normalized = self.mock_linkedin.bulk_normalize(leads)
        return store.add_leads(normalized)

    def store_contact(self, lead: Dict[str, Any], mock_external: bool = True) -> Dict[str, Any]:
        crm_payload = self.fluentcrm.create_contact(
            first_name=lead.get("first_name", ""),
            last_name=lead.get("last_name", ""),
            email=lead.get("email", ""),
            phone=lead.get("phone", ""),
            webinar=lead.get("webinar_topic", settings.DEFAULT_WEBINAR_TOPIC),
        ) if not mock_external else {
            "id": lead.get("email"),
            "status": "mock-contact-created",
        }

        stored = store.add_contact(
            {
                "lead_email": lead.get("email"),
                "crm": crm_payload,
                "lead": lead,
            }
        )
        return stored

    def invite_to_webinar(
        self,
        lead: Dict[str, Any],
        event_id: Optional[str] = None,
        mock_external: bool = True,
    ) -> Dict[str, Any]:
        if mock_external:
            event_payload = {
                "id": event_id or settings.DEFAULT_EVENTBRITE_EVENT_ID or "demo-event",
                "name": {"text": lead.get("webinar_topic", settings.DEFAULT_WEBINAR_TOPIC)},
                "start": {"local": (lead.get("availability_dates") or [""])[0]},
                "url": "https://eventbrite.test/demo-event",
            }
            registration = {
                "id": f"invite-{lead.get('email')}",
                "status": "mock-registered",
            }
            result = {
                "success": True,
                "event": event_payload,
                "registration": registration,
                "match_reason": "mock availability match",
            }
        else:
            if event_id:
                registration = self.eventbrite.register_attendee(
                    first_name=lead.get("first_name", ""),
                    last_name=lead.get("last_name", ""),
                    email=lead.get("email", ""),
                    event_id=event_id,
                    ticket_class_id=settings.DEFAULT_EVENTBRITE_TICKET_CLASS_ID or None,
                    availability_preference=", ".join(lead.get("availability_dates", [])) or None,
                )
                result = {
                    "success": True,
                    "event": {
                        "id": event_id,
                        "name": {"text": lead.get("webinar_topic", settings.DEFAULT_WEBINAR_TOPIC)},
                    },
                    "registration": registration,
                    "match_reason": "explicit event_id provided",
                }
            else:
                result = self.eventbrite.register_with_availability_check(
                    first_name=lead.get("first_name", ""),
                    last_name=lead.get("last_name", ""),
                    email=lead.get("email", ""),
                    preferred_dates=lead.get("availability_dates"),
                    topic_filter=lead.get("webinar_topic"),
                )

        return store.add_invitation(
            {
                "lead_email": lead.get("email"),
                "event_id": event_id or result.get("event", {}).get("id"),
                "result": result,
            }
        )

    def create_purchase(self, lead: Dict[str, Any], mock_external: bool = True) -> Dict[str, Any]:
        customer_payload = {
            "first_name": lead.get("first_name"),
            "last_name": lead.get("last_name"),
            "email": lead.get("email"),
            "phone": lead.get("phone", ""),
        }
        customer = self.fluentcart.create_customer(customer_payload, mock=mock_external)
        checkout_payload = self.fluentcart.build_demo_checkout_payload(lead)
        checkout = self.fluentcart.process_checkout(checkout_payload, mock=mock_external)
        order = self.fluentcart.create_order(
            {
                "customer_id": customer.get("data", {}).get("id", lead.get("email")),
                "items": checkout_payload.get("items", []),
                "status": "paid",
            },
            mock=mock_external,
        )
        return store.add_purchase(
            {
                "lead_email": lead.get("email"),
                "customer": customer,
                "checkout": checkout,
                "order": order,
            }
        )

    def run_e2e(
        self,
        leads: List[Dict[str, Any]],
        event_id: Optional[str] = None,
        mock_external: bool = True,
        persist_input: bool = True,
    ) -> Dict[str, Any]:
        logs: List[str] = []
        stored_contacts = []
        invitations = []
        purchases = []

        logs.append(f"Received {len(leads)} lead(s) into demo pipeline")
        if persist_input:
            persisted_leads = self.ingest_custom_leads(leads)
            logs.append(f"Stored {len(persisted_leads)} lead(s) in demo store")
        else:
            persisted_leads = leads
            logs.append(f"Reused {len(persisted_leads)} pre-stored lead(s) from demo store")

        for lead in persisted_leads:
            contact = self.store_contact(lead, mock_external=mock_external)
            stored_contacts.append(contact)
            logs.append(f"Stored contact for {lead.get('email')} in CRM stage")

            invitation = self.invite_to_webinar(lead, event_id=event_id, mock_external=mock_external)
            invitations.append(invitation)
            logs.append(f"Invited {lead.get('email')} to webinar event")

            interest_level = lead.get("interest_level", "medium")
            if interest_level == "high":
                purchase = self.create_purchase(lead, mock_external=mock_external)
                purchases.append(purchase)
                logs.append(f"Created FluentCart purchase path for interested lead {lead.get('email')}")
            else:
                logs.append(f"Skipped purchase path for {lead.get('email')} due to interest level {interest_level}")

        return {
            "logs": logs,
            "summary": {
                "lead_count": len(persisted_leads),
                "contacts_stored": len(stored_contacts),
                "webinar_invitations": len(invitations),
                "purchase_paths": len(purchases),
                "mock_external": mock_external,
            },
            "state": store.get_state(),
        }


demo_pipeline = DemoPipelineService()
