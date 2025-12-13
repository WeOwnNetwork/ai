
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import requests

PERSONA_API_BASE = os.getenv("PERSONA_API_BASE", "https://withpersona.com/api/v1").rstrip("/")
PERSONA_API_KEY = os.getenv("PERSONA_API_KEY", "").strip().strip('"')
PERSONA_INQUIRY_TEMPLATE_ID = os.getenv("PERSONA_INQUIRY_TEMPLATE_ID", "").strip().strip('"')


class PersonaError(RuntimeError):
    pass


def _headers() -> Dict[str, str]:
    if not PERSONA_API_KEY:
        raise PersonaError("Missing PERSONA_API_KEY")
    return {
        "Authorization": f"Bearer {PERSONA_API_KEY}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }


def create_inquiry(template_id: Optional[str] = None, reference_id: Optional[str] = None) -> dict:
    url = f"{PERSONA_API_BASE}/inquiries"
    payload: dict = {"data": {"type": "inquiry", "attributes": {}}}

    tmpl = template_id or PERSONA_INQUIRY_TEMPLATE_ID
    if tmpl:
        payload["data"]["attributes"]["inquiry-template-id"] = tmpl
    if reference_id:
        payload["data"]["attributes"]["reference-id"] = reference_id

    resp = requests.post(url, json=payload, headers=_headers(), timeout=20)
    if not resp.ok:
        raise PersonaError(f"Failed to create inquiry: {resp.status_code} {resp.text}")
    return resp.json()


def get_inquiry(inquiry_id: str, include: Optional[str] = None) -> dict:
    url = f"{PERSONA_API_BASE}/inquiries/{inquiry_id}"
    params: Dict[str, str] = {}
    if include:
        params["include"] = include
    resp = requests.get(url, params=params or None, headers=_headers(), timeout=20)
    if not resp.ok:
        raise PersonaError(f"Failed to fetch inquiry: {resp.status_code} {resp.text}")
    return resp.json()


def get_inquiry_with_includes(inquiry_id: str) -> dict:
    # Persona's API is strict about `include`. Some accounts/templates support includes like
    # `account`, while others will reject nested paths like `account.reports`.
    # We try a safe include first, then fall back to no include.
    for include in ("account", None):
        try:
            return get_inquiry(inquiry_id, include=include)
        except PersonaError as exc:
            msg = str(exc)
            if include is not None and ("not a valid include" in msg or "Bad request" in msg):
                continue
            raise

    return get_inquiry(inquiry_id)


@dataclass
class WatchlistReport:
    type: str
    status: Optional[str]
    decision: Optional[str]


def _is_watchlist_report(report_type: str) -> bool:
    t = (report_type or "").lower()
    return any(k in t for k in ("watchlist", "sanction", "ofac", "aml"))


def summarize_kyc(inquiry: dict) -> dict:
    data = inquiry.get("data") or {}
    attrs = data.get("attributes") or {}
    status = attrs.get("status")
    decision = attrs.get("decision")
    inquiry_url = attrs.get("inquiry-url") or attrs.get("inquiry_url")

    status_l = (status or "").lower()
    decision_l = (decision or "").lower()

    included: List[Dict[str, Any]] = inquiry.get("included") or []
    reports: List[WatchlistReport] = []
    blocked_by_watchlist = False

    for item in included:
        if (item.get("type") or "") != "report":
            continue
        rtype = (item.get("attributes") or {}).get("report-template-name") or item.get("attributes", {}).get("type") or "report"
        if not _is_watchlist_report(rtype):
            continue
        rattrs = item.get("attributes") or {}
        r_status = rattrs.get("status")
        r_decision = rattrs.get("decision")

        reports.append(WatchlistReport(type=str(rtype), status=r_status, decision=r_decision))

        if (r_decision or "").lower() in ("declined", "rejected", "failed"):
            blocked_by_watchlist = True
        if (r_status or "").lower() in ("failed", "declined"):
            blocked_by_watchlist = True
        if rattrs.get("match") is True or rattrs.get("has-match") is True:
            blocked_by_watchlist = True

    allowed = (decision_l == "approved" or status_l == "approved") and not blocked_by_watchlist

    return {
        "status": status,
        "decision": decision,
        "allowed": allowed,
        "blocked_by_watchlist": blocked_by_watchlist,
        "inquiry_url": inquiry_url,
        "watchlist_reports": [r.__dict__ for r in reports],
    }
