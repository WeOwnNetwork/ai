"""WeOwn billing service — Django settings.

All secrets arrive via environment (Infisical in-process injection, ADR-006).
Non-secret config comes from compose `environment:`. Nothing is read from files.
"""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.environ["DJANGO_SECRET_KEY"]
DEBUG = os.environ.get("DJANGO_DEBUG", "") == "1"
# Comma-separated: first entry is the canonical host (used to build absolute
# URLs); extras are aliases so a domain swap/addition is config-only.
ALLOWED_HOSTS = [h.strip() for h in os.environ.get("DJANGO_ALLOWED_HOST", "localhost").split(",") if h.strip()]
CSRF_TRUSTED_ORIGINS = [f"https://{h}" for h in ALLOWED_HOSTS if h != "localhost"]

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "mozilla_django_oidc",
    "core",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "core.middleware.ReferralCodeMiddleware",
]

ROOT_URLCONF = "billing.urls"
WSGI_APPLICATION = "billing.wsgi.application"

TEMPLATES = [{
    "BACKEND": "django.template.backends.django.DjangoTemplates",
    "DIRS": [],
    "APP_DIRS": True,
    "OPTIONS": {"context_processors": [
        "django.template.context_processors.request",
        "django.contrib.auth.context_processors.auth",
        "django.contrib.messages.context_processors.messages",
        "core.context_processors.nav",
        "core.context_processors.branding",
    ]},
}]

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.environ.get("POSTGRES_DB", "billing"),
        "USER": os.environ.get("POSTGRES_USER", "billing"),
        "PASSWORD": os.environ.get("POSTGRES_PASSWORD", ""),
        "HOST": os.environ.get("POSTGRES_HOST", "db"),
        "PORT": os.environ.get("POSTGRES_PORT", "5432"),
    }
}

# ── Auth: Keycloak OIDC (same realm the customer's instance uses) ──────────
_ISSUER = os.environ.get("OIDC_OP_ISSUER", "").rstrip("/")
OIDC_OP_ISSUER = _ISSUER  # read back by core.keycloak for the admin API base
AUTHENTICATION_BACKENDS = [
    "core.auth.WeOwnOIDCBackend",
    "django.contrib.auth.backends.ModelBackend",  # break-glass local admin
]
OIDC_OP_AUTHORIZATION_ENDPOINT = f"{_ISSUER}/protocol/openid-connect/auth"
OIDC_OP_TOKEN_ENDPOINT = f"{_ISSUER}/protocol/openid-connect/token"
OIDC_OP_USER_ENDPOINT = f"{_ISSUER}/protocol/openid-connect/userinfo"
OIDC_OP_JWKS_ENDPOINT = f"{_ISSUER}/protocol/openid-connect/certs"
OIDC_RP_CLIENT_ID = os.environ.get("OIDC_RP_CLIENT_ID", "billing")
OIDC_RP_CLIENT_SECRET = os.environ.get("OIDC_RP_CLIENT_SECRET", "")
OIDC_RP_SIGN_ALGO = "RS256"
LOGIN_URL = "/oidc/authenticate/"
LOGIN_REDIRECT_URL = "/"
LOGOUT_REDIRECT_URL = "/"

# ── Transactional email (SMTP; unconfigured = a logged no-op) ──────────────
# ⚠️ DigitalOcean blocks outbound 587 on droplets — default to 2525 (submission
# alt-port). SMTP_HOST empty → EMAIL_HOST empty → core.mail.notify no-ops.
EMAIL_HOST = os.environ.get("SMTP_HOST", "")
EMAIL_PORT = int(os.environ.get("SMTP_PORT", "2525") or "2525")
EMAIL_HOST_USER = os.environ.get("SMTP_USER", "")
EMAIL_HOST_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
EMAIL_USE_TLS = os.environ.get("SMTP_USE_TLS", "1") == "1"
EMAIL_TIMEOUT = 10  # never let a slow SMTP server hang a webhook worker
DEFAULT_FROM_EMAIL = os.environ.get("MAIL_FROM", "WeOwn <no-reply@weown.dev>")

# ── Stripe (test keys until Nik flips them in Infisical) ───────────────────
STRIPE_SECRET_KEY = os.environ.get("STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.environ.get("STRIPE_WEBHOOK_SECRET", "")
STRIPE_PRICE_ID = os.environ.get("STRIPE_PRICE_ID", "")  # the single product's price


def _trial_days() -> int:
    """Free-trial length in days; 0 disables the trial entirely.

    Config, never a constant: the same image has to run the $5 real-money drill
    product and the $1,000 live product, and pointing at either must be an
    Infisical/env change plus a restart — not a deploy. A non-numeric or
    negative value is treated as "no trial" rather than crashing the app at
    import time, because a bad env var must not take billing down.
    """
    raw = (os.environ.get("STRIPE_TRIAL_DAYS", "") or "").strip()
    try:
        return max(0, int(raw))
    except ValueError:
        return 0


STRIPE_TRIAL_DAYS = _trial_days()

# ── Keycloak admin (service account that flips subscription_active) ────────
KC_ADMIN_CLIENT_ID = os.environ.get("KC_ADMIN_CLIENT_ID", "billing-admin")
KC_ADMIN_CLIENT_SECRET = os.environ.get("KC_ADMIN_CLIENT_SECRET", "")

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = not DEBUG
CSRF_COOKIE_SECURE = not DEBUG

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_TZ = True
