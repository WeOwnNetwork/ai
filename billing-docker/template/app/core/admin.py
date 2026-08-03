from django.contrib import admin

from .models import (
    Affiliate, AffiliateContract, ContractTemplate, Customer, SplitConfig,
    SplitPayout, Subscription, WebhookEvent,
)


@admin.register(Customer)
class CustomerAdmin(admin.ModelAdmin):
    list_display = ("user", "stripe_customer_id", "referred_by", "instance_status", "instance_slug", "created_at")
    list_editable = ("instance_status",)
    search_fields = ("user__username", "user__email", "stripe_customer_id")
    list_select_related = ("user", "referred_by")


@admin.register(Subscription)
class SubscriptionAdmin(admin.ModelAdmin):
    list_display = ("customer", "status", "current_period_end", "updated_at")
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
    list_display = ("version", "active", "created_at")

    def has_change_permission(self, request, obj=None):
        # immutable once signed — new text = new version row
        if obj and obj.affiliatecontract_set.exists():
            return False
        return super().has_change_permission(request, obj)


@admin.register(AffiliateContract)
class AffiliateContractAdmin(admin.ModelAdmin):
    list_display = ("affiliate", "template", "signed_name", "signer_email", "signer_ip", "signed_at")
    readonly_fields = [f.name for f in AffiliateContract._meta.fields]

    def has_add_permission(self, request):
        return False  # signatures only via the click-wrap flow

    def has_delete_permission(self, request, obj=None):
        return False


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


@admin.register(WebhookEvent)
class WebhookEventAdmin(admin.ModelAdmin):
    list_display = ("stripe_event_id", "event_type", "processed", "received_at")
    list_filter = ("processed", "event_type")
    readonly_fields = [f.name for f in WebhookEvent._meta.fields]
