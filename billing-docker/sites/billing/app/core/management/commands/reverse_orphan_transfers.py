"""Reconcile Stripe transfers against the SplitPayout ledger.

Every affiliate payout this service sends is recorded as a SplitPayout row with
its transfer id. A transfer that exists in Stripe with NO matching row is money
that left the platform without the books knowing — it should not exist, and
until it is reversed the ledger and Stripe disagree.

That is not hypothetical. On 2026-08-04 a failing split leg raised inside the
webhook's database transaction, rolling back the PAID row of a *successful*
sibling leg whose transfer had already gone out. The replay then saw an
unrecorded leg and paid it a second time. The code path is fixed (splits report
failures instead of raising), and this command is the reconciliation that proves
the two systems still agree.

    python manage.py reverse_orphan_transfers            # report only (default)
    python manage.py reverse_orphan_transfers --confirm  # reverse the orphans

Reversing is safe to re-run: a transfer already fully reversed is skipped, and
the reversal amount is always what remains, never the original amount.
"""
from django.core.management.base import BaseCommand

from core import stripe_svc
from core.models import Affiliate, SplitPayout


class Command(BaseCommand):
    help = "Find Stripe transfers with no SplitPayout row and (optionally) reverse them"

    def add_arguments(self, parser):
        parser.add_argument("--confirm", action="store_true",
                            help="actually reverse. Without this the command only reports.")
        parser.add_argument("--limit", type=int, default=100,
                            help="how many recent transfers to examine (default 100)")

    def handle(self, *args, **options):
        s = stripe_svc._client()
        recorded = set(
            SplitPayout.objects.exclude(stripe_transfer_id="")
            .values_list("stripe_transfer_id", flat=True)
        )
        who = {a.stripe_connect_account_id: a.code
               for a in Affiliate.objects.all() if a.stripe_connect_account_id}

        orphans, checked = [], 0
        for t in s.Transfer.list(limit=options["limit"]).auto_paging_iter():
            checked += 1
            outstanding = t["amount"] - t["amount_reversed"]
            if t["id"] in recorded or outstanding <= 0:
                continue
            orphans.append((t["id"], outstanding, who.get(t["destination"], t["destination"])))

        self.stdout.write(f"examined {checked} transfers against {len(recorded)} ledger rows")
        if not orphans:
            self.stdout.write(self.style.SUCCESS("✓ no orphans — Stripe and the ledger agree"))
            return

        for tid, amount, code in orphans:
            self.stdout.write(f"  orphan {tid} {amount}c -> {code}")
        if not options["confirm"]:
            self.stdout.write(self.style.WARNING(
                f"\n{len(orphans)} orphan transfer(s). Re-run with --confirm to reverse them."))
            return

        for tid, amount, code in orphans:
            try:
                r = s.Transfer.create_reversal(
                    tid, amount=amount,
                    description="reconciliation: transfer had no SplitPayout ledger row",
                    idempotency_key=f"orphan-reversal:{tid}:{amount}",
                )
            except Exception as exc:  # noqa: BLE001 — report and keep going
                self.stdout.write(self.style.ERROR(f"  ✗ {tid}: {exc}"))
            else:
                self.stdout.write(self.style.SUCCESS(f"  ✓ reversed {tid} {amount}c from {code} ({r['id']})"))
