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
    SplitConfig, SplitPayout, SplitReversal, Subscription,
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


class RefundClawbackTests(TestCase):
    """Refund/dispute → proportional clawback of every paid split leg.

    The invariant under test is not "a reversal happens" but "the RIGHT amount
    happens, exactly once, and a failure never destroys the record of money
    that already moved" — the mirror of the 2026-08-04 double payout.
    """

    def setUp(self):
        SplitConfig.objects.create(tier1_pct=20, tier2_pct=5, monthly_cogs_cents=0)
        sponsor_user = User.objects.create_user(username="sponsor", email="s@example.test")
        self.sponsor = Affiliate.objects.create(
            user=sponsor_user, code="sponsor", active=True,
            stripe_connect_account_id="acct_sponsor")
        aff_user = User.objects.create_user(username="aff", email="a@example.test")
        self.affiliate = Affiliate.objects.create(
            user=aff_user, code="larry", active=True, parent=self.sponsor,
            stripe_connect_account_id="acct_larry")
        _, customer = _customer()
        self.sub = Subscription.objects.create(
            customer=customer, affiliate=self.affiliate,
            status=Subscription.Status.ACTIVE, stripe_subscription_id="sub_1")

    def _paid_leg(self, tier=1, affiliate=None, cut=19414, gross=100000,
                  transfer="tr_1", status=SplitPayout.Status.PAID):
        return SplitPayout.objects.create(
            invoice_id="in_1", charge_id="ch_1", affiliate=affiliate or self.affiliate,
            tier=tier, gross_cents=gross, stripe_fee_cents=2930, cogs_cents=0,
            profit_cents=97070, pct=20, cut_cents=cut, status=status,
            stripe_transfer_id=transfer)

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal",
                return_value={"id": "trr_1"})
    def test_full_refund_reverses_the_whole_cut(self, rev):
        leg = self._paid_leg()
        failures = stripe_svc.reverse_affiliate_splits(
            "ch_1", refunded_cents=100000, reason="refund", event_id="evt_1")
        self.assertEqual(failures, [])
        row = SplitReversal.objects.get(payout=leg)
        self.assertEqual(row.status, SplitReversal.Status.REVERSED)
        self.assertEqual(row.amount_cents, leg.cut_cents)
        self.assertEqual(rev.call_args.kwargs["amount"], leg.cut_cents)
        self.assertEqual(rev.call_args.args[0], "tr_1")

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal",
                return_value={"id": "trr_1"})
    def test_partial_refund_is_proportional(self, rev):
        leg = self._paid_leg(cut=19414, gross=100000)
        stripe_svc.reverse_affiliate_splits(
            "ch_1", refunded_cents=30000, reason="refund", event_id="evt_1")
        row = SplitReversal.objects.get(payout=leg)
        # 30% refunded -> 30% of the cut clawed back, floored.
        self.assertEqual(row.amount_cents, int(19414 * 30000 / 100000))

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal",
                return_value={"id": "trr_1"})
    def test_every_leg_is_reversed_not_just_tier_one(self, rev):
        """Tyler's requirement: a reversal claws back from EVERY leg."""
        self._paid_leg(tier=1, affiliate=self.affiliate, cut=19414, transfer="tr_1")
        self._paid_leg(tier=2, affiliate=self.sponsor, cut=4853, transfer="tr_2")
        stripe_svc.reverse_affiliate_splits(
            "ch_1", refunded_cents=100000, reason="refund", event_id="evt_1")
        self.assertEqual(SplitReversal.objects.count(), 2)
        self.assertEqual(
            sorted(r.amount_cents for r in SplitReversal.objects.all()), [4853, 19414])

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal",
                return_value={"id": "trr_1"})
    def test_replayed_webhook_does_not_double_reverse(self, rev):
        self._paid_leg()
        stripe_svc.reverse_affiliate_splits("ch_1", 100000, "refund", "evt_1")
        stripe_svc.reverse_affiliate_splits("ch_1", 100000, "refund", "evt_1")
        self.assertEqual(rev.call_count, 1, "the same event must move money once")
        self.assertEqual(SplitReversal.objects.count(), 1)

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal",
                return_value={"id": "trr_1"})
    def test_successive_partial_refunds_reverse_only_the_remainder(self, rev):
        """The cumulative-target design: 30% then 100% must total 100%, not 130%."""
        leg = self._paid_leg(cut=19414, gross=100000)
        stripe_svc.reverse_affiliate_splits("ch_1", 30000, "refund", "evt_1")
        stripe_svc.reverse_affiliate_splits("ch_1", 100000, "refund", "evt_2")
        total = sum(r.amount_cents for r in SplitReversal.objects.all())
        self.assertEqual(total, leg.cut_cents, "never claw back more than was paid")
        self.assertEqual(rev.call_count, 2)
        self.assertEqual(rev.call_args.kwargs["amount"], leg.cut_cents - int(19414 * 0.3))

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal")
    def test_a_failing_reversal_returns_and_never_raises(self, rev):
        """The 2026-08-04 shape: raising here would roll back rows for money
        that already moved, and the retry would reverse it twice."""
        rev.side_effect = RuntimeError("connect account frozen")
        leg = self._paid_leg()
        failures = stripe_svc.reverse_affiliate_splits("ch_1", 100000, "refund", "evt_1")
        self.assertEqual(len(failures), 1)
        self.assertIn("connect account frozen", failures[0])
        row = SplitReversal.objects.get(payout=leg)
        self.assertEqual(row.status, SplitReversal.Status.FAILED)
        self.assertIn("connect account frozen", row.error)

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal",
                return_value={"id": "trr_ok"})
    def test_one_failing_leg_does_not_block_the_other(self, rev):
        rev.side_effect = [RuntimeError("frozen"), {"id": "trr_ok"}]
        self._paid_leg(tier=1, affiliate=self.affiliate, transfer="tr_1")
        self._paid_leg(tier=2, affiliate=self.sponsor, cut=4853, transfer="tr_2")
        failures = stripe_svc.reverse_affiliate_splits("ch_1", 100000, "refund", "evt_1")
        self.assertEqual(len(failures), 1)
        states = {r.status for r in SplitReversal.objects.all()}
        self.assertEqual(states, {SplitReversal.Status.FAILED,
                                  SplitReversal.Status.REVERSED})

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal")
    def test_a_leg_that_never_paid_is_not_reversed(self, rev):
        self._paid_leg(status=SplitPayout.Status.SKIPPED_NO_ACCOUNT, transfer="")
        failures = stripe_svc.reverse_affiliate_splits("ch_1", 100000, "refund", "evt_1")
        self.assertEqual(failures, [])
        rev.assert_not_called()
        self.assertEqual(SplitReversal.objects.get().status,
                         SplitReversal.Status.SKIPPED_NOT_PAID)

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal")
    def test_unknown_charge_is_a_no_op(self, rev):
        self.assertEqual(
            stripe_svc.reverse_affiliate_splits("ch_unknown", 100000, "refund", "evt_1"), [])
        rev.assert_not_called()


class RefundWebhookTests(TestCase):
    """The events that trigger a clawback."""

    def setUp(self):
        SplitConfig.objects.create(tier1_pct=20, tier2_pct=5, monthly_cogs_cents=0)
        aff_user = User.objects.create_user(username="aff", email="a@example.test")
        self.affiliate = Affiliate.objects.create(
            user=aff_user, code="larry", active=True,
            stripe_connect_account_id="acct_larry")
        _, self.customer = _customer()
        self.customer.stripe_customer_id = "cus_1"
        self.customer.save()
        SplitPayout.objects.create(
            invoice_id="in_1", charge_id="ch_1", affiliate=self.affiliate, tier=1,
            gross_cents=100000, stripe_fee_cents=2930, cogs_cents=0, profit_cents=97070,
            pct=20, cut_cents=19414, status=SplitPayout.Status.PAID,
            stripe_transfer_id="tr_1")

    def _process(self, event_type, obj, event_id="evt_1"):
        from . import views
        with mock.patch("core.views.keycloak.set_subscription_active"):
            return views._process_event(
                {"id": event_id, "type": event_type, "data": {"object": obj}})

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal",
                return_value={"id": "trr_1"})
    def test_charge_refunded_triggers_the_clawback(self, rev):
        failures = self._process("charge.refunded",
                                 {"id": "ch_1", "amount_refunded": 100000})
        self.assertEqual(failures, [])
        self.assertEqual(SplitReversal.objects.get().amount_cents, 19414)
        self.assertEqual(SplitReversal.objects.get().reason, "refund")

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal",
                return_value={"id": "trr_1"})
    def test_dispute_triggers_the_clawback(self, rev):
        self._process("charge.dispute.created",
                      {"charge": "ch_1", "amount": 100000, "customer": "cus_1"})
        row = SplitReversal.objects.get()
        self.assertEqual(row.reason, "dispute")
        self.assertEqual(row.amount_cents, 19414)

    @mock.patch("core.stripe_svc.stripe.Transfer.create_reversal",
                return_value={"id": "trr_1"})
    def test_funds_reinstated_does_not_auto_repay(self, rev):
        """Re-paying an affiliate is a new payment decision, not an undo."""
        self._process("charge.dispute.funds_reinstated", {"charge": "ch_1"})
        rev.assert_not_called()
        self.assertFalse(SplitReversal.objects.exists())
