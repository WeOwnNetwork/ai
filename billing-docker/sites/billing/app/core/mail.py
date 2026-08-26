"""Transactional email — best-effort, never fatal.

The customer-facing lifecycle notices (welcome, trial-ending, payment-failed,
suspended). Two rules make this safe to call from a webhook:

1. **Never raises.** A mail send is best-effort exactly like the Keycloak flip:
   an SMTP hiccup must never fail a Stripe webhook (which would make Stripe
   retry and re-run the money logic). Failures are logged, swallowed, and the
   caller carries on.
2. **Send AFTER commit, not inside the transaction.** Callers wrap this in
   `transaction.on_commit(...)` so the network I/O happens once the DB
   transaction has committed and its locks are released — never holding a row
   lock open across an SMTP round-trip.

Config is env-driven (SMTP_* → Django EMAIL_* in settings). With SMTP unset the
send is a logged no-op, so a dev/POC deployment runs without mail configured and
nothing breaks — the same config-not-constant posture as the trial and the
split rates.

⚠️ Deploy notes baked into the config, not discovered later:
- **DigitalOcean blocks outbound port 587** on droplets — the default here is
  **2525** (SendGrid/Mailgun submission alt-port). 587 will silently time out.
- SendGrid has DKIM history on this fleet (A543) — verify `dkim=pass` before
  trusting deliverability.
"""
import logging

from django.conf import settings
from django.core.mail import send_mail
from django.template.loader import render_to_string
from django.template import TemplateDoesNotExist

log = logging.getLogger(__name__)

# One subject per kind; the body is core/email/<kind>.txt rendered with ctx.
_SUBJECTS = {
    "welcome": "Welcome to WeOwn — your instance is being set up",
    "instance_ready": "Your WeOwn instance is ready",
    "trial_ending": "Your WeOwn trial ends soon",
    "payment_failed": "We couldn't process your WeOwn payment",
    "suspended": "Your WeOwn subscription has ended",
}


def _configured() -> bool:
    return bool(getattr(settings, "EMAIL_HOST", "") and getattr(settings, "DEFAULT_FROM_EMAIL", ""))


def notify(to_email: str, kind: str, ctx: dict | None = None) -> bool:
    """Send one lifecycle email. Returns True if handed to the backend, False on
    any skip/failure. NEVER raises — a mail problem must not break a webhook."""
    ctx = ctx or {}
    if not to_email:
        log.warning("mail skipped (%s): no recipient", kind)
        return False
    subject = _SUBJECTS.get(kind)
    if not subject:
        log.error("mail skipped: unknown kind %r", kind)
        return False
    if not _configured():
        # A POC/dev box with no SMTP configured. Loud enough to find, not a
        # failure — the feature degrades to "logged, not sent".
        log.info("mail NOT sent (SMTP unconfigured): %s → %s", kind, to_email)
        return False
    try:
        body = render_to_string(f"core/email/{kind}.txt", ctx)
    except TemplateDoesNotExist:
        log.error("mail skipped: no template for kind %r", kind)
        return False
    try:
        send_mail(subject, body, settings.DEFAULT_FROM_EMAIL, [to_email],
                  fail_silently=False)
        log.info("mail sent: %s → %s", kind, to_email)
        return True
    except Exception:  # noqa: BLE001 — best-effort; a webhook must not fail on mail
        log.exception("mail FAILED (%s → %s) — swallowed so the webhook succeeds",
                      kind, to_email)
        return False
