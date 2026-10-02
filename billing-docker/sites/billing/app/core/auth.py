"""Keycloak OIDC backend — maps the KC identity onto Django users and keeps a
Customer row per login. Staff/superuser is NEVER granted from OIDC claims;
admin access is local login only (break-glass, or a manually flagged user):
a Keycloak login onto a staff/superuser is refused."""
import logging

from django.core.exceptions import SuspiciousOperation
from django.db.models import Q
from mozilla_django_oidc.auth import OIDCAuthenticationBackend

from .models import Customer

log = logging.getLogger(__name__)


def _email_verified(claims):
    # Keycloak sends a JSON boolean; anything else (absent, "true") is unverified.
    return claims.get("email_verified") is True


def _refuse(event, user=None):
    # Fail the login (the library turns this into "no user"). The log names the
    # event and our row id only: no e-mail, no sub (weown-fleet#107).
    log.warning("oidc login refused: %s (user_id=%s)", event, getattr(user, "pk", None))
    raise SuspiciousOperation(f"oidc login refused: {event}")


class WeOwnOIDCBackend(OIDCAuthenticationBackend):
    def get_username(self, claims):
        return claims.get("preferred_username") or claims.get("email")

    def filter_users_by_claims(self, claims):
        """Link a login to an existing user (weown-fleet#96).

        1. by Keycloak `sub`, recorded on the Customer at first login;
        2. else by e-mail ONLY when Keycloak marks it verified, never onto a
           staff/superuser (the break-glass e-mail is fixed and known), and only
           onto a user not yet bound to a Keycloak sub (no takeover of a bound
           account by another identity with the same verified e-mail).
        A sub bound to a staff/superuser fails the login: admin is local only.
        No match means a NEW user (library default), never someone else's."""
        sub = claims.get("sub")
        if sub:
            by_sub = self.UserModel.objects.filter(customer__kc_user_id=sub)
            if by_sub.filter(Q(is_staff=True) | Q(is_superuser=True)).exists():
                _refuse("sub is bound to a staff/superuser")
            if by_sub.exists():
                return by_sub
        email = claims.get("email")
        if not email or not _email_verified(claims):
            return self.UserModel.objects.none()
        return self.UserModel.objects.filter(
            Q(customer__isnull=True) | Q(customer__kc_user_id=""),
            email__iexact=email, is_staff=False, is_superuser=False)

    def _sync(self, user, claims):
        customer, _ = Customer.objects.get_or_create(user=user)
        sub = claims.get("sub", "")
        if sub and customer.kc_user_id and customer.kc_user_id != sub:
            _refuse("account is bound to a different sub", user)
        if _email_verified(claims):
            user.email = claims.get("email", user.email)
        user.first_name = claims.get("given_name", "")
        user.last_name = claims.get("family_name", "")
        user.save()
        if sub and customer.kc_user_id != sub:
            customer.kc_user_id = sub
            customer.save(update_fields=["kc_user_id"])
        return user

    def create_user(self, claims):
        return self._sync(super().create_user(claims), claims)

    def update_user(self, user, claims):
        return self._sync(user, claims)
