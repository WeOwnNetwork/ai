"""Keycloak OIDC backend — maps the KC identity onto Django users and keeps a
Customer row per login. Staff/superuser is NEVER granted from OIDC claims;
admin access is the local break-glass account only (or explicit manual flag)."""
from mozilla_django_oidc.auth import OIDCAuthenticationBackend

from .models import Customer


def _email_verified(claims):
    # Keycloak sends a JSON boolean; anything else (absent, "true") is unverified.
    return claims.get("email_verified") is True


class WeOwnOIDCBackend(OIDCAuthenticationBackend):
    def get_username(self, claims):
        return claims.get("preferred_username") or claims.get("email")

    def filter_users_by_claims(self, claims):
        """Link a login to an existing user (weown-fleet#96).

        1. by Keycloak `sub`, recorded on the Customer at first login;
        2. else by e-mail ONLY when Keycloak marks it verified, and never onto a
           staff/superuser: the break-glass account's e-mail is fixed and known,
           and self-registration lets anyone claim any unverified address.
        No match means a NEW user (library default), never someone else's."""
        sub = claims.get("sub")
        if sub:
            by_sub = self.UserModel.objects.filter(customer__kc_user_id=sub)
            if by_sub.exists():
                return by_sub
        email = claims.get("email")
        if not email or not _email_verified(claims):
            return self.UserModel.objects.none()
        return self.UserModel.objects.filter(
            email__iexact=email, is_staff=False, is_superuser=False)

    def _sync(self, user, claims):
        if _email_verified(claims):
            user.email = claims.get("email", user.email)
        user.first_name = claims.get("given_name", "")
        user.last_name = claims.get("family_name", "")
        user.save()
        customer, _ = Customer.objects.get_or_create(user=user)
        sub = claims.get("sub", "")
        if sub and customer.kc_user_id != sub:
            customer.kc_user_id = sub
            customer.save(update_fields=["kc_user_id"])
        return user

    def create_user(self, claims):
        return self._sync(super().create_user(claims), claims)

    def update_user(self, user, claims):
        return self._sync(user, claims)
