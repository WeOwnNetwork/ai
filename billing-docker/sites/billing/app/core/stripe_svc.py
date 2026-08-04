"""Stripe integration — single product, Checkout for signup, Billing Portal
for self-service, webhooks drive entitlement.

Affiliate economics (Nik, 2026-08-03): 2-tier splits are percentages of
PROFIT per invoice, not gross:
    profit = amount_paid − actual Stripe fee (charge's balance transaction)
             − COGS (admin-configured cents per instance-month, SplitConfig)
Every computation writes a SplitPayout audit row, including skipped legs, so
the money math is always inspectable in admin. Transfers go out via Stripe
Connect only for affiliates that completed Connect onboarding."""
import logging
from decimal import Decimal

import stripe
from django.conf import settings

from .models import Affiliate, SplitConfig, SplitPayout

log = logging.getLogger(__name__)


def _client():
    stripe.api_key = settings.STRIPE_SECRET_KEY
    return stripe


def create_checkout_session(customer, success_url: str, cancel_url: str, instance=None, ref_code: str = ""):
    s = _client()
    kwargs = {
        "mode": "subscription",
        "line_items": [{"price": settings.STRIPE_PRICE_ID, "quantity": 1}],
        "success_url": success_url,
        "cancel_url": cancel_url,
        "client_reference_id": str(customer.pk),
        # Attribution + target instance travel with the session so the webhook
        # freezes them onto the subscription at creation time.
        "metadata": {"instance_id": str(instance.pk) if instance else "",
                     "ref_code": ref_code or ""},
        "subscription_data": {"metadata": {"instance_id": str(instance.pk) if instance else ""}},
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


def splits_for(affiliate: Affiliate) -> list[tuple[int, Affiliate, Decimal]]:
    """Resolve the 2-tier legs for a referral: [(tier, affiliate, pct), ...]."""
    cfg = SplitConfig.current()
    legs = [(1, affiliate, affiliate.tier1_pct_override or cfg.tier1_pct)]
    if affiliate.parent and affiliate.parent.active:
        legs.append((2, affiliate.parent, affiliate.parent.tier2_pct_override or cfg.tier2_pct))
    return legs


def _stripe_fee_cents(charge_id: str) -> int:
    """Actual processing fee from the charge's balance transaction. Raises on
    lookup failure — the webhook then 500s and Stripe retries, rather than
    silently splitting on a wrong basis."""
    s = _client()
    charge = s.Charge.retrieve(charge_id, expand=["balance_transaction"])
    return int(charge["balance_transaction"]["fee"])


def pay_affiliate_splits(invoice: dict, subscription) -> None:
    """On invoice.paid: compute profit, audit every leg, transfer where the
    affiliate is onboarded. Attribution comes from the SUBSCRIPTION (frozen when
    it was created) — never re-derived, so money already collected is never
    re-attributed. Idempotent per (invoice, affiliate, tier)."""
    aff = subscription.affiliate if subscription else None
    if not aff or not aff.active:
        return
    gross = int(invoice.get("amount_paid") or 0)  # cents
    charge = invoice.get("charge")
    if not gross or not charge:
        return
    legs = splits_for(aff)
    existing = set(SplitPayout.objects.filter(
        invoice_id=invoice["id"], affiliate__in=[a for _, a, _ in legs]
    ).values_list("affiliate_id", "tier"))
    if all((a.id, t) in existing for t, a, _ in legs):
        return  # webhook replay — everything already computed
    s = _client()
    cfg = SplitConfig.current()
    fee = _stripe_fee_cents(charge)
    profit = gross - fee - cfg.monthly_cogs_cents

    for tier, leg_aff, pct in legs:
        if (leg_aff.id, tier) in existing:
            continue  # already computed (webhook replay)
        cut = int(Decimal(profit) * pct / 100) if profit > 0 else 0
        row = SplitPayout(
            invoice_id=invoice["id"], affiliate=leg_aff, tier=tier,
            gross_cents=gross, stripe_fee_cents=fee, cogs_cents=cfg.monthly_cogs_cents,
            profit_cents=profit, pct=pct, cut_cents=cut,
        )
        if profit <= 0 or cut <= 0:
            row.status = SplitPayout.Status.SKIPPED_NO_PROFIT
        elif not leg_aff.stripe_connect_account_id:
            row.status = SplitPayout.Status.SKIPPED_NO_ACCOUNT
            log.warning("Split leg skipped (no Connect account): %s owed %s%% of profit %sc on %s",
                        leg_aff.code, pct, profit, invoice["id"])
        else:
            transfer = s.Transfer.create(
                amount=cut,
                currency=invoice.get("currency", "usd"),
                destination=leg_aff.stripe_connect_account_id,
                source_transaction=charge,
                transfer_group=f"invoice:{invoice['id']}",
                description=f"WeOwn affiliate split T{tier} {leg_aff.code} ({pct}% of profit)",
                idempotency_key=f"split:{invoice['id']}:{leg_aff.code}:{tier}",
            )
            row.status = SplitPayout.Status.PAID
            row.stripe_transfer_id = transfer["id"]
            log.info("Split paid: %s T%s -> %s (%s%% of profit %sc = %sc)",
                     invoice["id"], tier, leg_aff.code, pct, profit, cut)
        row.save()
