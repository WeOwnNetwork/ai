"""Create (or reuse) an affiliate's Stripe Connect Express account and print a
one-time onboarding link to send them.

Requires Connect enabled on the Stripe account (Dashboard -> Connect). Prints
only the account id and the onboarding URL — no secrets.
"""
import stripe
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from core.models import Affiliate


class Command(BaseCommand):
    help = "Create/refresh a Stripe Connect Express account + onboarding link for an affiliate"

    def add_arguments(self, parser):
        parser.add_argument("code", help="affiliate referral code")

    def handle(self, *args, **o):
        stripe.api_key = settings.STRIPE_SECRET_KEY
        aff = Affiliate.objects.filter(code=o["code"]).first()
        if not aff:
            raise CommandError(f"No affiliate with code {o['code']}")
        base = f"https://{settings.ALLOWED_HOSTS[0]}"
        if not aff.stripe_connect_account_id:
            acct = stripe.Account.create(
                type="express",
                email=aff.user.email,
                capabilities={"transfers": {"requested": True}},
                business_type="individual",
                metadata={"affiliate_code": aff.code},
            )
            aff.stripe_connect_account_id = acct["id"]
            aff.save(update_fields=["stripe_connect_account_id"])
            self.stdout.write(f"created Connect account {acct['id']} for {aff.code}")
        else:
            self.stdout.write(f"reusing Connect account {aff.stripe_connect_account_id}")
        link = stripe.AccountLink.create(
            account=aff.stripe_connect_account_id,
            refresh_url=f"{base}/affiliate/",
            return_url=f"{base}/affiliate/",
            type="account_onboarding",
        )
        self.stdout.write(f"ONBOARDING URL (single use, expires in minutes):\n{link['url']}")
