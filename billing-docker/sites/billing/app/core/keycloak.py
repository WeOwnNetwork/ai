"""Flip subscription_active on the Keycloak user via a service-account client.

The attribute is the fleet-wide entitlement signal: the ALLM dashboard and any
SSO'd surface read it from the token/userinfo and show the friendly
"account needs to be enabled" page when false. Payment webhooks flip it back —
instant reactivation, no redeploy, no droplet touch."""
import logging

import requests
from django.conf import settings

log = logging.getLogger(__name__)


def _admin_base() -> tuple[str, str]:
    # issuer: https://host/realms/<realm> -> admin API https://host/admin/realms/<realm>
    issuer = settings.OIDC_OP_ISSUER
    host, _, realm = issuer.partition("/realms/")
    return f"{host}/admin/realms/{realm}", issuer


def _admin_token(issuer: str) -> str:
    r = requests.post(
        f"{issuer}/protocol/openid-connect/token",
        data={
            "grant_type": "client_credentials",
            "client_id": settings.KC_ADMIN_CLIENT_ID,
            "client_secret": settings.KC_ADMIN_CLIENT_SECRET,
        },
        timeout=15,
    )
    r.raise_for_status()
    return r.json()["access_token"]


def set_subscription_active(kc_user_id: str, active: bool) -> bool:
    """Best-effort with loud logging; billing DB stays the source of truth."""
    if not kc_user_id or not settings.KC_ADMIN_CLIENT_SECRET:
        log.warning("KC flip skipped (kc_user_id=%r, secret set=%s)", kc_user_id, bool(settings.KC_ADMIN_CLIENT_SECRET))
        return False
    try:
        base, issuer = _admin_base()
        tok = _admin_token(issuer)
        h = {"Authorization": f"Bearer {tok}"}
        u = requests.get(f"{base}/users/{kc_user_id}", headers=h, timeout=15)
        u.raise_for_status()
        body = u.json()
        attrs = body.get("attributes") or {}
        attrs["subscription_active"] = ["true" if active else "false"]
        body["attributes"] = attrs
        p = requests.put(f"{base}/users/{kc_user_id}", headers=h, json=body, timeout=15)
        p.raise_for_status()
        log.info("KC subscription_active=%s for %s", active, kc_user_id)
        return True
    except Exception:  # noqa: BLE001 — never let a KC hiccup break webhook processing
        log.exception("KC subscription_active flip FAILED for %s", kc_user_id)
        return False
