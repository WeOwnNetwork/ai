"""Seed rows every fresh deployment needs: the current split defaults and the
placeholder v0.1 affiliate agreement (test-mode text — replace with the
legal-approved version as a NEW ContractTemplate row before real affiliates
sign; v0.1 becomes inactive then, its signatures stay intact)."""
from django.db import migrations

PLACEHOLDER = """WeOwn Affiliate Agreement — v0.1 (PLACEHOLDER, TEST MODE ONLY)

This is a placeholder agreement used while the billing system runs in Stripe
test mode. It is not a binding contract. The legal-approved agreement will be
published as a new version; affiliates will be asked to sign that version
before any live payouts are made.

1. The affiliate refers customers to WeOwn via their referral link.
2. WeOwn pays the affiliate a percentage of collected subscription revenue
   from referred customers (tier 1), and a smaller percentage to the
   affiliate's sponsor where one exists (tier 2), at the rates configured in
   the WeOwn billing system at the time of each payment.
3. Payouts are made via Stripe Connect. The affiliate is responsible for
   completing Stripe onboarding and for their own taxes.
4. Either party may end the arrangement at any time; earned, unpaid splits
   for already-collected invoices remain payable.
"""


def seed(apps, schema_editor):
    SplitConfig = apps.get_model("core", "SplitConfig")
    if not SplitConfig.objects.exists():
        SplitConfig.objects.create(tier1_pct=20, tier2_pct=5, note="initial defaults (seed)")
    ContractTemplate = apps.get_model("core", "ContractTemplate")
    if not ContractTemplate.objects.exists():
        ContractTemplate.objects.create(version="0.1", body_md=PLACEHOLDER, active=True)


class Migration(migrations.Migration):
    dependencies = [("core", "0001_initial")]
    operations = [migrations.RunPython(seed, migrations.RunPython.noop)]
