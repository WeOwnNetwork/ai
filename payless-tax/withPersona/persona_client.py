import os
from typing import Optional

import requests
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, ".env"))

PERSONA_API_KEY = os.getenv("PERSONA_API_KEY")
PERSONA_INQUIRY_TEMPLATE_ID = os.getenv("PERSONA_INQUIRY_TEMPLATE_ID")

# Persona Graph/Protocol base. For this demo we use the public REST-style API root.
PERSONA_API_BASE = "https://api.withpersona.com/api/v1"


class PersonaError(Exception):
    pass


def _headers() -> dict:
    if not PERSONA_API_KEY:
        raise PersonaError("PERSONA_API_KEY not configured")
    return {
        "Authorization": f"Bearer {PERSONA_API_KEY}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def create_inquiry(template_id: Optional[str] = None, reference_id: Optional[str] = None) -> dict:
    """Create a Persona Inquiry for an individual using the configured template."""
    url = f"{PERSONA_API_BASE}/inquiries"
    payload: dict = {
        "data": {
            "type": "inquiry",
            "attributes": {},
        }
    }

    tmpl = template_id or PERSONA_INQUIRY_TEMPLATE_ID
    if tmpl:
        payload["data"]["attributes"]["inquiry-template-id"] = tmpl
    if reference_id:
        payload["data"]["attributes"]["reference-id"] = reference_id

    resp = requests.post(url, json=payload, headers=_headers(), timeout=15)
    if not resp.ok:
        raise PersonaError(f"Failed to create inquiry: {resp.status_code} {resp.text}")
    return resp.json()


def get_inquiry(inquiry_id: str) -> dict:
    url = f"{PERSONA_API_BASE}/inquiries/{inquiry_id}"
    resp = requests.get(url, headers=_headers(), timeout=15)
    if not resp.ok:
        raise PersonaError(f"Failed to fetch inquiry: {resp.status_code} {resp.text}")
    return resp.json()


def get_inquiry_with_includes(inquiry_id: str) -> dict:
    """Retrieve an inquiry including account.reports for sanctions/watchlist checks."""
    url = f"{PERSONA_API_BASE}/inquiries/{inquiry_id}"
    params = {"include": "account.reports"}
    resp = requests.get(url, headers=_headers(), params=params, timeout=15)
    if not resp.ok:
        raise PersonaError(f"Failed to fetch inquiry with includes: {resp.status_code} {resp.text}")
    return resp.json()


def extract_inquiry_status(inquiry: dict) -> str:
    """Return a simplified status string from the Persona inquiry payload."""
    data = inquiry.get("data") or {}
    attrs = data.get("attributes") or {}
    status = attrs.get("status") or "unknown"
    decision = attrs.get("decision")

    if decision == "approved":
        return "VERIFIED"
    if decision == "declined":
        return "FAILED"
    if status in {"approved", "completed"}:
        return "VERIFIED"
    if status in {"declined", "failed"}:
        return "FAILED"
    if status in {"pending", "created", "requires-input", "review"}:
        return "PENDING"
    return "PENDING"


def summarize_kyc(inquiry: dict) -> dict:
    data = inquiry.get("data") or {}
    attrs = data.get("attributes") or {}
    included = inquiry.get("included") or []

    persona_status = attrs.get("status")
    persona_decision = attrs.get("decision")

    watchlist_reports = []
    for obj in included:
        obj_type = (obj.get("type") or "").lower()
        if obj_type in {"report", "reports"}:
            r_attrs = obj.get("attributes") or {}
            r_type = (r_attrs.get("report-type") or "").lower()
            if any(key in r_type for key in ("watchlist", "sanctions", "aml")):
                watchlist_reports.append(
                    {
                        "id": obj.get("id"),
                        "type": r_attrs.get("report-type"),
                        "status": r_attrs.get("status"),
                        "decision": r_attrs.get("decision"),
                    }
                )

    has_watchlist_decline = any(r.get("decision") == "declined" for r in watchlist_reports)
    allowed = persona_decision == "approved" and not has_watchlist_decline

    return {
        "status": persona_status,
        "decision": persona_decision,
        "allowed": allowed,
        "watchlist_reports": watchlist_reports,
    }
