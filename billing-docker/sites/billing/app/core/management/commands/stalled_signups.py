"""Read-only: where did every sign-up since a date stop? (weown-fleet#66)

    python manage.py stalled_signups [--since 2026-09-10] [--ids]

The no-instance paywall (WeOwnNetwork/ai#252) means someone can register and
never finish, leaving an account with nothing behind it, and nobody could see
how many. This places each Customer created on or after --since at the FIRST
step of the funnel it has not passed, and prints one count per step.

It prints NO personal data: no emails, no names. With --ids it adds each step's
Customer primary keys, for an operator to open in the admin. It writes nothing.

Not covered: Keycloak registrations that never reached billing have no Customer
row at all. Counting those needs the Keycloak admin API; this command only sees
what billing saw.
"""
from datetime import datetime, timezone

from django.core.management.base import BaseCommand, CommandError
from django.db.models import Prefetch

from core.models import Customer, CustomerContract, Instance, Subscription

# Funnel order: a customer is reported at the first step it has not passed.
STEPS = [
    ("no_agreement", "registered, never signed the customer agreement (the gate before checkout)"),
    ("signed_no_checkout", "signed the agreement, no checkout recorded (see note: includes the legacy /subscribe/ route)"),
    ("checkout_unfinished", "started checkout (an instance was requested), no active or trialing subscription"),
    ("lapsed", "had a subscription, now past_due or canceled"),
    ("paid_no_instance", "paying (active/trialing), but no instance requested"),
    ("provisioning_stuck", "paying, instance requested or provisioning, not yet active"),
    ("instance_inactive", "instance paused, destroying or destroyed"),
    ("live", "paying and the instance is active"),
]
PAYING = {Subscription.Status.ACTIVE, Subscription.Status.TRIALING}
LAPSED = {Subscription.Status.PAST_DUE, Subscription.Status.CANCELED}
PENDING_INSTANCE = {Instance.Status.REQUESTED, Instance.Status.PROVISIONING}


def classify(customer):
    subs = {s.status for s in customer.subscriptions.all()}
    instances = {i.status for i in customer.instances.all()}
    if not subs:
        # Checkout STARTED is not the Stripe customer id: that is written only on
        # checkout.session.completed (views.py stripe webhook). What exists from
        # the moment checkout starts is the Instance row, which new_instance
        # creates BEFORE redirecting to Stripe. So an abandoned first checkout is
        # an instance with no subscription, not a sign-up that never began.
        #
        # One door leaves no row: the legacy /subscribe/ route opens Checkout
        # without an Instance. No page links to it, but it is live, so an
        # abandoned checkout through it is indistinguishable from never starting.
        # The agreement signature is the step just before checkout on BOTH
        # doors, so it bounds that gap: such a customer lands in
        # signed_no_checkout, never in no_agreement.
        started = bool(customer.stripe_customer_id) or bool(instances)
        if started:
            return "checkout_unfinished"
        return "signed_no_checkout" if customer.contracts.all() else "no_agreement"
    if not subs & PAYING:
        return "lapsed" if subs & LAPSED else "checkout_unfinished"
    if Instance.Status.ACTIVE in instances:
        return "live"
    if instances & PENDING_INSTANCE:
        return "provisioning_stuck"
    if instances:
        return "instance_inactive"
    return "paid_no_instance"


class Command(BaseCommand):
    help = "Read-only: count sign-ups since a date by the funnel step each one stopped at (no personal data)"

    def add_arguments(self, parser):
        parser.add_argument("--since", default="2026-09-10", help="YYYY-MM-DD, UTC (default: the paywall launch)")
        parser.add_argument("--ids", action="store_true", help="also list Customer primary keys per step")

    def handle(self, *args, **o):
        try:
            since = datetime.strptime(o["since"], "%Y-%m-%d").replace(tzinfo=timezone.utc)
        except ValueError as e:
            raise CommandError(f"--since must be YYYY-MM-DD: {e}") from e
        customers = Customer.objects.filter(created_at__gte=since).prefetch_related(
            Prefetch("subscriptions", queryset=Subscription.objects.only("customer_id", "status")),
            Prefetch("instances", queryset=Instance.objects.only("customer_id", "status")),
            Prefetch("contracts", queryset=CustomerContract.objects.only("customer_id")),
        )
        by_step = {key: [] for key, _ in STEPS}
        for c in customers:
            by_step[classify(c)].append(c.pk)
        total = sum(len(v) for v in by_step.values())
        stalled = total - len(by_step["live"])
        self.stdout.write(f"sign-ups since {o['since']} (UTC): {total} · live: {len(by_step['live'])} · stalled: {stalled}")
        self.stdout.write("step\tcount\tmeaning" + ("\tcustomer_ids" if o["ids"] else ""))
        for key, meaning in STEPS:
            row = f"{key}\t{len(by_step[key])}\t{meaning}"
            if o["ids"]:
                row += "\t" + ",".join(str(pk) for pk in sorted(by_step[key]))
            self.stdout.write(row)
        self.stdout.write("note: an abandoned checkout through the unlinked legacy /subscribe/ route leaves no "
                          "record, so it is counted in signed_no_checkout, not checkout_unfinished")
