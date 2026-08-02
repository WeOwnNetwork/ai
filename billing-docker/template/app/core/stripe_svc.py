"""Stripe integration — single product, Checkout for signup, Billing Portal
for self-service, webhooks drive entitlement. 2-tier affiliate splits are
recorded per-invoice and paid via Connect transfers (destination charges are
not used because the tier-2 leg needs a second transfer anyway)."""
import logging
from decimal import Decimal

import stripe
from django.conf import settings

from .models import Affiliate, SplitConfig

log = logging.getLogger(__name__)


def _client():
    stripe.api_key = settings.STRIPE_SECRET_KEY
    return stripe


def create_checkout_session(customer, success_url: str, cancel_url: str):
    s = _client()
    kwargs = {
        "mode": "subscription",
        "line_items": [{"price": settings.STRIPE_PRICE_ID, "quantity": 1}],
        "success_url": success_url,
        "cancel_url": cancel_url,
        "client_reference_id": str(customer.pk),
    }
    if customer.stripe_customer_id:
        kwargs["customer"] = customer.stripe_customer_id
    else:
        kwargs["customer_email"] = customer.user.email
    return s.checkout.Session.create(**kwargs)


def create_portal_session(customer, return_url: str):
    s = _client()
    return s.billing_portal.Session.create(
        customer=customer.stripe_customer_id, return_url=return_url
    )


def splits_for(affiliate: Affiliate) -> list[tuple[Affiliate, Decimal]]:
    """Resolve the 2-tier split legs for a referral: [(tier1, pct), (tier2, pct)]."""
    cfg = SplitConfig.current()
    legs = [(affiliate, affiliate.tier1_pct_override or cfg.tier1_pct)]
    if affiliate.parent and affiliate.parent.active:
        legs.append((affiliate.parent, affiliate.parent.tier2_pct_override or cfg.tier2_pct))
    return legs


def pay_affiliate_splits(invoice: dict, customer) -> None:
    """On invoice.paid: transfer each leg its cut via Connect. Idempotent per
    invoice via transfer_group + idempotency keys."""
    aff = customer.referred_by
    if not aff or not aff.active:
        return
    s = _client()
    amount_paid = invoice.get("amount_paid") or 0  # cents
    charge = invoice.get("charge")
    if not amount_paid or not charge:
        return
    for leg_aff, pct in splits_for(aff):
        if not leg_aff.stripe_connect_account_id:
            log.warning("Affiliate %s has no Connect account — split leg skipped (owed %s%% of %s)",
                        leg_aff.code, pct, amount_paid)
            continue
        cut = int(Decimal(amount_paid) * pct / 100)
        if cut <= 0:
            continue
        s.Transfer.create(
            amount=cut,
            currency=invoice.get("currency", "usd"),
            destination=leg_aff.stripe_connect_account_id,
            source_transaction=charge,
            transfer_group=f"invoice:{invoice['id']}",
            description=f"WeOwn affiliate split {leg_aff.code} ({pct}%)",
            idempotency_key=f"split:{invoice['id']}:{leg_aff.code}",
        )
        log.info("Split paid: %s -> %s (%s%% of %s)", invoice["id"], leg_aff.code, pct, amount_paid)
