"""Core billing models — deliberately thin.

One product, subscription per customer, 2-tier affiliate splits, click-wrap
affiliate contracts, and a raw webhook-event ledger for idempotency + audit.
"""
from django.conf import settings
from django.db import models


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
        PAST_DUE = "past_due"
        CANCELED = "canceled"
        INCOMPLETE = "incomplete"

    customer = models.OneToOneField(Customer, on_delete=models.PROTECT)
    stripe_subscription_id = models.CharField(max_length=64, blank=True, db_index=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.INCOMPLETE)
    current_period_end = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    @property
    def entitled(self) -> bool:
        """The single flag every surface (dashboard, embed, KC attribute)
        derives from. past_due keeps access until the period actually ends —
        Stripe retries first; we suspend on the transition to canceled/unpaid."""
        return self.status == self.Status.ACTIVE

    def __str__(self):
        return f"{self.customer} [{self.status}]"


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
    """Versioned affiliate-agreement text. Immutable once any signature
    references it (enforced in admin)."""

    version = models.CharField(max_length=20, unique=True)
    body_md = models.TextField(help_text="Full agreement text (markdown)")
    active = models.BooleanField(default=False, help_text="The one shown for new signatures")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["active"], condition=models.Q(active=True), name="one_active_contract_template"),
        ]

    def __str__(self):
        return f"Affiliate Agreement v{self.version}"


class AffiliateContract(models.Model):
    """Thin click-wrap signature record: who accepted which exact text, when,
    from where. body_sha256 pins the text independent of the template row."""

    affiliate = models.ForeignKey(Affiliate, on_delete=models.PROTECT, related_name="contracts")
    template = models.ForeignKey(ContractTemplate, on_delete=models.PROTECT)
    body_sha256 = models.CharField(max_length=64)
    signed_name = models.CharField(max_length=120, help_text="Name typed by the signer")
    signer_email = models.EmailField()
    signer_ip = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.CharField(max_length=300, blank=True)
    signed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["affiliate", "template"], name="one_signature_per_version"),
        ]

    def __str__(self):
        return f"{self.affiliate} signed v{self.template.version} at {self.signed_at:%Y-%m-%d %H:%M}"


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

    invoice_id = models.CharField(max_length=64, db_index=True)
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

    def __str__(self):
        return f"{self.invoice_id} T{self.tier} {self.affiliate} {self.cut_cents}c [{self.status}]"
