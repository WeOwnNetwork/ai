"""Tests for the trial + customer-agreement gate.

Stripe is mocked throughout — these assert OUR logic (what we send Stripe, what
we do with what it sends back), never Stripe's behaviour. The
`test_zero_amount_trial_invoice_pays_no_commission` case is the one that must
never regress: it is the difference between a free trial and paying commission
on money nobody paid.
"""
import hashlib
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.test import Client, TestCase, override_settings
from django.urls import reverse

from . import stripe_svc
from .models import (
    Affiliate, ContractTemplate, Customer, CustomerContract, Instance,
    SplitConfig, SplitPayout, Subscription,
)

User = get_user_model()


def _customer(username="buyer", email="buyer@example.test"):
    user = User.objects.create_user(username=username, email=email, password="pw")
    return user, Customer.objects.get_or_create(user=user)[0]


class TrialCheckoutTests(TestCase):
    """What we ask Stripe for at Checkout."""

    def setUp(self):
        self.user, self.customer = _customer()

    @override_settings(STRIPE_TRIAL_DAYS=14)
    @mock.patch("core.stripe_svc.stripe.checkout.Session.create")
    def test_trial_days_sent_when_configured(self, create):
        stripe_svc.create_checkout_session(self.customer, "https://s/", "https://c/")
        kwargs = create.call_args.kwargs
        self.assertEqual(kwargs["subscription_data"]["trial_period_days"], 14)
        # Card up front, and a trial that cannot silently become a free forever
        # subscription if the card is missing when it ends.
        self.assertEqual(kwargs["payment_method_collection"], "always")
        self.assertEqual(
            kwargs["subscription_data"]["trial_settings"]["end_behavior"]["missing_payment_method"],
            "cancel",
        )

    @override_settings(STRIPE_TRIAL_DAYS=0)
    @mock.patch("core.stripe_svc.stripe.checkout.Session.create")
    def test_no_trial_key_when_disabled(self, create):
        stripe_svc.create_checkout_session(self.customer, "https://s/", "https://c/")
        self.assertNotIn("trial_period_days", create.call_args.kwargs["subscription_data"])

    def test_trial_days_setting_survives_a_bad_env_value(self):
        from billing import settings as billing_settings
        with mock.patch.dict("os.environ", {"STRIPE_TRIAL_DAYS": "fourteen"}):
            self.assertEqual(billing_settings._trial_days(), 0)
        with mock.patch.dict("os.environ", {"STRIPE_TRIAL_DAYS": "-5"}):
            self.assertEqual(billing_settings._trial_days(), 0)
        with mock.patch.dict("os.environ", {"STRIPE_TRIAL_DAYS": " 14 "}):
            self.assertEqual(billing_settings._trial_days(), 14)


class TrialSplitTests(TestCase):
    """Commission is owed on money collected — never on a $0 trial invoice."""

    def setUp(self):
        SplitConfig.objects.create(tier1_pct=20, tier2_pct=5, monthly_cogs_cents=0)
        aff_user = User.objects.create_user(username="aff", email="aff@example.test")
        self.affiliate = Affiliate.objects.create(
            user=aff_user, code="larry", active=True,
            stripe_connect_account_id="acct_live",
        )
        _, customer = _customer()
        self.subscription = Subscription.objects.create(
            customer=customer, affiliate=self.affiliate,
            status=Subscription.Status.TRIALING, stripe_subscription_id="sub_1",
        )

    @mock.patch("core.stripe_svc.stripe.Transfer.create")
    @mock.patch("core.stripe_svc._charge_for_invoice")
    def test_zero_amount_trial_invoice_pays_no_commission(self, charge_lookup, transfer):
        """The trial's $0 invoice is `paid` — it must move no money."""
        invoice = {"id": "in_trial", "amount_paid": 0, "currency": "usd"}
        failures = stripe_svc.pay_affiliate_splits(invoice, self.subscription)
        self.assertEqual(failures, [])
        transfer.assert_not_called()
        self.assertFalse(SplitPayout.objects.exists())
        # And it must not burn three Stripe round-trips hunting a charge that
        # cannot exist for a zero-amount invoice.
        charge_lookup.assert_not_called()

    @mock.patch("core.stripe_svc._stripe_fee_cents", return_value=2930)
    @mock.patch("core.stripe_svc._charge_for_invoice", return_value="ch_1")
    @mock.patch("core.stripe_svc.stripe.Transfer.create",
                return_value={"id": "tr_1"})
    def test_first_real_invoice_after_trial_does_pay(self, transfer, _charge, _fee):
        invoice = {"id": "in_first_real", "amount_paid": 100000, "currency": "usd"}
        failures = stripe_svc.pay_affiliate_splits(invoice, self.subscription)
        self.assertEqual(failures, [])
        row = SplitPayout.objects.get(invoice_id="in_first_real", tier=1)
        self.assertEqual(row.status, SplitPayout.Status.PAID)
        # 20% of (100000 - 2930 fee - 0 COGS)
        self.assertEqual(row.cut_cents, int(Decimal(97070) * Decimal(20) / 100))


class WebhookTrialLifecycleTests(TestCase):
    """Trial states arriving from Stripe."""

    def setUp(self):
        self.user, self.customer = _customer()
        self.customer.stripe_customer_id = "cus_1"
        self.customer.kc_user_id = "kc-uuid"
        self.customer.save()

    def _process(self, event_type, obj):
        from . import views
        with mock.patch("core.views.keycloak.set_subscription_active") as kc:
            failures = views._process_event({"type": event_type, "data": {"object": obj}})
        return failures, kc

    def test_trialing_subscription_is_entitled(self):
        _, kc = self._process("customer.subscription.created", {
            "id": "sub_1", "customer": "cus_1", "status": "trialing",
            "trial_end": 1786800000, "current_period_end": 1786800000,
        })
        sub = Subscription.objects.get(stripe_subscription_id="sub_1")
        self.assertEqual(sub.status, Subscription.Status.TRIALING)
        self.assertTrue(sub.entitled)
        self.assertIsNotNone(sub.trial_end)
        kc.assert_called_once_with("kc-uuid", True)  # instance works during the trial

    def test_trial_converts_to_active_and_clears_trial_end(self):
        self._process("customer.subscription.created", {
            "id": "sub_1", "customer": "cus_1", "status": "trialing", "trial_end": 1786800000,
        })
        self._process("customer.subscription.updated", {
            "id": "sub_1", "customer": "cus_1", "status": "active", "trial_end": None,
            "items": {"data": [{"current_period_end": 1789392000}]},
        })
        sub = Subscription.objects.get(stripe_subscription_id="sub_1")
        self.assertEqual(sub.status, Subscription.Status.ACTIVE)
        self.assertIsNone(sub.trial_end, "a converted subscription must not look like it is still trialing")
        self.assertIsNotNone(sub.current_period_end, "renewal date comes from items[] on current API versions")

    def test_trial_will_end_records_the_date_without_changing_entitlement(self):
        self._process("customer.subscription.created", {
            "id": "sub_1", "customer": "cus_1", "status": "trialing", "trial_end": 1786800000,
        })
        self._process("customer.subscription.trial_will_end", {
            "id": "sub_1", "customer": "cus_1", "trial_end": 1786800000,
        })
        sub = Subscription.objects.get(stripe_subscription_id="sub_1")
        self.assertEqual(sub.status, Subscription.Status.TRIALING)
        self.assertTrue(sub.entitled)

    def test_cancelled_subscription_is_not_entitled(self):
        _, kc = self._process("customer.subscription.updated", {
            "id": "sub_1", "customer": "cus_1", "status": "canceled",
        })
        self.assertFalse(Subscription.objects.get(stripe_subscription_id="sub_1").entitled)
        kc.assert_called_once_with("kc-uuid", False)


@override_settings(ALLOWED_HOSTS=["billing.example.test", "testserver"])
class CustomerAgreementGateTests(TestCase):
    """No signature, no Checkout session."""

    def setUp(self):
        self.client = Client()
        self.user, self.customer = _customer()
        self.client.force_login(self.user)
        # Migration 0008 seeds a placeholder customer agreement, and only one
        # per kind may be active — stand this test's text up in its place.
        ContractTemplate.objects.filter(
            kind=ContractTemplate.Kind.CUSTOMER).update(active=False)
        self.template = ContractTemplate.objects.create(
            kind=ContractTemplate.Kind.CUSTOMER, version="test-1",
            body_md="Agreement text that must be hashed exactly.", active=True,
        )

    @mock.patch("core.stripe_svc.stripe.checkout.Session.create")
    def test_unsigned_customer_is_redirected_and_no_session_is_created(self, create):
        resp = self.client.post(reverse("new_instance"),
                                {"subdomain": "acme", "display_name": "Acme"})
        self.assertRedirects(resp, reverse("customer_agreement"))
        create.assert_not_called()
        self.assertFalse(Instance.objects.exists(), "no instance may be claimed before signing")

    @mock.patch("core.stripe_svc.stripe.checkout.Session.create")
    def test_subscribe_route_is_gated_too(self, create):
        resp = self.client.get(reverse("subscribe"))
        self.assertRedirects(resp, reverse("customer_agreement"))
        create.assert_not_called()

    @mock.patch("core.stripe_svc.stripe.checkout.Session.create")
    def test_missing_template_fails_closed(self, create):
        ContractTemplate.objects.filter(kind=ContractTemplate.Kind.CUSTOMER).delete()
        resp = self.client.post(reverse("new_instance"), {"subdomain": "acme"})
        self.assertEqual(resp.status_code, 409, "must refuse to sell with no agreement to show")
        create.assert_not_called()

    def test_signature_records_the_evidence(self):
        resp = self.client.post(reverse("customer_agreement"),
                                {"signed_name": "Ada Lovelace", "agree": "on"},
                                HTTP_USER_AGENT="pytest-UA", REMOTE_ADDR="203.0.113.7")
        self.assertRedirects(resp, reverse("new_instance"), fetch_redirect_response=False)
        sig = CustomerContract.objects.get(customer=self.customer)
        self.assertEqual(sig.signed_name, "Ada Lovelace")
        self.assertEqual(sig.signer_ip, "203.0.113.7")
        self.assertEqual(sig.user_agent, "pytest-UA")
        self.assertEqual(
            sig.body_sha256,
            hashlib.sha256(self.template.body_md.encode()).hexdigest(),
            "the hash must pin the exact text shown, independent of the template row",
        )

    def test_unticked_box_is_not_a_signature(self):
        resp = self.client.post(reverse("customer_agreement"), {"signed_name": "Ada Lovelace"})
        self.assertEqual(resp.status_code, 400)
        self.assertFalse(CustomerContract.objects.exists())

    @mock.patch("core.stripe_svc.stripe.checkout.Session.create")
    def test_signed_customer_reaches_checkout(self, create):
        create.return_value = mock.Mock(url="https://checkout.stripe.test/session")
        self.client.post(reverse("customer_agreement"),
                         {"signed_name": "Ada Lovelace", "agree": "on"})
        resp = self.client.post(reverse("new_instance"),
                                {"subdomain": "acme", "display_name": "Acme"})
        self.assertEqual(resp.status_code, 302)
        self.assertEqual(resp["Location"], "https://checkout.stripe.test/session")
        create.assert_called_once()
        self.assertTrue(Instance.objects.filter(subdomain="acme").exists())

    @mock.patch("core.stripe_svc.stripe.checkout.Session.create")
    def test_a_new_agreement_version_re_gates_checkout(self, create):
        self.client.post(reverse("customer_agreement"),
                         {"signed_name": "Ada Lovelace", "agree": "on"})
        self.template.active = False
        self.template.save(update_fields=["active"])
        ContractTemplate.objects.create(
            kind=ContractTemplate.Kind.CUSTOMER, version="test-2",
            body_md="Revised terms.", active=True,
        )
        resp = self.client.post(reverse("new_instance"), {"subdomain": "acme2"})
        self.assertRedirects(resp, reverse("customer_agreement"))
        create.assert_not_called()


class ContractKindTests(TestCase):
    """Affiliate and customer agreements must not fight over `active`."""

    def test_both_kinds_can_be_active_at_once(self):
        ContractTemplate.objects.filter(active=True).update(active=False)  # clear the seeds
        ContractTemplate.objects.create(
            kind=ContractTemplate.Kind.AFFILIATE, version="1.0", body_md="aff", active=True)
        ContractTemplate.objects.create(
            kind=ContractTemplate.Kind.CUSTOMER, version="1.0", body_md="cust", active=True)
        self.assertEqual(
            ContractTemplate.active_for(ContractTemplate.Kind.AFFILIATE).body_md, "aff")
        self.assertEqual(
            ContractTemplate.active_for(ContractTemplate.Kind.CUSTOMER).body_md, "cust")

    def test_two_active_of_the_same_kind_is_rejected(self):
        from django.db.utils import IntegrityError
        ContractTemplate.objects.filter(active=True).update(active=False)
        ContractTemplate.objects.create(
            kind=ContractTemplate.Kind.CUSTOMER, version="1.0", body_md="a", active=True)
        with self.assertRaises(IntegrityError):
            ContractTemplate.objects.create(
                kind=ContractTemplate.Kind.CUSTOMER, version="1.1", body_md="b", active=True)

    def test_the_migration_seeds_a_customer_agreement(self):
        """A fresh deployment can take a signature without an admin step."""
        self.assertTrue(
            ContractTemplate.objects.filter(
                kind=ContractTemplate.Kind.CUSTOMER, active=True).exists())


class ContractTemplateAdminTests(TestCase):
    """Publishing a new agreement version must stay possible forever.

    Regression test for the deadlock found in review of ai#169: `has_change_permission`
    returned False once a template had any signature, while only one template per kind
    may be active — so after the FIRST signature, v1 could not be deactivated and v2
    could not be activated. The click-wrap flow's "a new version re-gates everyone"
    behaviour was unreachable through the admin, which is the only way the business
    publishes text. The earlier tests missed it because they build templates directly
    via the ORM, bypassing admin permissions entirely.
    """

    def setUp(self):
        from django.contrib.admin.sites import AdminSite
        from .admin import ContractTemplateAdmin
        self.admin = ContractTemplateAdmin(ContractTemplate, AdminSite())
        self.factory_user = User.objects.create_superuser(
            username="root", email="root@example.test", password="pw")
        ContractTemplate.objects.filter(active=True).update(active=False)
        self.v1 = ContractTemplate.objects.create(
            kind=ContractTemplate.Kind.CUSTOMER, version="1.0", body_md="v1 text", active=True)
        _, customer = _customer()
        CustomerContract.objects.create(
            customer=customer, template=self.v1,
            body_sha256=hashlib.sha256(b"v1 text").hexdigest(),
            signed_name="Ada Lovelace", signer_email="buyer@example.test")

    def _request(self):
        from django.test import RequestFactory
        req = RequestFactory().get("/admin/")
        req.user = self.factory_user
        return req

    def test_signed_template_stays_editable_so_a_new_version_can_be_published(self):
        req = self._request()
        self.assertTrue(
            self.admin.has_change_permission(req, self.v1),
            "a signed template must remain changeable — its `active` flag is how v2 is published",
        )

    def test_the_signed_text_itself_is_frozen(self):
        req = self._request()
        readonly = self.admin.get_readonly_fields(req, self.v1)
        for f in ("kind", "version", "body_md"):
            self.assertIn(f, readonly, f"{f} must be immutable once signed")
        unsigned = ContractTemplate.objects.create(
            kind=ContractTemplate.Kind.AFFILIATE, version="9.9", body_md="draft")
        self.assertNotIn("body_md", self.admin.get_readonly_fields(req, unsigned))

    def test_publishing_v2_through_admin_deactivates_v1_in_one_save(self):
        req = self._request()
        v2 = ContractTemplate(
            kind=ContractTemplate.Kind.CUSTOMER, version="2.0", body_md="v2 text", active=True)
        self.admin.save_model(req, v2, form=None, change=False)  # must not raise IntegrityError
        self.v1.refresh_from_db()
        self.assertFalse(self.v1.active, "publishing v2 must retire v1")
        self.assertEqual(ContractTemplate.active_for(ContractTemplate.Kind.CUSTOMER).version, "2.0")
        # ...and the affiliate agreement is untouched by a customer publish.
        self.assertIsNone(ContractTemplate.active_for(ContractTemplate.Kind.AFFILIATE))

    def test_a_signed_template_cannot_be_deleted(self):
        self.assertFalse(self.admin.has_delete_permission(self._request(), self.v1))


@override_settings(ALLOWED_HOSTS=["billing.example.test", "testserver"])
class SignerOriginTests(TestCase):
    """The recorded signing IP must be one the signer cannot choose.

    Django sits behind Caddy (`reverse_proxy web:8000`), so REMOTE_ADDR is the
    proxy — constant for everyone — and X-Forwarded-For is client-writable at the
    LEFT. Caddy appends the true peer, so only the RIGHTMOST hop is trustworthy.
    """

    def setUp(self):
        self.client = Client()
        self.user, self.customer = _customer()
        self.client.force_login(self.user)
        ContractTemplate.objects.filter(
            kind=ContractTemplate.Kind.CUSTOMER).update(active=False)
        ContractTemplate.objects.create(
            kind=ContractTemplate.Kind.CUSTOMER, version="ip-test",
            body_md="terms", active=True)

    def _sign(self, **extra):
        return self.client.post(reverse("customer_agreement"),
                                {"signed_name": "Ada Lovelace", "agree": "on"}, **extra)

    def test_a_spoofed_forwarded_for_is_not_recorded_as_the_signer_ip(self):
        # The client claims 1.2.3.4; Caddy appends the address it really saw.
        self._sign(HTTP_X_FORWARDED_FOR="1.2.3.4, 203.0.113.9", REMOTE_ADDR="172.18.0.3")
        sig = CustomerContract.objects.get(customer=self.customer)
        self.assertEqual(sig.signer_ip, "203.0.113.9", "must take the hop our proxy appended")
        self.assertNotEqual(sig.signer_ip, "1.2.3.4", "the client-supplied hop is forgeable")
        self.assertEqual(sig.signer_forwarded_for, "1.2.3.4, 203.0.113.9",
                         "the whole chain is kept so a spoof attempt stays visible")

    def test_single_hop_is_recorded_as_is(self):
        self._sign(HTTP_X_FORWARDED_FOR="203.0.113.9", REMOTE_ADDR="172.18.0.3")
        sig = CustomerContract.objects.get(customer=self.customer)
        self.assertEqual(sig.signer_ip, "203.0.113.9")

    def test_without_a_proxy_header_remote_addr_is_used(self):
        self._sign(REMOTE_ADDR="203.0.113.9")
        sig = CustomerContract.objects.get(customer=self.customer)
        self.assertEqual(sig.signer_ip, "203.0.113.9")
        self.assertEqual(sig.signer_forwarded_for, "")
