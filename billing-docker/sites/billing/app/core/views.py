import datetime
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

from . import keycloak, mail, stripe_svc
from django.db.models import Q, Sum

from .models import (
    INSTANCE_DOMAIN, Affiliate, AffiliateContract, ContractTemplate, Customer,
    CustomerContract, Instance, SplitPayout, Subscription, WebhookEvent,
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
        ctx["provisioning_now"] = any(
            i.status == Instance.Status.PROVISIONING for i in ctx["instances"]
        )
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
    # Same hard gate as new_instance — this is the second door to Checkout and
    # a gate on only one door is not a gate.
    template, signed = _customer_agreement_state(customer)
    if not signed:
        if not template:
            log.error("Checkout blocked: no active customer ContractTemplate is published")
            return render(request, "core/customer_agreement.html",
                          {"template": None,
                           "error": "No customer agreement is published yet — "
                                    "please contact support."}, status=409)
        return redirect("customer_agreement")
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
    template = ContractTemplate.active_for(ContractTemplate.Kind.AFFILIATE)
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
            "connect": stripe_svc.connect_account_status(aff),
        })
    return render(request, "core/affiliate.html", ctx)


@login_required
@require_POST
def affiliate_contract(request):
    """Click-wrap signature: records who accepted which exact text, when,
    from where — then activates the affiliate."""
    aff = Affiliate.objects.filter(user=request.user).first()
    template = ContractTemplate.active_for(ContractTemplate.Kind.AFFILIATE)
    signed_name = (request.POST.get("signed_name") or "").strip()
    if not (aff and template and signed_name and request.POST.get("agree") == "on"):
        return render(request, "core/affiliate.html", {
            "affiliate": aff, "template": template, "signed": False,
            "error": "Type your full name and tick the agreement box.",
        }, status=400)
    signer_ip, forwarded_for = _signer_origin(request)
    AffiliateContract.objects.get_or_create(
        affiliate=aff, template=template,
        defaults={
            "body_sha256": hashlib.sha256(template.body_md.encode()).hexdigest(),
            "signed_name": signed_name,
            "signer_email": request.user.email,
            "signer_ip": signer_ip,
            "signer_forwarded_for": forwarded_for,
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
        failures = _process_event(event)
        record.processed = not failures
        record.error = "; ".join(failures)[:2000]
    except Exception as exc:  # noqa: BLE001 — recorded, Stripe will retry on 500
        log.exception("webhook processing failed: %s", event["type"])
        record.error = str(exc)[:2000]
        record.save(update_fields=["error"])
        return HttpResponse(status=500)
    record.save(update_fields=["processed", "error"])
    if failures:
        # The transaction has committed, so every transfer that DID go through
        # is recorded. 500 asks Stripe to retry; the retry skips settled legs.
        log.error("split failures on %s: %s", event["type"], record.error)
        return HttpResponse(status=500)
    return HttpResponse(status=200)


def _signer_origin(request) -> tuple[str | None, str]:
    """(authoritative client IP, raw X-Forwarded-For chain) for a signature record.

    Getting this wrong makes the click-wrap evidence worthless, and the obvious
    two readings are both wrong for this deployment:

    * `X-Forwarded-For.split(",")[0]` — the LEFTMOST entry — is whatever the
      client sent. Anyone can add `X-Forwarded-For: 1.2.3.4` to their request
      and have that recorded as the IP they signed from.
    * plain `REMOTE_ADDR` is the Caddy container (`reverse_proxy web:8000`),
      the same private address for every signature ever taken.

    Caddy APPENDS the real peer to any inbound chain, so with exactly one proxy
    in front of Django the RIGHTMOST entry is the address Caddy actually saw and
    the only one a client cannot forge. The full chain is returned alongside it
    and stored verbatim: if the topology ever gains a second hop, the evidence
    is still there to re-interpret, and a spoof attempt is visible rather than
    silently recorded as fact.

    ⚠️ LOAD-BEARING ASSUMPTION: **Caddy is the OUTERMOST proxy.** Verified
    2026-08-11 — the billing host's A record points straight at its DigitalOcean
    droplet, so the zone is DNS-only and Caddy's peer is the end client.

    **If a CDN/WAF is ever put in front of this host — proxying `billing.*`
    through Cloudflare's orange cloud is a one-click DNS toggle, and WeOwn is
    mid-migration onto Cloudflare (D434) — this function silently starts
    recording the CDN's edge IP** for every signature. Nothing raises: the
    click-wrap evidence just quietly becomes a handful of repeated Cloudflare
    addresses, which is the exact failure this record exists to prevent.

    Making that move safely means switching to the CDN's own client-IP header
    (`CF-Connecting-IP` for Cloudflare) AND verifying the request arrived from
    that CDN's published IP ranges — a header alone is as forgeable as the
    leftmost XFF hop. Do not "just add the header"; the range check is what
    makes it trustworthy. Cross-referenced in the model docstring and in
    docs/handoff/DRILL-billing-end-to-end-real-money.md.
    """
    chain = (request.META.get("HTTP_X_FORWARDED_FOR") or "").strip()
    if chain:
        hops = [h.strip() for h in chain.split(",") if h.strip()]
        if hops:
            return hops[-1], chain[:300]
    return (request.META.get("REMOTE_ADDR") or "").strip() or None, ""


def _mail_after_commit(customer, kind, ctx=None):
    """Queue a lifecycle email to fire AFTER this transaction commits — so the
    SMTP round-trip never holds a DB lock, and a failed send never rolls back
    the entitlement change. Best-effort by construction (mail.notify swallows)."""
    email = getattr(getattr(customer, "user", None), "email", "")
    name = (getattr(getattr(customer, "user", None), "first_name", "") or "").strip()
    payload = {"name": name, **(ctx or {})}
    transaction.on_commit(lambda: mail.notify(email, kind, payload))


def _ts(epoch):
    """Stripe epoch seconds -> aware datetime (django.utils.timezone.utc was
    removed in Django 5, so use the stdlib's)."""
    if not epoch:
        return None
    return datetime.datetime.fromtimestamp(epoch, tz=datetime.timezone.utc)


# Distinguishes "caller said nothing about the trial" from "Stripe told us the
# trial is over" — the latter arrives as an explicit None and MUST clear the
# stored date. A plain None default cannot tell those apart.
_UNSET = object()


def _entitle(customer: Customer, status: str, period_end=None, sub_id: str = "", affiliate=None,
             trial_end=_UNSET):
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
        sub.current_period_end = _ts(period_end)
    if trial_end is not _UNSET:
        # Written on every event that carries the field, INCLUDING the explicit
        # None Stripe sends once the trial has converted — leaving a stale date
        # behind would make a paying customer look like they are still trialing.
        sub.trial_end = _ts(trial_end)
    sub.save()
    keycloak.set_subscription_active(customer.kc_user_id, sub.entitled)
    return sub


# Stripe subscription status -> our status. `trialing` and `active` are both
# entitled; the difference is whether money has been collected yet.
_SUB_STATUS = {
    "trialing": Subscription.Status.TRIALING,
    "active": Subscription.Status.ACTIVE,
    "past_due": Subscription.Status.PAST_DUE,
    "canceled": Subscription.Status.CANCELED,
    "unpaid": Subscription.Status.CANCELED,
    "incomplete": Subscription.Status.INCOMPLETE,
    "incomplete_expired": Subscription.Status.CANCELED,
}


@transaction.atomic
def _process_event(event) -> list[str]:
    """Apply one Stripe event. Returns non-fatal failures (currently: split
    transfers that did not go through) for the caller to report AFTER this
    transaction commits. Genuine errors still raise and roll back — but
    anything that already moved money must not, or its audit row is lost while
    the money is gone."""
    t, obj = event["type"], event["data"]["object"]
    failures: list[str] = []

    if t == "checkout.session.completed":
        customer = Customer.objects.select_for_update().get(pk=int(obj["client_reference_id"]))
        customer.stripe_customer_id = obj["customer"]
        if customer.instance_status == Customer.InstanceStatus.NONE:
            customer.instance_status = Customer.InstanceStatus.AWAITING
        customer.save(update_fields=["stripe_customer_id", "instance_status"])
        meta = obj.get("metadata") or {}
        instance = Instance.objects.filter(pk=meta.get("instance_id") or 0).first()
        aff = Affiliate.objects.filter(code=meta.get("ref_code") or "", active=True).first()
        # With a trial configured the subscription Stripe just created is
        # `trialing`, not `active`, and the session payload does not carry the
        # subscription's status. Seed the status from config; the
        # customer.subscription.created/updated events that follow within
        # seconds carry the authoritative status and correct this if it is
        # wrong. Both values are entitled, so provisioning proceeds either way.
        seeded = (Subscription.Status.TRIALING
                  if int(getattr(settings, "STRIPE_TRIAL_DAYS", 0) or 0) > 0
                  else Subscription.Status.ACTIVE)
        sub = _entitle(customer, seeded,
                       sub_id=obj.get("subscription") or "", affiliate=aff)
        if instance:
            instance.subscription = sub
            instance.status = Instance.Status.PROVISIONING
            instance.save(update_fields=["subscription", "status"])
            # The provisioning worker (operator side, holds fleet credentials)
            # polls for PROVISIONING instances and runs provision-instance.sh.
            log.info("PROVISION-REQUEST instance=%s subdomain=%s customer=%s",
                     instance.pk, instance.subdomain, customer.pk)
        _mail_after_commit(customer, "welcome",
                           {"trial_days": int(getattr(settings, "STRIPE_TRIAL_DAYS", 0) or 0)})

    elif t == "invoice.paid":
        customer = Customer.objects.filter(stripe_customer_id=obj["customer"]).select_for_update().first()
        if customer:
            # Stripe moved invoice.subscription to
            # invoice.parent.subscription_details.subscription. Reading the old
            # field returned None, so _entitle could not match the real
            # subscription and created an orphan row instead.
            sub_id = obj.get("subscription") or (
                ((obj.get("parent") or {}).get("subscription_details") or {}).get("subscription") or "")
            sub = _entitle(customer, Subscription.Status.ACTIVE,
                           sub_id=sub_id,
                           period_end=(obj.get("lines", {}).get("data") or [{}])[0].get("period", {}).get("end"))
            failures += stripe_svc.pay_affiliate_splits(obj, sub)

    elif t == "invoice.payment_failed":
        customer = Customer.objects.filter(stripe_customer_id=obj["customer"]).select_for_update().first()
        if customer:
            _entitle(customer, Subscription.Status.PAST_DUE)
            _mail_after_commit(customer, "payment_failed")

    elif t in ("customer.subscription.deleted", "customer.subscription.paused"):
        customer = Customer.objects.filter(stripe_customer_id=obj["customer"]).select_for_update().first()
        if customer:
            _entitle(customer, Subscription.Status.CANCELED)
            _mail_after_commit(customer, "suspended")

    elif t in ("customer.subscription.created", "customer.subscription.updated"):
        customer = Customer.objects.filter(stripe_customer_id=obj["customer"]).select_for_update().first()
        if customer:
            status = _SUB_STATUS.get(obj["status"])
            if status:
                # trial_end is passed even when absent (None) so the field is
                # cleared on the trialing -> active transition. `current_period_end`
                # moved into the subscription's items in recent API versions;
                # read both so the renewal date does not silently go blank.
                items = ((obj.get("items") or {}).get("data") or [{}])[0]
                _entitle(customer, status,
                         period_end=obj.get("current_period_end") or items.get("current_period_end"),
                         sub_id=obj.get("id", ""),
                         # .get(key, _UNSET): absent means "unknown, leave it";
                         # present-and-null means "the trial is over, clear it".
                         trial_end=obj.get("trial_end", _UNSET))
            else:
                log.warning("unmapped Stripe subscription status %r on %s", obj.get("status"), t)

    elif t == "charge.refunded":
        # The Charge object carries the CUMULATIVE `amount_refunded`, which is
        # exactly what the target-based clawback wants — a second partial refund
        # arrives with the running total, not just its own increment.
        failures += stripe_svc.reverse_affiliate_splits(
            charge_id=obj.get("id") or "",
            refunded_cents=int(obj.get("amount_refunded") or 0),
            reason="refund", event_id=event["id"],
        )

    elif t in ("charge.dispute.created", "charge.dispute.funds_withdrawn"):
        # A dispute pulls the FULL disputed amount out of the platform balance
        # the moment it is opened, so the commission is already underwater —
        # claw back at dispute time rather than waiting for the outcome. If the
        # dispute is later won, `charge.dispute.funds_reinstated` arrives and
        # the affiliate is re-paid by hand: over-reversing and refunding an
        # affiliate is recoverable, while under-reversing loses the money to a
        # party with no obligation to return it.
        disputed = int(obj.get("amount") or 0)
        charge_id = obj.get("charge") or ""
        failures += stripe_svc.reverse_affiliate_splits(
            charge_id=charge_id, refunded_cents=disputed,
            reason="dispute", event_id=event["id"],
        )
        customer = Customer.objects.filter(stripe_customer_id=obj.get("customer") or "").select_for_update().first()
        log.warning("DISPUTE %s on charge %s (%sc) — customer=%s",
                    t, charge_id, disputed, customer.pk if customer else "unknown")

    elif t == "charge.dispute.funds_reinstated":
        # Deliberately NOT automatic. Re-sending money to an affiliate is a new
        # payment, not the undo of a reversal, and it deserves a human deciding
        # that the win is final. Loud log + audit trail; the operator re-pays.
        log.warning("DISPUTE WON — funds reinstated on charge %s. Affiliate commission "
                    "was clawed back when the dispute opened and is NOT re-paid "
                    "automatically; review SplitReversal rows for this charge.",
                    obj.get("charge") or "")

    elif t == "customer.subscription.trial_will_end":
        # Fires ~3 days before the first charge. Entitlement does not change —
        # this is the hook the trial-ending email hangs off (P1 item: no
        # transactional email exists yet, so for now it is an auditable log
        # line plus the stored date, not a silent no-op).
        customer = Customer.objects.filter(stripe_customer_id=obj["customer"]).select_for_update().first()
        if customer:
            sub = Subscription.objects.filter(stripe_subscription_id=obj.get("id", "")).first()
            if sub:
                sub.trial_end = _ts(obj.get("trial_end"))
                sub.save(update_fields=["trial_end"])
            log.info("TRIAL-ENDING customer=%s subscription=%s trial_end=%s",
                     customer.pk, obj.get("id", ""), _ts(obj.get("trial_end")))
            te = _ts(obj.get("trial_end"))
            _mail_after_commit(customer, "trial_ending",
                               {"trial_end": te.strftime("%B %-d, %Y") if te else ""})

    return failures


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


def _customer_agreement_state(customer):
    """(active customer template, has the customer signed it) — the pair every
    checkout surface needs. A NEW template version un-signs everybody by
    design: the gate asks for a signature on the text that is active *now*."""
    template = ContractTemplate.active_for(ContractTemplate.Kind.CUSTOMER)
    signed = bool(template and CustomerContract.objects.filter(
        customer=customer, template=template).exists())
    return template, signed


@login_required
def customer_agreement(request):
    """Click-wrap the customer agreement. GET shows the text, POST records the
    signature and continues to the instance form.

    Deliberately its own URL rather than a checkbox bolted onto the subdomain
    form: the evidence we need if a charge is disputed is that the person was
    shown this exact text and affirmatively accepted it."""
    customer, _ = Customer.objects.get_or_create(user=request.user)
    template, signed = _customer_agreement_state(customer)
    ctx = {"template": template, "signed": signed}

    if request.method != "POST":
        return render(request, "core/customer_agreement.html", ctx)

    signed_name = (request.POST.get("signed_name") or "").strip()
    if not template:
        return render(request, "core/customer_agreement.html",
                      dict(ctx, error="No customer agreement is published yet — "
                                      "please contact support."), status=409)
    if not signed_name or request.POST.get("agree") != "on":
        return render(request, "core/customer_agreement.html",
                      dict(ctx, error="Type your full legal name and tick the box to accept.",
                           name_value=signed_name), status=400)
    signer_ip, forwarded_for = _signer_origin(request)
    CustomerContract.objects.get_or_create(
        customer=customer, template=template,
        defaults={
            # Hash the exact bytes shown, not the template row: this is the
            # evidence, and it must survive the row being edited or deleted.
            "body_sha256": hashlib.sha256(template.body_md.encode()).hexdigest(),
            "signed_name": signed_name,
            "signer_email": request.user.email,
            "signer_ip": signer_ip,
            "signer_forwarded_for": forwarded_for,
            "user_agent": request.META.get("HTTP_USER_AGENT", "")[:300],
        },
    )
    log.info("CUSTOMER-AGREEMENT signed customer=%s version=%s", customer.pk, template.version)
    return redirect("new_instance")


@login_required
def new_instance(request):
    customer, _ = Customer.objects.get_or_create(user=request.user)
    # ── the gate ───────────────────────────────────────────────────────────
    # No signature, no Checkout session. Enforced on BOTH methods: the GET so
    # nobody sees the form first, and the POST so a hand-crafted request (or a
    # tab left open across a new agreement version) cannot skip it.
    template, signed = _customer_agreement_state(customer)
    if not signed:
        if not template:
            # Fail CLOSED. No published agreement means we cannot prove what
            # the customer accepted, and taking money in that state is the
            # exposure this whole feature exists to close.
            log.error("Checkout blocked: no active customer ContractTemplate is published")
            return render(request, "core/customer_agreement.html",
                          {"template": None,
                           "error": "No customer agreement is published yet — "
                                    "please contact support."}, status=409)
        return redirect("customer_agreement")

    if request.method != "POST":
        return render(request, "core/new_instance.html",
                      {"domain": INSTANCE_DOMAIN, "trial_days": settings.STRIPE_TRIAL_DAYS})
    name = (request.POST.get("subdomain") or "").strip().lower()
    err = _subdomain_error(name)
    if err:
        return render(request, "core/new_instance.html",
                      {"domain": INSTANCE_DOMAIN, "error": err, "value": name,
                       "trial_days": settings.STRIPE_TRIAL_DAYS}, status=400)
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
        instance=instance, ref_code=ref,
    )
    return redirect(session.url, permanent=False)


# ── self-serve affiliate signup (digital signature at the same moment) ─────
AFF_CODE_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])$")
RESERVED_CODES = {"weown", "admin", "billing", "support", "chat", "app", "www", "api", "test"}


def _code_error(code: str) -> str:
    if not code:
        return "Choose a referral code."
    if not AFF_CODE_RE.match(code):
        return ("Use 3–32 characters: lowercase letters, numbers and hyphens, "
                "starting and ending with a letter or number.")
    if code in RESERVED_CODES:
        return "That code is reserved — please choose another."
    if Affiliate.objects.filter(code=code).exists():
        return "That code is already taken."
    return ""


@login_required
def check_affiliate_code(request):
    code = (request.GET.get("code") or "").strip().lower()
    err = _code_error(code)
    return JsonResponse({"available": not err, "error": err})


@login_required
def affiliate_join(request):
    """Anyone signed in can become an affiliate: pick a code, read the current
    agreement, sign it. The signature IS the activation — no operator step.
    If they arrived through someone's referral link, that affiliate becomes
    their tier-2 sponsor, which is how the two-tier tree grows on its own."""
    if Affiliate.objects.filter(user=request.user).exists():
        return redirect("affiliate_home")
    template = ContractTemplate.active_for(ContractTemplate.Kind.AFFILIATE)
    sponsor_code = (request.session.get("ref_code") or request.GET.get("ref") or "").strip().lower()
    sponsor = Affiliate.objects.filter(code=sponsor_code, active=True).first() if sponsor_code else None
    ctx = {"template": template, "sponsor": sponsor}

    if request.method != "POST":
        return render(request, "core/affiliate_join.html", ctx)

    code = (request.POST.get("code") or "").strip().lower()
    signed_name = (request.POST.get("signed_name") or "").strip()
    err = _code_error(code)
    if not template:
        err = "No affiliate agreement is published yet — please try again later."
    elif not err and not signed_name:
        err = "Type your full legal name to sign."
    elif not err and request.POST.get("agree") != "on":
        err = "You must accept the agreement to join."
    if err:
        return render(request, "core/affiliate_join.html",
                      dict(ctx, error=err, value=code, name_value=signed_name), status=400)

    signer_ip, forwarded_for = _signer_origin(request)
    with transaction.atomic():
        aff = Affiliate.objects.create(
            user=request.user, code=code, parent=sponsor, active=True,
        )
        AffiliateContract.objects.create(
            affiliate=aff, template=template,
            body_sha256=hashlib.sha256(template.body_md.encode()).hexdigest(),
            signed_name=signed_name,
            signer_email=request.user.email,
            signer_ip=signer_ip,
            signer_forwarded_for=forwarded_for,
            user_agent=request.META.get("HTTP_USER_AGENT", "")[:300],
        )
    log.info("AFFILIATE-JOIN code=%s user=%s sponsor=%s", aff.code, request.user.email,
             sponsor.code if sponsor else "-")
    return redirect("affiliate_home")


@login_required
@require_POST
def connect_payouts(request):
    """Self-serve payout connection: the affiliate presses a button and lands in
    Stripe's hosted onboarding. Replaces 'WeOwn will send your onboarding link',
    which was a dead end — links expire in minutes so they cannot be emailed
    ahead of time anyway.

    POST-only with CSRF: this creates a Stripe Connect account on first use, and
    a state-changing GET is triggerable by a prefetch, a crawler, or a crafted
    link on another site.
    """
    aff = Affiliate.objects.filter(user=request.user).first()
    if not aff:
        return redirect("affiliate_home")
    base = f"https://{settings.ALLOWED_HOSTS[0]}"
    try:
        url = stripe_svc.connect_onboarding_url(aff, return_url=f"{base}/affiliate/")
    except Exception:  # noqa: BLE001
        log.exception("Connect onboarding failed for %s", aff.code)
        # Recompute the page's state the same way affiliate_home does — do not
        # assert facts (like "signed") the request has not established.
        template = ContractTemplate.active_for(ContractTemplate.Kind.AFFILIATE)
        signed = bool(template and AffiliateContract.objects.filter(
            affiliate=aff, template=template).exists())
        return render(request, "core/affiliate.html",
                      {"affiliate": aff, "template": template, "signed": signed,
                       "connect": stripe_svc.connect_account_status(aff),
                       "error": "Could not reach Stripe just now — please try again in a moment."},
                      status=502)
    return redirect(url, permanent=False)
