"""Register an existing WeOwn user as an affiliate (operator command).

The user must have signed in to the billing portal at least once (that is what
creates their Django user via Keycloak OIDC). Percentages come from SplitConfig
unless overridden here. The affiliate stays INACTIVE until they sign the
agreement in the portal — that is the gate for any payout.
"""
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError

from core.models import Affiliate


class Command(BaseCommand):
    help = "Create an affiliate for an existing portal user"

    def add_arguments(self, parser):
        parser.add_argument("email")
        parser.add_argument("code", help="referral code used in ?ref= links")
        parser.add_argument("--parent", help="referral code of the tier-2 sponsor")
        parser.add_argument("--tier1-pct", type=float)
        parser.add_argument("--tier2-pct", type=float)
        parser.add_argument(
            "--create-user", action="store_true",
            help="Invite: create the portal account now (no password — SSO links it by "
                 "email on their first sign-in) instead of requiring they log in first",
        )

    def handle(self, *args, **o):
        User = get_user_model()
        user = User.objects.filter(email__iexact=o["email"]).first()
        if not user and o["create_user"]:
            user = User.objects.create_user(username=o["email"], email=o["email"])
            user.set_unusable_password()  # SSO only — no local login
            user.save()
            self.stdout.write(f"invited: created portal account for {o['email']} (SSO will link it)")
        if not user:
            raise CommandError(
                f"No portal user with email {o['email']} — either they sign in to "
                "billing once first, or re-run with --create-user to invite them."
            )
        parent = None
        if o.get("parent"):
            parent = Affiliate.objects.filter(code=o["parent"]).first()
            if not parent:
                raise CommandError(f"No affiliate with code {o['parent']}")
        aff, created = Affiliate.objects.get_or_create(
            user=user,
            defaults={"code": o["code"], "parent": parent},
        )
        if not created:
            aff.code = o["code"]
        if parent:
            aff.parent = parent
        if o.get("tier1_pct") is not None:
            aff.tier1_pct_override = o["tier1_pct"]
        if o.get("tier2_pct") is not None:
            aff.tier2_pct_override = o["tier2_pct"]
        aff.save()
        self.stdout.write(
            f"{'created' if created else 'updated'}: {aff.code} "
            f"(user {user.email}, parent={aff.parent.code if aff.parent else '-'}, "
            f"active={aff.active}) — they must sign the agreement at /affiliate/ to activate"
        )
