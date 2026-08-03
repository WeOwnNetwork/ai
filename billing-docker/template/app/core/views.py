import hashlib
import json
import logging

import stripe
from django.conf import settings
from django.contrib.auth.decorators import login_required
from django.db import transaction
from django.http import HttpResponse, JsonResponse
from django.shortcuts import redirect, render
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST

from . import keycloak, stripe_svc
from .models import (
    Affiliate, AffiliateContract, ContractTemplate, Customer, Subscription, WebhookEvent,
)

log = logging.getLogger(__name__)


def healthz(request):
    return JsonResponse({"ok": True})


def home(request):
    ctx = {}
    if request.user.is_authenticated:
        customer = Customer.objects.filter(user=request.user).first()
        ctx["customer"] = customer
        ctx["subscription"] = Subscription.objects.filter(customer=customer).first() if customer else None
        ctx["affiliate"] = Affiliate.objects.filter(user=request.user).first()
    return render(request, "core/home.html", ctx)


def suspended(request):
    """The friendly wall every gated surface links to."""
    return render(request, "core/suspended.html")


@login_required
def subscribe(request):
    customer, _ = Customer.objects.get_or_create(user=request.user)
    # attach referral if they arrived via ?ref=<code> earlier this session
    ref = request.session.pop("ref_code", None)
    if ref and not customer.referred_by:
        customer.referred_by = Affiliate.objects.filter(code=ref, active=True).first()
        customer.save(update_fields=["referred_by"])
    base = f"https://{settings.ALLOWED_HOSTS[0]}"
    session = stripe_svc.create_checkout_session(
        customer, success_url=f"{base}/subscribe/success/", cancel_url=f"{base}/"
    )
    return redirect(session.url, permanent=False)


@login_required
def subscribe_success(request):
    return render(request, "core/subscribe_success.html")


@login_required
def customer_portal(request):
    customer = Customer.objects.filter(user=request.user).first()
    if not customer or not customer.stripe_customer_id:
        return redirect("home")
    base = f"https://{settings.ALLOWED_HOSTS[0]}"
    session = stripe_svc.create_portal_session(customer, return_url=f"{base}/")
    return redirect(session.url, permanent=False)


@login_required
def affiliate_home(request):
    aff = Affiliate.objects.filter(user=request.user).first()
    template = ContractTemplate.objects.filter(active=True).first()
    signed = bool(
        aff and template
        and AffiliateContract.objects.filter(affiliate=aff, template=template).exists()
    )
    return render(request, "core/affiliate.html", {
        "affiliate": aff, "template": template, "signed": signed,
    })


@login_required
@require_POST
def affiliate_contract(request):
    """Click-wrap signature: records who accepted which exact text, when,
    from where — then activates the affiliate."""
    aff = Affiliate.objects.filter(user=request.user).first()
    template = ContractTemplate.objects.filter(active=True).first()
    signed_name = (request.POST.get("signed_name") or "").strip()
    if not (aff and template and signed_name and request.POST.get("agree") == "on"):
        return render(request, "core/affiliate.html", {
            "affiliate": aff, "template": template, "signed": False,
            "error": "Type your full name and tick the agreement box.",
        }, status=400)
    AffiliateContract.objects.get_or_create(
        affiliate=aff, template=template,
        defaults={
            "body_sha256": hashlib.sha256(template.body_md.encode()).hexdigest(),
            "signed_name": signed_name,
            "signer_email": request.user.email,
            "signer_ip": request.META.get("HTTP_X_FORWARDED_FOR", request.META.get("REMOTE_ADDR", "")).split(",")[0].strip(),
            "user_agent": request.META.get("HTTP_USER_AGENT", "")[:300],
        },
    )
    if not aff.active:
        aff.active = True
        aff.save(update_fields=["active"])
    return redirect("affiliate_home")


@csrf_exempt
@require_POST
def stripe_webhook(request):
    try:
        event = stripe.Webhook.construct_event(
            request.body, request.META.get("HTTP_STRIPE_SIGNATURE", ""),
            settings.STRIPE_WEBHOOK_SECRET,
        )
    except Exception:  # bad signature / payload
        log.warning("Stripe webhook signature verification failed")
        return HttpResponse(status=400)

    record, created = WebhookEvent.objects.get_or_create(
        stripe_event_id=event["id"],
        defaults={"event_type": event["type"], "payload": json.loads(request.body)},
    )
    if not created and record.processed:
        return HttpResponse(status=200)  # idempotent replay

    try:
        _process_event(event)
        record.processed = True
        record.error = ""
    except Exception as exc:  # noqa: BLE001 — recorded, Stripe will retry on 500
        log.exception("webhook processing failed: %s", event["type"])
        record.error = str(exc)[:2000]
        record.save(update_fields=["error"])
        return HttpResponse(status=500)
    record.save(update_fields=["processed", "error"])
    return HttpResponse(status=200)


def _entitle(customer: Customer, status: str, period_end=None, sub_id: str = ""):
    sub, _ = Subscription.objects.get_or_create(customer=customer)
    sub.status = status
    if sub_id:
        sub.stripe_subscription_id = sub_id
    if period_end:
        sub.current_period_end = timezone.datetime.fromtimestamp(period_end, tz=timezone.utc)
    sub.save()
    keycloak.set_subscription_active(customer.kc_user_id, sub.entitled)


@transaction.atomic
def _process_event(event):
    t, obj = event["type"], event["data"]["object"]
    # stripe-python's StripeObject does NOT expose dict.get (attribute lookup
    # raises KeyError: 'get') — normalize to plain nested dicts once.
    if hasattr(obj, "to_dict_recursive"):
        obj = obj.to_dict_recursive()

    if t == "checkout.session.completed":
        customer = Customer.objects.select_for_update().get(pk=int(obj["client_reference_id"]))
        customer.stripe_customer_id = obj["customer"]
        customer.save(update_fields=["stripe_customer_id"])
        _entitle(customer, Subscription.Status.ACTIVE, sub_id=obj.get("subscription") or "")
        # Provisioning hook: the instance is created AFTER payment. v1 = loud
        # log line an operator acts on; later = drive weown-fleet directly.
        log.info("PROVISION-REQUEST customer=%s email=%s", customer.pk, customer.user.email)

    elif t == "invoice.paid":
        customer = Customer.objects.filter(stripe_customer_id=obj["customer"]).select_for_update().first()
        if customer:
            _entitle(customer, Subscription.Status.ACTIVE,
                     period_end=(obj.get("lines", {}).get("data") or [{}])[0].get("period", {}).get("end"))
            stripe_svc.pay_affiliate_splits(obj, customer)

    elif t == "invoice.payment_failed":
        customer = Customer.objects.filter(stripe_customer_id=obj["customer"]).select_for_update().first()
        if customer:
            _entitle(customer, Subscription.Status.PAST_DUE)

    elif t in ("customer.subscription.deleted", "customer.subscription.paused"):
        customer = Customer.objects.filter(stripe_customer_id=obj["customer"]).select_for_update().first()
        if customer:
            _entitle(customer, Subscription.Status.CANCELED)

    elif t == "customer.subscription.updated":
        customer = Customer.objects.filter(stripe_customer_id=obj["customer"]).select_for_update().first()
        if customer:
            status = {"active": Subscription.Status.ACTIVE, "past_due": Subscription.Status.PAST_DUE,
                      "canceled": Subscription.Status.CANCELED}.get(obj["status"])
            if status:
                _entitle(customer, status, period_end=obj.get("current_period_end"),
                         sub_id=obj.get("id", ""))
