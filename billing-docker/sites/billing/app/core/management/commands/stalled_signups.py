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

from core.models import Customer, Instance, Subscription

# Funnel order: a customer is reported at the first step it has not passed.
STEPS = [
    ("no_checkout", "registered, never started checkout (no Stripe customer)"),
    ("checkout_unfinished", "started checkout, no active or trialing subscription"),
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
    if not subs:
        return "no_checkout" if not customer.stripe_customer_id else "checkout_unfinished"
    if not subs & PAYING:
        return "lapsed" if subs & LAPSED else "checkout_unfinished"
    instances = {i.status for i in customer.instances.all()}
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
