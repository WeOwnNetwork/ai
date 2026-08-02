"""Keycloak OIDC backend — maps the KC identity onto Django users and keeps a
Customer row per login. Staff/superuser is NEVER granted from OIDC claims;
admin access is the local break-glass account only (or explicit manual flag)."""
from mozilla_django_oidc.auth import OIDCAuthenticationBackend

from .models import Customer


class WeOwnOIDCBackend(OIDCAuthenticationBackend):
    def get_username(self, claims):
        return claims.get("preferred_username") or claims.get("email")

    def _sync(self, user, claims):
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
