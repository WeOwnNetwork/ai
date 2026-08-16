from django.contrib import admin

from .models import (
    Affiliate, AffiliateContract, ContractTemplate, Customer, CustomerContract,
    Instance, SplitConfig, SplitPayout, SplitReversal, Subscription, WebhookEvent,
)


@admin.register(Customer)
class CustomerAdmin(admin.ModelAdmin):
    list_display = ("user", "stripe_customer_id", "referred_by", "instance_status", "instance_slug", "created_at")
    list_editable = ("instance_status",)
    search_fields = ("user__username", "user__email", "stripe_customer_id")
    list_select_related = ("user", "referred_by")


@admin.register(Instance)
class InstanceAdmin(admin.ModelAdmin):
    list_display = ("subdomain", "customer", "status", "subscription", "created_at", "provisioned_at")
    list_filter = ("status",)
    search_fields = ("subdomain", "customer__user__email")
    list_editable = ("status",)


@admin.register(Subscription)
class SubscriptionAdmin(admin.ModelAdmin):
    # affiliate is editable here ONLY — customers can never change attribution.
    list_display = ("customer", "affiliate", "status", "current_period_end", "updated_at")
    list_filter = ("status",)
    search_fields = ("customer__user__email", "stripe_subscription_id")


@admin.register(Affiliate)
class AffiliateAdmin(admin.ModelAdmin):
    list_display = ("code", "user", "parent", "active", "tier1_pct_override", "tier2_pct_override")
    list_filter = ("active",)
    search_fields = ("code", "user__email")


@admin.register(SplitConfig)
class SplitConfigAdmin(admin.ModelAdmin):
    list_display = ("tier1_pct", "tier2_pct", "monthly_cogs_cents", "effective_from", "note")

    def has_change_permission(self, request, obj=None):
        return False  # append-only (G2): change splits by adding a new row

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(ContractTemplate)
class ContractTemplateAdmin(admin.ModelAdmin):
    list_display = ("kind", "version", "active", "created_at")
    list_filter = ("kind", "active")

    # The TEXT of a signed template is immutable — editing it would rewrite what
    # someone is recorded as having agreed to. Its `active` FLAG is not: that is
    # how a new version is published.
    #
    # Blocking change outright (the pre-2026-08-11 behaviour) deadlocked exactly
    # that: only one template per kind may be active, so publishing v2 requires
    # deactivating v1 — which is a change to v1 — so after the FIRST signature no
    # new agreement version could ever be published. Freeze the fields, not the row.
    _IMMUTABLE_ONCE_SIGNED = ("kind", "version", "body_md")

    @staticmethod
    def _is_signed(obj) -> bool:
        return bool(obj and obj.pk and (
            obj.affiliatecontract_set.exists() or obj.customercontract_set.exists()))

    def get_readonly_fields(self, request, obj=None):
        base = tuple(super().get_readonly_fields(request, obj))
        return base + self._IMMUTABLE_ONCE_SIGNED if self._is_signed(obj) else base

    def save_model(self, request, obj, form, change):
        # Publishing v2 is one save, not two. Without this, ticking `active` on
        # the new version raises IntegrityError against one_active_template_per_kind
        # and the admin shows a 500 — the operator has to guess that v1 must be
        # deactivated first, in a separate edit.
        if obj.active:
            ContractTemplate.objects.filter(kind=obj.kind, active=True).exclude(
                pk=obj.pk).update(active=False)
        super().save_model(request, obj, form, change)

    def has_delete_permission(self, request, obj=None):
        # A signed template is evidence — its bytes are what the signature hash
        # attests to. PROTECT on the FK would raise anyway; refuse clearly instead.
        if self._is_signed(obj):
            return False
        return super().has_delete_permission(request, obj)


@admin.register(AffiliateContract)
class AffiliateContractAdmin(admin.ModelAdmin):
    list_display = ("affiliate", "template", "signed_name", "signer_email", "signer_ip", "signed_at")
    readonly_fields = [f.name for f in AffiliateContract._meta.fields]

    def has_add_permission(self, request):
        return False  # signatures only via the click-wrap flow

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(CustomerContract)
class CustomerContractAdmin(admin.ModelAdmin):
    list_display = ("customer", "template", "signed_name", "signer_email", "signer_ip", "signed_at")
    readonly_fields = [f.name for f in CustomerContract._meta.fields]
    list_filter = ("template",)

    def has_add_permission(self, request):
        return False  # signatures only via the click-wrap flow

    def has_delete_permission(self, request, obj=None):
        return False  # evidence: never deletable from the UI


@admin.register(SplitPayout)
class SplitPayoutAdmin(admin.ModelAdmin):
    list_display = ("invoice_id", "tier", "affiliate", "gross_cents", "stripe_fee_cents",
                    "cogs_cents", "profit_cents", "pct", "cut_cents", "status", "created_at")
    list_filter = ("status", "tier")
    readonly_fields = [f.name for f in SplitPayout._meta.fields]

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(SplitReversal)
class SplitReversalAdmin(admin.ModelAdmin):
    list_display = ("payout", "reason", "amount_dollars", "status",
                    "stripe_reversal_id", "created_at")
    list_filter = ("status", "reason")
    search_fields = ("stripe_event_id", "stripe_reversal_id", "payout__invoice_id",
                     "payout__charge_id")
    readonly_fields = [f.name for f in SplitReversal._meta.fields]

    def has_add_permission(self, request):
        return False  # reversals are created by the webhook path only

    def has_delete_permission(self, request, obj=None):
        return False  # money ledger — append only


@admin.register(WebhookEvent)
class WebhookEventAdmin(admin.ModelAdmin):
    list_display = ("stripe_event_id", "event_type", "processed", "received_at")
    list_filter = ("processed", "event_type")
    readonly_fields = [f.name for f in WebhookEvent._meta.fields]
