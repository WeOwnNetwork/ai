"""Core billing models — deliberately thin.

One product, subscription per customer, 2-tier affiliate splits, click-wrap
affiliate contracts, and a raw webhook-event ledger for idempotency + audit.
"""
import os

from django.conf import settings
from django.core.validators import RegexValidator, URLValidator
from django.db import models

# Parent zone every instance subdomain hangs off (config, not secret).
INSTANCE_DOMAIN = os.environ.get("INSTANCE_DOMAIN", "weown.dev")


class Customer(models.Model):
    """A paying WeOwn customer. user maps 1:1 to the Keycloak identity
    (same login that runs their instance)."""

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    kc_user_id = models.CharField(max_length=64, blank=True, help_text="Keycloak user UUID (sub claim)")
    stripe_customer_id = models.CharField(max_length=64, blank=True, db_index=True)
    referred_by = models.ForeignKey(
        "Affiliate", null=True, blank=True, on_delete=models.SET_NULL, related_name="referrals",
        help_text="Affiliate whose link/code this customer signed up through",
    )
    instance_slug = models.CharField(
        max_length=64, blank=True,
        help_text="weown-fleet tenant slug once provisioned (empty until then)",
    )

    class InstanceStatus(models.TextChoices):
        NONE = "none", "No instance"
        AWAITING = "awaiting_provision", "Being set up"
        PROVISIONING = "provisioning", "Provisioning"
        ACTIVE = "active", "Active"
        PAUSED = "paused", "Paused"
        RETIRED = "retired", "Retired"

    instance_status = models.CharField(
        max_length=20, choices=InstanceStatus.choices, default=InstanceStatus.NONE,
        help_text="Lifecycle of the customer's private instance (operator-driven until provisioning automation lands)",
    )
    instance_url = models.URLField(blank=True, help_text="Customer's instance URL once active")
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.user.get_username()


class Subscription(models.Model):
    class Status(models.TextChoices):
        ACTIVE = "active"
        TRIALING = "trialing"
        PAST_DUE = "past_due"
        CANCELED = "canceled"
        INCOMPLETE = "incomplete"

    customer = models.ForeignKey(Customer, on_delete=models.PROTECT, related_name="subscriptions")
    # Affiliate attribution is captured AT SUBSCRIPTION and never inferred later
    # (Nik 2026-08-03): splitting money that was already collected under different
    # attribution is bad practice — back-dated concessions are a manual credit.
    affiliate = models.ForeignKey(
        "Affiliate", null=True, blank=True, on_delete=models.SET_NULL, related_name="attributed_subscriptions",
        help_text="Referring affiliate at the moment this subscription was created. Customers cannot change this; admins can.",
    )
    stripe_subscription_id = models.CharField(max_length=64, blank=True, db_index=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.INCOMPLETE)
    current_period_end = models.DateTimeField(null=True, blank=True)
    trial_end = models.DateTimeField(
        null=True, blank=True,
        help_text="When the free trial converts to a paid charge (empty if there was no trial)",
    )
    updated_at = models.DateTimeField(auto_now=True)

    @property
    def entitled(self) -> bool:
        """The single flag every surface (dashboard, embed, KC attribute)
        derives from. past_due keeps access until the period actually ends —
        Stripe retries first; we suspend on the transition to canceled/unpaid.

        TRIALING is entitled: the whole point of the 14-day trial is a working
        instance before the first charge. Entitlement and revenue are separate
        questions — the split engine keys off money collected (a $0 trial
        invoice pays no commission), never off this flag."""
        return self.status in (self.Status.ACTIVE, self.Status.TRIALING)

    @property
    def in_trial(self) -> bool:
        return self.status == self.Status.TRIALING

    def __str__(self):
        return f"{self.customer} [{self.status}]"


# Brand colour is interpolated into a CSS custom property, so it is validated
# at the model AND re-validated in the context processor. Model validators do
# not run on a bare .save(), and the template's HTML autoescaping does NOT
# protect a CSS context — so the render path must never trust the stored value.
HEX_COLOR = RegexValidator(
    r"^#[0-9A-Fa-f]{6}$", "Use a 6-digit hex colour such as #2563eb.",
)

#: What an unbranded (direct / WeOwn-sold) visitor sees.
WEOWN_BRAND = {
    "name": "WeOwn",
    "logo_url": "",
    "primary_color": "#2563eb",
    "support_email": "",
    "is_affiliate": False,
}


class Affiliate(models.Model):
    """2-tier: an affiliate may have a parent; parent earns the tier-2 cut on
    the child's referrals. Splits live on SplitConfig (global defaults) with
    optional per-affiliate overrides here."""

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    code = models.SlugField(max_length=32, unique=True, help_text="referral code used in signup links")
    parent = models.ForeignKey(
        "self", null=True, blank=True, on_delete=models.SET_NULL, related_name="children",
        help_text="Tier-2 beneficiary of this affiliate's referrals",
    )
    stripe_connect_account_id = models.CharField(
        max_length=64, blank=True,
        help_text="Stripe Connect Express account for payouts (empty until onboarded)",
    )
    tier1_pct_override = models.DecimalField(
        max_digits=5, decimal_places=2, null=True, blank=True,
        help_text="Override of the global tier-1 %, leave empty for default",
    )
    tier2_pct_override = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    active = models.BooleanField(default=False, help_text="Only set after their contract is signed")
    created_at = models.DateTimeField(auto_now_add=True)

    # ── White-label branding (WO-Disc-1040 / A627) ────────────────────────────
    # The billing funnel is the ONLY WeOwn-controlled surface an end customer
    # sees before paying, and affiliates sell under their own brand — so these
    # drive the header, the accent colour and the support contact on every
    # pre-purchase page. All optional: empty falls back to WEOWN_BRAND.
    display_name = models.CharField(
        max_length=80, blank=True,
        help_text="Brand shown to customers in the signup funnel (e.g. 'Vulcarian'). Empty = WeOwn.",
    )
    logo_url = models.URLField(
        blank=True, validators=[URLValidator(schemes=["https"])],
        help_text="HTTPS URL of the affiliate's logo, shown in the billing header. HTTPS only — "
                  "an http:// logo would make the payment page mixed-content.",
    )
    primary_color = models.CharField(
        max_length=7, blank=True, validators=[HEX_COLOR],
        help_text="Brand accent as #RRGGBB, used for buttons and links.",
    )
    support_email = models.EmailField(
        blank=True,
        help_text="Where this affiliate's customers should be told to get help. Empty = WeOwn support.",
    )

    @property
    def brand(self) -> dict:
        """Branding for this affiliate, WeOwn defaults filling any blank.

        Read through `core.context_processors.branding`, never directly in a
        template — that is where the CSS-context re-validation lives.
        """
        return {
            "name": self.display_name or WEOWN_BRAND["name"],
            "logo_url": self.logo_url or WEOWN_BRAND["logo_url"],
            "primary_color": self.primary_color or WEOWN_BRAND["primary_color"],
            "support_email": self.support_email or WEOWN_BRAND["support_email"],
            "is_affiliate": True,
        }

    def __str__(self):
        return self.code


class SplitConfig(models.Model):
    """Singleton-ish global split defaults, editable in admin. History kept by
    adding rows (latest effective_from wins) — never edit old rows (G2).

    Splits are percentages of PROFIT per invoice:
    profit = amount_paid − actual Stripe fee (balance transaction) − monthly_cogs_cents."""

    tier1_pct = models.DecimalField(max_digits=5, decimal_places=2, default=20)
    tier2_pct = models.DecimalField(max_digits=5, decimal_places=2, default=5)
    monthly_cogs_cents = models.PositiveIntegerField(
        default=0,
        help_text="Cost of goods sold per instance-month, in CENTS (droplet, LLM keys, support overhead) — subtracted with Stripe fees before splits",
    )
    effective_from = models.DateTimeField(auto_now_add=True)
    note = models.CharField(max_length=200, blank=True)

    class Meta:
        get_latest_by = "effective_from"
        constraints = [
            models.CheckConstraint(check=models.Q(tier1_pct__gte=0, tier1_pct__lte=100), name="tier1_pct_0_100"),
            models.CheckConstraint(check=models.Q(tier2_pct__gte=0, tier2_pct__lte=100), name="tier2_pct_0_100"),
        ]

    @classmethod
    def current(cls):
        return cls.objects.latest()

    def __str__(self):
        return f"T1 {self.tier1_pct}% / T2 {self.tier2_pct}% (from {self.effective_from:%Y-%m-%d})"


class ContractTemplate(models.Model):
    """Versioned agreement text — affiliate OR customer. Immutable once any
    signature references it (enforced in admin).

    One model, two kinds, because the mechanics are identical: publish text,
    someone click-wraps it, the signature pins the exact bytes by hash. The
    text is a DB row precisely so the business can replace a placeholder with
    legal-approved wording without a deploy."""

    class Kind(models.TextChoices):
        AFFILIATE = "affiliate", "Affiliate agreement"
        CUSTOMER = "customer", "Customer agreement"

    kind = models.CharField(
        max_length=16, choices=Kind.choices, default=Kind.AFFILIATE, db_index=True,
        help_text="Who signs this — affiliates at join, customers at checkout",
    )
    version = models.CharField(max_length=20)
    body_md = models.TextField(help_text="Full agreement text (markdown)")
    active = models.BooleanField(default=False, help_text="The one shown for new signatures")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            # Versions are unique WITHIN a kind — an affiliate v0.1 and a
            # customer v0.1 are different documents and must coexist.
            models.UniqueConstraint(fields=["kind", "version"], name="one_version_per_kind"),
            # Exactly one active template PER KIND. The pre-2026-08-11 form of
            # this constraint was global, so publishing a customer agreement
            # would have deactivated the affiliate one.
            models.UniqueConstraint(
                fields=["kind"], condition=models.Q(active=True),
                name="one_active_template_per_kind",
            ),
        ]

    @classmethod
    def active_for(cls, kind: str):
        return cls.objects.filter(kind=kind, active=True).first()

    def __str__(self):
        return f"{self.get_kind_display()} v{self.version}"


class AffiliateContract(models.Model):
    """Thin click-wrap signature record: who accepted which exact text, when,
    from where. body_sha256 pins the text independent of the template row."""

    affiliate = models.ForeignKey(Affiliate, on_delete=models.PROTECT, related_name="contracts")
    template = models.ForeignKey(ContractTemplate, on_delete=models.PROTECT)
    body_sha256 = models.CharField(max_length=64)
    signed_name = models.CharField(max_length=120, help_text="Name typed by the signer")
    signer_email = models.EmailField()
    signer_ip = models.GenericIPAddressField(null=True, blank=True)
    signer_forwarded_for = models.CharField(
        max_length=300, blank=True,
        help_text="Raw X-Forwarded-For chain as received. signer_ip is the rightmost "
                  "hop (the one our own proxy appended, and the only one a client "
                  "cannot forge); this keeps the whole chain for forensics.",
    )
    user_agent = models.CharField(max_length=300, blank=True)
    signed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["affiliate", "template"], name="one_signature_per_version"),
        ]

    def __str__(self):
        return f"{self.affiliate} signed v{self.template.version} at {self.signed_at:%Y-%m-%d %H:%M}"


class CustomerContract(models.Model):
    """Click-wrap signature by a CUSTOMER, taken before Stripe Checkout.

    Same evidentiary shape as AffiliateContract — who accepted which exact
    text, when, from where — because the two have to stand up the same way if
    a charge is ever disputed. `body_sha256` pins the bytes independently of
    the template row, so later edits (or a deleted template) cannot silently
    change what someone is recorded as having agreed to.

    Unlike the affiliate side, this is a HARD GATE: no signature, no checkout
    session (see views.new_instance).

    ⚠️ **Can you trust `signer_ip`?** Only while Caddy is the OUTERMOST proxy.
    It is the rightmost `X-Forwarded-For` hop — the one our own proxy appended,
    which a client cannot forge (the leftmost hop, which they can, is what this
    used to record). Put a CDN/WAF in front of the billing host — proxying
    through Cloudflare is a one-click DNS toggle and WeOwn is mid-migration onto
    Cloudflare (D434) — and this field silently becomes the CDN's edge address
    on every row, with nothing raising to say so. Check `signer_forwarded_for`:
    if the same IP appears as the last hop across unrelated signers, the
    topology changed and those rows attest to nothing. See views._signer_origin
    for what has to change first."""

    customer = models.ForeignKey(Customer, on_delete=models.PROTECT, related_name="contracts")
    template = models.ForeignKey(ContractTemplate, on_delete=models.PROTECT)
    body_sha256 = models.CharField(max_length=64)
    signed_name = models.CharField(max_length=120, help_text="Name typed by the signer")
    signer_email = models.EmailField()
    signer_ip = models.GenericIPAddressField(null=True, blank=True)
    signer_forwarded_for = models.CharField(
        max_length=300, blank=True,
        help_text="Raw X-Forwarded-For chain as received. signer_ip is the rightmost "
                  "hop (the one our own proxy appended, and the only one a client "
                  "cannot forge); this keeps the whole chain for forensics.",
    )
    user_agent = models.CharField(max_length=300, blank=True)
    signed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["customer", "template"], name="one_customer_signature_per_version",
            ),
        ]

    def __str__(self):
        return f"{self.customer} signed {self.template} at {self.signed_at:%Y-%m-%d %H:%M}"


class WebhookEvent(models.Model):
    """Raw Stripe event ledger — idempotency (unique event id) + audit."""

    stripe_event_id = models.CharField(max_length=64, unique=True)
    event_type = models.CharField(max_length=64, db_index=True)
    payload = models.JSONField()
    processed = models.BooleanField(default=False)
    error = models.TextField(blank=True)
    received_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.event_type} {self.stripe_event_id}"


class SplitPayout(models.Model):
    """Audit row for every split computation — written even when the transfer
    is skipped, so the money math is always inspectable in admin."""

    class Status(models.TextChoices):
        PAID = "paid"
        SKIPPED_NO_ACCOUNT = "skipped_no_account", "Skipped — affiliate has no Connect account"
        SKIPPED_NO_PROFIT = "skipped_no_profit", "Skipped — no profit on this invoice"
        FAILED = "failed", "Transfer failed — see error"

    invoice_id = models.CharField(max_length=64, db_index=True)
    charge_id = models.CharField(
        max_length=64, blank=True, db_index=True,
        help_text="The charge that funded this payout. Recorded so a refund or "
                  "dispute — which arrives as a CHARGE event — can find the legs "
                  "it has to claw back without re-deriving the invoice.",
    )
    affiliate = models.ForeignKey(Affiliate, on_delete=models.PROTECT, related_name="payouts")
    tier = models.PositiveSmallIntegerField()
    gross_cents = models.PositiveIntegerField()
    stripe_fee_cents = models.PositiveIntegerField()
    cogs_cents = models.PositiveIntegerField()
    profit_cents = models.IntegerField()
    pct = models.DecimalField(max_digits=5, decimal_places=2)
    cut_cents = models.IntegerField()
    status = models.CharField(max_length=24, choices=Status.choices)
    stripe_transfer_id = models.CharField(max_length=64, blank=True)
    error = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["invoice_id", "affiliate", "tier"], name="one_payout_per_invoice_leg"),
        ]

    @property
    def cut_dollars(self):
        return f"{self.cut_cents / 100:,.2f}"

    @property
    def profit_dollars(self):
        return f"{self.profit_cents / 100:,.2f}"

    @property
    def reversed_cents(self) -> int:
        """How much of this leg has already been clawed back."""
        return sum(r.amount_cents for r in self.reversals.all()
                   if r.status == SplitReversal.Status.REVERSED)

    def __str__(self):
        return f"{self.invoice_id} T{self.tier} {self.affiliate} {self.cut_cents}c [{self.status}]"


class SplitReversal(models.Model):
    """One clawback attempt against one paid split leg.

    A refund does not just cost WeOwn its margin — the affiliate's commission
    went out the door too, and Stripe does not pull it back on its own. Each
    row is an attempt to reverse one leg by one amount, recorded whether it
    succeeded, was skipped, or failed, so the position is always inspectable.

    Keyed by the STRIPE EVENT, not the charge: a charge can be refunded several
    times, and each event must be able to reverse its own increment exactly
    once. Amounts are computed against a cumulative TARGET (see
    stripe_svc.reverse_affiliate_splits) rather than per-event deltas, so a
    duplicate or out-of-order webhook cannot over-reverse."""

    class Status(models.TextChoices):
        REVERSED = "reversed", "Reversed — funds clawed back"
        SKIPPED_NOTHING_OWED = "skipped_nothing_owed", "Skipped — already fully reversed"
        SKIPPED_NOT_PAID = "skipped_not_paid", "Skipped — leg never paid out"
        FAILED = "failed", "Reversal failed — see error"

    payout = models.ForeignKey(SplitPayout, on_delete=models.PROTECT, related_name="reversals")
    stripe_event_id = models.CharField(
        max_length=64, db_index=True,
        help_text="The refund/dispute event that triggered this clawback",
    )
    reason = models.CharField(max_length=32, help_text="refund | dispute")
    amount_cents = models.IntegerField(help_text="Clawed back by THIS reversal")
    charge_refunded_cents = models.IntegerField(
        help_text="Cumulative amount refunded on the charge when this was computed",
    )
    status = models.CharField(max_length=24, choices=Status.choices)
    stripe_reversal_id = models.CharField(max_length=64, blank=True)
    error = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            # One attempt per (event, leg). A FAILED row is deliberately allowed
            # to be retried in place, the same way SplitPayout treats failures.
            models.UniqueConstraint(
                fields=["stripe_event_id", "payout"], name="one_reversal_per_event_leg",
            ),
        ]

    @property
    def amount_dollars(self):
        return f"{self.amount_cents / 100:,.2f}"

    def __str__(self):
        return f"reverse {self.amount_cents}c of {self.payout} [{self.status}]"


class Instance(models.Model):
    """One private AI instance. A customer may run several, each on its own
    subdomain with its own subscription and its own affiliate attribution."""

    class Status(models.TextChoices):
        REQUESTED = "requested", "Requested (awaiting payment)"
        PROVISIONING = "provisioning", "Provisioning"
        ACTIVE = "active", "Active"
        PAUSED = "paused", "Paused (billing)"
        DESTROYING = "destroying", "Destroying"
        DESTROYED = "destroyed", "Destroyed"

    customer = models.ForeignKey(Customer, on_delete=models.PROTECT, related_name="instances")
    subdomain = models.SlugField(
        max_length=40, unique=True,
        help_text="Customer-chosen name; becomes <subdomain>.weown.dev",
    )
    display_name = models.CharField(max_length=80, blank=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.REQUESTED)
    subscription = models.OneToOneField(
        "Subscription", null=True, blank=True, on_delete=models.SET_NULL, related_name="instance",
    )
    provision_log = models.TextField(blank=True, help_text="Latest provisioning output/status detail")
    created_at = models.DateTimeField(auto_now_add=True)
    provisioned_at = models.DateTimeField(null=True, blank=True)
    destroyed_at = models.DateTimeField(null=True, blank=True)

    # Names we never hand out (fleet + marketing surfaces).
    RESERVED = {
        "www", "app", "api", "admin", "billing", "chat", "sso", "git", "mail",
        "smtp", "ns1", "ns2", "matomo", "fathom", "status", "docs", "support",
        "weown", "test", "staging", "prod", "dashboard", "portal",
    }

    class Meta:
        ordering = ["-created_at"]

    @property
    def url(self) -> str:
        return f"https://{self.subdomain}.{INSTANCE_DOMAIN}"

    @property
    def entitled(self) -> bool:
        return bool(self.subscription and self.subscription.entitled)

    def __str__(self):
        return f"{self.subdomain} ({self.status})"
