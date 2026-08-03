import hashlib
import json
import logging
import re

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
from django.db.models import Q, Sum

from .models import (
    INSTANCE_DOMAIN, Affiliate, AffiliateContract, ContractTemplate, Customer,
    Instance, SplitPayout, Subscription, WebhookEvent,
)

log = logging.getLogger(__name__)


def healthz(request):
    return JsonResponse({"ok": True})


def home(request):
    ctx = {}
    if request.user.is_authenticated:
        customer = Customer.objects.filter(user=request.user).first()
        ctx["customer"] = customer
        ctx["subscription"] = Subscription.objects.filter(customer=customer).order_by("-updated_at").first() if customer else None
        ctx["instances"] = (Instance.objects.filter(customer=customer)
                            .exclude(status=Instance.Status.DESTROYED)
                            .select_related("subscription") if customer else [])
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
    # Attribution is now recorded against the subscription — tell the browser to
    # forget the referral so a future signup can credit a different affiliate.
    request.session.pop("ref_code", None)
    request.session.pop("pending_instance", None)
    return render(request, "core/subscribe_success.html", {"ref_recorded": True})


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
    ctx = {"affiliate": aff, "template": template, "signed": signed}
    if aff:
        rows = SplitPayout.objects.filter(affiliate=aff).order_by("-created_at")
        agg = rows.aggregate(
            paid=Sum("cut_cents", filter=Q(status=SplitPayout.Status.PAID)),
            pending=Sum("cut_cents", filter=Q(status=SplitPayout.Status.SKIPPED_NO_ACCOUNT)),
        )
        ctx.update({
            "payouts": rows[:20],
            "paid_cents": agg["paid"] or 0,
            "pending_cents": agg["pending"] or 0,
            "direct_referrals": Customer.objects.filter(referred_by=aff).count(),
            "sub_affiliates": Affiliate.objects.filter(parent=aff).count(),
            "paid_dollars": f"{(agg['paid'] or 0) / 100:,.2f}",
            "pending_dollars": f"{(agg['pending'] or 0) / 100:,.2f}",
        })
    return render(request, "core/affiliate.html", ctx)


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
            "signer_ip": (request.META.get("HTTP_X_FORWARDED_FOR", request.META.get("REMOTE_ADDR", "")).split(",")[0].strip() or None),
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
        stripe.Webhook.construct_event(
            request.body, request.META.get("HTTP_STRIPE_SIGNATURE", ""),
            settings.STRIPE_WEBHOOK_SECRET,
        )
    except Exception:  # bad signature / payload
        log.warning("Stripe webhook signature verification failed")
        return HttpResponse(status=400)
    # construct_event is used ONLY to verify the signature. Processing runs on
    # the plain parsed JSON: stripe-python's StripeObject raises KeyError('get')
    # on dict-style .get(), and it is the same bytes we just verified.
    event = json.loads(request.body)

    record, created = WebhookEvent.objects.get_or_create(
        stripe_event_id=event["id"],
        defaults={"event_type": event["type"], "payload": event},
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


def _entitle(customer: Customer, status: str, period_end=None, sub_id: str = "", affiliate=None):
    sub = (Subscription.objects.filter(stripe_subscription_id=sub_id).first() if sub_id else None)
    if sub is None:
        sub = Subscription.objects.filter(customer=customer, stripe_subscription_id="").first()
    if sub is None:
        sub = Subscription(customer=customer)
    if affiliate is not None and sub.affiliate_id is None:
        sub.affiliate = affiliate  # frozen at subscription creation, never re-derived
    sub.status = status
    if sub_id:
        sub.stripe_subscription_id = sub_id
    if period_end:
        sub.current_period_end = timezone.datetime.fromtimestamp(period_end, tz=timezone.utc)
    sub.save()
    keycloak.set_subscription_active(customer.kc_user_id, sub.entitled)
    return sub


@transaction.atomic
def _process_event(event):
    t, obj = event["type"], event["data"]["object"]

    if t == "checkout.session.completed":
        customer = Customer.objects.select_for_update().get(pk=int(obj["client_reference_id"]))
        customer.stripe_customer_id = obj["customer"]
        if customer.instance_status == Customer.InstanceStatus.NONE:
            customer.instance_status = Customer.InstanceStatus.AWAITING
        customer.save(update_fields=["stripe_customer_id", "instance_status"])
        meta = obj.get("metadata") or {}
        instance = Instance.objects.filter(pk=meta.get("instance_id") or 0).first()
        aff = Affiliate.objects.filter(code=meta.get("ref_code") or "", active=True).first()
        sub = _entitle(customer, Subscription.Status.ACTIVE,
                       sub_id=obj.get("subscription") or "", affiliate=aff)
        if instance:
            instance.subscription = sub
            instance.status = Instance.Status.PROVISIONING
            instance.save(update_fields=["subscription", "status"])
            # The provisioning worker (operator side, holds fleet credentials)
            # polls for PROVISIONING instances and runs provision-instance.sh.
            log.info("PROVISION-REQUEST instance=%s subdomain=%s customer=%s",
                     instance.pk, instance.subdomain, customer.pk)

    elif t == "invoice.paid":
        customer = Customer.objects.filter(stripe_customer_id=obj["customer"]).select_for_update().first()
        if customer:
            sub = _entitle(customer, Subscription.Status.ACTIVE,
                           sub_id=obj.get("subscription") or "",
                           period_end=(obj.get("lines", {}).get("data") or [{}])[0].get("period", {}).get("end"))
            stripe_svc.pay_affiliate_splits(obj, sub)

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


# ── instance signup: claim a subdomain, then pay for THAT instance ─────────
SUBDOMAIN_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{1,38}[a-z0-9])$")


def _subdomain_error(name: str) -> str:
    if not name:
        return "Choose a name for your instance."
    if not SUBDOMAIN_RE.match(name):
        return ("Use 3–40 characters: lowercase letters, numbers and hyphens, "
                "starting and ending with a letter or number.")
    if name in Instance.RESERVED:
        return "That name is reserved — please choose another."
    if Instance.objects.filter(subdomain=name).exclude(status=Instance.Status.DESTROYED).exists():
        return "That name is already taken."
    return ""


@login_required
def check_subdomain(request):
    """Live availability check for the signup form."""
    name = (request.GET.get("name") or "").strip().lower()
    err = _subdomain_error(name)
    return JsonResponse({"available": not err, "error": err,
                         "domain": f"{name}.{INSTANCE_DOMAIN}" if name else ""})


@login_required
def new_instance(request):
    customer, _ = Customer.objects.get_or_create(user=request.user)
    if request.method != "POST":
        return render(request, "core/new_instance.html", {"domain": INSTANCE_DOMAIN})
    name = (request.POST.get("subdomain") or "").strip().lower()
    err = _subdomain_error(name)
    if err:
        return render(request, "core/new_instance.html",
                      {"domain": INSTANCE_DOMAIN, "error": err, "value": name}, status=400)
    instance = Instance.objects.create(
        customer=customer, subdomain=name,
        display_name=(request.POST.get("display_name") or "").strip()[:80],
    )
    # Affiliate attribution is decided HERE, at subscribe time, and frozen onto
    # the subscription when checkout completes.
    ref = (request.POST.get("ref") or request.session.get("ref_code") or "").strip()
    if ref:
        request.session["ref_code"] = ref
    request.session["pending_instance"] = instance.pk
    base = f"https://{settings.ALLOWED_HOSTS[0]}"
    session = stripe_svc.create_checkout_session(
        customer, success_url=f"{base}/subscribe/success/", cancel_url=f"{base}/",
        instance=instance,
    )
    return redirect(session.url, permanent=False)
