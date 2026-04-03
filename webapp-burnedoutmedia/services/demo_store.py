from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from uuid import uuid4


class DemoStore:
    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.leads: List[Dict[str, Any]] = []
        self.contacts: List[Dict[str, Any]] = []
        self.invitations: List[Dict[str, Any]] = []
        self.purchases: List[Dict[str, Any]] = []
        self.events: List[Dict[str, Any]] = []

    def _stamp(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        item = deepcopy(payload)
        item.setdefault("id", str(uuid4()))
        item.setdefault("created_at", datetime.now(timezone.utc).isoformat())
        return item

    def add_leads(self, leads: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        stored = [self._stamp(lead) for lead in leads]
        self.leads.extend(stored)
        return stored

    def add_contact(self, contact: Dict[str, Any]) -> Dict[str, Any]:
        stored = self._stamp(contact)
        self.contacts.append(stored)
        return stored

    def add_invitation(self, invitation: Dict[str, Any]) -> Dict[str, Any]:
        stored = self._stamp(invitation)
        self.invitations.append(stored)
        return stored

    def add_purchase(self, purchase: Dict[str, Any]) -> Dict[str, Any]:
        stored = self._stamp(purchase)
        self.purchases.append(stored)
        return stored

    def add_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        stored = self._stamp(event)
        self.events.append(stored)
        return stored

    def get_state(self) -> Dict[str, Any]:
        return {
            "leads": deepcopy(self.leads),
            "contacts": deepcopy(self.contacts),
            "invitations": deepcopy(self.invitations),
            "purchases": deepcopy(self.purchases),
            "events": deepcopy(self.events),
        }


store = DemoStore()
