"""Tests for the trial + customer-agreement gate.

Stripe is mocked throughout — these assert OUR logic (what we send Stripe, what
we do with what it sends back), never Stripe's behaviour. The
`test_zero_amount_trial_invoice_pays_no_commission` case is the one that must
never regress: it is the difference between a free trial and paying commission
on money nobody paid.
"""
import hashlib
import json
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
