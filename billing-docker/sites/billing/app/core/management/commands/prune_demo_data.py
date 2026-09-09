"""prune_demo_data — take the billing site OUT of demo mode (Nik, 2026-09-08:
"remove demo etc and start using these as real sites now").

Demo rows in a PRODUCTION database are not inert: an affiliate row brands the
whole pre-purchase funnel, so `demo-brand` was painting a customer-facing
"Need help? demo-support@weown.dev" and a placehold.co logo on billing.weown.dev
for any visitor whose session carried its referral code.

DISABLE OVER DELETE (the standing policy): this sets active=False, which is the
switch the branding chokepoint already reads, and is undone by flipping it back.
It NEVER deletes a row, and it refuses to touch an affiliate that has referred
anyone — a demo-looking code with a real customer behind it is a business
record, not test data.

    python manage.py prune_demo_data                 # dry run: what would change
    python manage.py prune_demo_data --apply
    python manage.py prune_demo_data --restore       # undo (re-activate the same codes)
"""
from django.core.management.base import BaseCommand

from core.models import Affiliate, Customer

#: Codes minted for demos/tests. `weown-partner` / `weown-mentor` are the real
#: programme tiers and are deliberately absent.
DEMO_CODES = ["demo-brand", "chatdemo", "weown-demo", "nik-chat"]


class Command(BaseCommand):
    help = "Deactivate (or restore) demo affiliate rows so no demo branding reaches customers"

    def add_arguments(self, parser):
        parser.add_argument("--apply", action="store_true")
        parser.add_argument("--restore", action="store_true", help="re-activate the same codes")
        parser.add_argument("--codes", default=",".join(DEMO_CODES))

    def handle(self, *a, **o):
        target_active = bool(o["restore"])
        changed = kept = 0
        for code in [c.strip() for c in o["codes"].split(",") if c.strip()]:
            aff = Affiliate.objects.filter(code=code).first()
            if not aff:
                self.stdout.write(f"absent      {code}")
                continue
            refs = Customer.objects.filter(referred_by=aff).count()
            if refs and not o["restore"]:
                self.stdout.write(f"KEPT        {code} — {refs} referred customer(s); this is a business record")
                kept += 1
                continue
            if aff.active == target_active:
                self.stdout.write(f"unchanged   {code} (active={aff.active})")
                continue
            if o["apply"]:
                aff.active = target_active
                aff.save(update_fields=["active"])
                self.stdout.write(f"{'restored' if target_active else 'deactivated'}  {code}"
                                  + (f" — was branding the funnel as {aff.display_name!r}" if aff.display_name else ""))
            else:
                self.stdout.write(f"would {'restore' if target_active else 'deactivate'} {code}"
                                  + (f" (brand {aff.display_name!r}, support {aff.support_email!r})" if aff.display_name or aff.support_email else ""))
            changed += 1
        self.stdout.write("")
        self.stdout.write("active affiliates now: " + ", ".join(
            Affiliate.objects.filter(active=True).order_by("code").values_list("code", flat=True)) or "(none)")
        if changed and not o["apply"]:
            self.stdout.write(self.style.WARNING("DRY RUN — re-run with --apply"))
        if kept:
            self.stdout.write(self.style.WARNING(f"{kept} code(s) kept because customers are attached to them"))
