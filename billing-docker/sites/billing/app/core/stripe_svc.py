"""Stripe integration — single product, Checkout for signup, Billing Portal
for self-service, webhooks drive entitlement.

Affiliate economics (Nik, 2026-08-03): 2-tier splits are percentages of
PROFIT per invoice, not gross:
    profit = amount_paid − actual Stripe fee (charge's balance transaction)
             − COGS (admin-configured cents per instance-month, SplitConfig)
Every computation writes a SplitPayout audit row, including skipped legs, so
the money math is always inspectable in admin. Transfers go out via Stripe
Connect only for affiliates that completed Connect onboarding."""
import hashlib
import json
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


def _charge_for_invoice(invoice) -> str:
    """The charge that actually paid this invoice, or "" if it can't be found.

    Worth the three hops. Stripe's current API removed `invoice.charge` and
    `invoice.payment_intent`; the payment is now its own InvoicePayment object.
    Without the charge id a transfer has no `source_transaction`, so it draws on
    the platform's *available* balance — which is zero while the charge is still
    pending, and the payout fails with "insufficient available funds". Tied to
    the charge, Stripe allows it against the pending funds.
    """
    direct = _field(invoice, "charge")
    if direct:
        return direct
    invoice_id = _field(invoice, "id")
    if not invoice_id:
        return ""
    s = _client()
    try:
        payments = s.InvoicePayment.list(invoice=invoice_id, limit=10)
        for p in payments.data:
            if _field(p, "status") != "paid":
                continue
            pi_id = _field(_field(p, "payment"), "payment_intent")
            if not pi_id:
                continue
            return _field(s.PaymentIntent.retrieve(pi_id), "latest_charge") or ""
    except Exception:
        log.exception("could not resolve the charge for invoice %s", invoice_id)
    return ""


def pay_affiliate_splits(invoice: dict, subscription) -> list[str]:
    """On invoice.paid: compute profit, audit every leg, transfer where the
    affiliate is onboarded. Attribution comes from the SUBSCRIPTION (frozen when
    it was created) — never re-derived, so money already collected is never
    re-attributed. Idempotent per (invoice, affiliate, tier).

    Returns a list of human-readable failures — it does NOT raise. This is load
    bearing: the caller runs inside a database transaction, so raising here
    would roll back the audit rows for transfers that have *already left
    Stripe*. That is precisely how weown-partner got paid twice on
    in_1U0sY941ERjsEaTsfeajnGtf (2026-08-04): a failing leg raised, the
    successful leg's PAID row was rolled back with it, and the replay saw an
    unrecorded leg and sent the money again. Money that has moved must never be
    un-recorded by a rollback; the caller decides how to report the failures
    after the rows are safely committed.
    """
    aff = subscription.affiliate if subscription else None
    if not aff or not aff.active:
        return []
    gross = int(_field(invoice, "amount_paid") or 0)  # cents
    charge = _charge_for_invoice(invoice)
    if not gross:
        log.warning("invoice %s has no amount_paid — no splits computed", _field(invoice, "id"))
        return []
    legs = splits_for(aff)
    invoice_id = _field(invoice, "id")
    # A FAILED leg is deliberately not "settled" — it must be retried. Anything
    # else (paid, or skipped for a recorded reason) is final for this invoice.
    settled = set(SplitPayout.objects.filter(
        invoice_id=invoice_id, affiliate__in=[a for _, a, _ in legs]
    ).exclude(status=SplitPayout.Status.FAILED).values_list("affiliate_id", "tier"))
    if all((a.id, t) in settled for t, a, _ in legs):
        return []  # webhook replay — everything already computed
    s = _client()
    cfg = SplitConfig.current()
    # No charge id means no balance transaction to read the real fee from.
    # Fall back to Stripe's standard card rate rather than skipping the split;
    # the audit row records which basis was used.
    fee = _stripe_fee_cents(charge) if charge else int(gross * 0.029) + 30
    profit = gross - fee - cfg.monthly_cogs_cents
    failures: list[str] = []

    for tier, leg_aff, pct in legs:
        if (leg_aff.id, tier) in settled:
            continue  # already computed (webhook replay)
        cut = int(Decimal(profit) * pct / 100) if profit > 0 else 0
        # Reuse the row when retrying a previously failed leg — (invoice,
        # affiliate, tier) is unique, and the audit trail should show one row
        # per leg with its final outcome, not a pile of attempts.
        row = SplitPayout.objects.filter(
            invoice_id=invoice_id, affiliate=leg_aff, tier=tier
        ).first() or SplitPayout(invoice_id=invoice_id, affiliate=leg_aff, tier=tier)
        row.gross_cents, row.stripe_fee_cents = gross, fee
        row.cogs_cents, row.profit_cents = cfg.monthly_cogs_cents, profit
        row.pct, row.cut_cents, row.error = pct, cut, ""
        if profit <= 0 or cut <= 0:
            row.status = SplitPayout.Status.SKIPPED_NO_PROFIT
        elif not leg_aff.stripe_connect_account_id:
            row.status = SplitPayout.Status.SKIPPED_NO_ACCOUNT
            log.warning("Split leg skipped (no Connect account): %s owed %s%% of profit %sc on %s",
                        leg_aff.code, pct, profit, invoice_id)
        else:
            kw = dict(
                amount=cut,
                currency=_field(invoice, "currency") or "usd",
                destination=leg_aff.stripe_connect_account_id,
                transfer_group=f"invoice:{invoice_id}",
                description=f"WeOwn affiliate split T{tier} {leg_aff.code} ({pct}% of profit)",
            )
            if charge:
                kw["source_transaction"] = charge
            # The idempotency key describes the REQUEST, not just the leg.
            # Stripe rejects a reused key whose parameters changed, so a
            # leg-only key gets permanently burned by a broken attempt — a
            # corrected retry can then never go through. Double-paying is
            # prevented by the unique (invoice, affiliate, tier) row and the
            # `settled` check above, both of which run before any API call.
            fingerprint = hashlib.sha256(
                json.dumps(kw, sort_keys=True, default=str).encode()
            ).hexdigest()[:16]
            kw["idempotency_key"] = f"split:{invoice_id}:{leg_aff.code}:{tier}:{fingerprint}"
            # A failing leg records itself and lets the other legs run — one
            # affiliate's broken Connect account must not cost the other their
            # payout, and a failure with no audit row is invisible.
            try:
                transfer = s.Transfer.create(**kw)
            except Exception as exc:
                row.status = SplitPayout.Status.FAILED
                row.error = f"{type(exc).__name__}: {exc}"[:2000]
                failures.append(f"T{tier} {leg_aff.code}: {exc}")
                log.exception("Split transfer FAILED: %s T%s -> %s", invoice_id, tier, leg_aff.code)
            else:
                row.status = SplitPayout.Status.PAID
                row.stripe_transfer_id = transfer["id"]
                log.info("Split paid: %s T%s -> %s (%s%% of profit %sc = %sc)",
                         invoice_id, tier, leg_aff.code, pct, profit, cut)
        row.save()

    return failures


def _field(obj, key, default=None):
    """Read a field from a stripe-python object OR a plain dict.

    StripeObject supports attribute access and item access but not .get();
    dicts support .get() but not attribute access. Anything that reads a
    Stripe response goes through here so the difference can never bite again.
    """
    if obj is None:
        return default
    if isinstance(obj, dict):
        return obj.get(key, default)
    try:
        return obj[key]
    except Exception:  # noqa: BLE001
        return getattr(obj, key, default)


def connect_account_status(affiliate) -> dict:
    """What Stripe thinks of this affiliate's payout account. Cheap enough to
    call on the affiliate page; degrades to 'unknown' rather than erroring."""
    if not affiliate.stripe_connect_account_id:
        return {"exists": False, "payouts_enabled": False, "details_submitted": False,
                "requirements_due": [], "lookup_ok": True}
    try:
        # stripe-python objects support ATTRIBUTE access and __getitem__, but
        # NOT dict.get() — that raises AttributeError('get'), and to_dict_recursive
        # does not exist on this version either. This cost us three separate
        # bugs (webhook processing, key generation, and here — where a broad
        # except turned a read error into "payouts never connect", with the real
        # cause visible to nobody). _field() works whichever shape we are handed.
        acct = _client().Account.retrieve(affiliate.stripe_connect_account_id)
        reqs = _field(acct, "requirements") or {}
        return {"exists": True,
                "payouts_enabled": bool(_field(acct, "payouts_enabled")),
                "details_submitted": bool(_field(acct, "details_submitted")),
                "requirements_due": list(_field(reqs, "currently_due") or []),
                "lookup_ok": True}
    except Exception:  # noqa: BLE001 — never break the page over a Stripe hiccup
        log.exception("Connect account lookup FAILED for %s", affiliate.code)
        # Say we could not tell, rather than asserting "not connected" — a
        # failed lookup and a genuinely unconnected account are different facts.
        return {"exists": True, "payouts_enabled": False, "details_submitted": False,
                "requirements_due": [], "lookup_ok": False}


def connect_onboarding_url(affiliate, return_url: str) -> str:
    """Create the affiliate's Express account if needed and return a fresh
    onboarding link. Links are single-use and expire in minutes, which is
    exactly why this is generated on demand from a button rather than emailed."""
    s = _client()
    if not affiliate.stripe_connect_account_id:
        acct = s.Account.create(
            type="express", email=affiliate.user.email,
            capabilities={"transfers": {"requested": True}},
            business_type="individual", metadata={"affiliate_code": affiliate.code},
        )
        affiliate.stripe_connect_account_id = _field(acct, "id")
        affiliate.save(update_fields=["stripe_connect_account_id"])
        log.info("Connect account created for %s", affiliate.code)
    status = connect_account_status(affiliate)
    if status.get("details_submitted"):
        # Already onboarded — send them to their Express dashboard instead.
        return _field(s.Account.create_login_link(affiliate.stripe_connect_account_id), "url")
    return _field(s.AccountLink.create(
        account=affiliate.stripe_connect_account_id,
        refresh_url=return_url, return_url=return_url, type="account_onboarding",
    ), "url")
