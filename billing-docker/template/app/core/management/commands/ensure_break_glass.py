"""Idempotent break-glass local superuser.

Rules baked in from the Gitea/KC incidents: the account gets its OWN email
(never a human's — SSO auto-link-by-email hijacks sessions otherwise) and the
password comes from Infisical (BILLING_BREAK_GLASS_PASSWORD), never argv/disk.
"""
import os

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

USERNAME = "weown-admin"
EMAIL = "billing-admin@weown.net"


class Command(BaseCommand):
    help = "Create/refresh the weown-admin break-glass superuser from env"

    def handle(self, *args, **options):
        password = os.environ.get("BILLING_BREAK_GLASS_PASSWORD", "")
        if not password:
            self.stderr.write("BILLING_BREAK_GLASS_PASSWORD not set — break-glass account NOT created")
            return
        User = get_user_model()
        bound = User.objects.filter(username=USERNAME, customer__isnull=False).exclude(customer__kc_user_id="")
        if bound.exists():
            # An SSO user already holds this username: promoting it would make that
            # Keycloak identity a superuser via the sub login path. Refuse, loudly;
            # don't exit non-zero (start.sh is `set -e`, and billing must still boot).
            self.stderr.write(f"REFUSED: {USERNAME} is bound to a Keycloak identity; break-glass NOT "
                              "created/promoted. Rename or unlink that user, then re-run.")
            return
        user, created = User.objects.get_or_create(
            username=USERNAME, defaults={"email": EMAIL, "is_staff": True, "is_superuser": True}
        )
        user.is_staff = user.is_superuser = True
        user.email = EMAIL
        user.set_password(password)
        user.save()
        self.stdout.write(f"break-glass superuser {'created' if created else 'refreshed'}: {USERNAME}")
