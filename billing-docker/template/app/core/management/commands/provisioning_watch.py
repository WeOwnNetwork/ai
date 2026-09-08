"""provisioning_watch — tell a human when a PAID customer is sitting unprovisioned.

WHY (2026-09-08, A667): four paid tenants sat in "being set up" for up to a
month and it took a human asking. The queue existed (pending_instances); nobody
was told.

THREE states, never two — the absence-as-health trap this fleet has shipped
before (an ssh refusal used to read as an EMPTY queue):
  ALERT       stranded > 0   (paid, awaiting provisioning for > --minutes)
  OK          queue READ successfully and stranded == 0
  UNREADABLE  the read itself failed — reported with the exception text; it is
              NOT health and alerts distinctly.

Runs from cron on the billing box (see ansible/deploy.yml), writes a state file
the staff-only /ops/provisioning/ page serves (a place to LOOK, with a dead-man:
a stale file is shown as STALE), and e-mails OPS_ALERT_EMAIL on every state
change plus a reminder every --remind-hours while ALERT/UNREADABLE persists.
Optional OPS_ALERT_WEBHOOK_URL gets the same payload as JSON (Matrix/hookshot).
"""
import json
import logging
import os
import traceback
from datetime import timedelta

import requests
from django.conf import settings
from django.core.management.base import BaseCommand
from django.utils import timezone

from core import mail
from core.models import Instance, Subscription

log = logging.getLogger(__name__)

PAID = {Subscription.Status.ACTIVE, Subscription.Status.TRIALING} if hasattr(Subscription.Status, "TRIALING") else {Subscription.Status.ACTIVE}
WAITING = [Instance.Status.PROVISIONING, Instance.Status.REQUESTED] if hasattr(Instance.Status, "REQUESTED") else [Instance.Status.PROVISIONING]


def read_queue(minutes: int):
    """Return the list of stranded instances. Raises on any read problem —
    the caller maps an exception to UNREADABLE, never to an empty list."""
    cutoff = timezone.now() - timedelta(minutes=minutes)
    rows = []
    qs = (Instance.objects.filter(status__in=WAITING, created_at__lt=cutoff)
          .select_related("customer__user", "subscription").order_by("created_at"))
    for i in qs:
        sub = i.subscription
        if sub is None or sub.status not in PAID:
            continue  # unpaid rows are not stranded customers
        age = timezone.now() - i.created_at
        rows.append({
            "id": i.pk, "subdomain": i.subdomain, "status": i.status,
            "email": i.customer.user.email, "waiting_minutes": int(age.total_seconds() // 60),
            "last_log": (i.provision_log or "")[-160:],
        })
    return rows


def classify(minutes: int):
    try:
        stranded = read_queue(minutes)
    except Exception as e:  # noqa: BLE001 — every failure is a distinct state
        return {"state": "UNREADABLE", "stranded": [], "error": f"{type(e).__name__}: {e}",
                "trace": traceback.format_exc()[-1200:]}
    return {"state": "ALERT" if stranded else "OK", "stranded": stranded, "error": ""}


class Command(BaseCommand):
    help = "Three-state watch for paid-but-unprovisioned instances (ALERT / OK / UNREADABLE)"

    def add_arguments(self, parser):
        parser.add_argument("--minutes", type=int, default=15, help="age before a paid row counts as stranded")
        parser.add_argument("--remind-hours", type=int, default=6)
        parser.add_argument("--state-file", default=getattr(settings, "OPS_STATE_FILE", "/app/state/provisioning.json"))
        parser.add_argument("--no-notify", action="store_true", help="classify + write state only")

    def handle(self, *args, **o):
        now = timezone.now()
        result = classify(o["minutes"])
        result.update({"checked_at": now.isoformat(), "threshold_minutes": o["minutes"]})
        prev = self._load(o["state_file"])
        changed = prev.get("state") != result["state"] or (
            result["state"] == "ALERT" and sorted(r["id"] for r in prev.get("stranded", [])) != sorted(r["id"] for r in result["stranded"]))
        last_alert = prev.get("last_alert_at")
        remind_due = result["state"] != "OK" and (
            not last_alert or (now - timezone.datetime.fromisoformat(last_alert)) > timedelta(hours=o["remind_hours"]))
        notify = (changed or remind_due) and not o["no_notify"]
        result["last_alert_at"] = last_alert
        if notify and (result["state"] != "OK" or prev.get("state") in ("ALERT", "UNREADABLE")):
            self._notify(result)
            result["last_alert_at"] = now.isoformat()
        self._save(o["state_file"], result)
        line = f"provisioning_watch {result['state']} stranded={len(result['stranded'])}"
        if result["state"] == "UNREADABLE":
            line += f" error={result['error']}"
        self.stdout.write(line)
        for r in result["stranded"]:
            self.stdout.write(f"  {r['subdomain']} ({r['email']}) waiting {r['waiting_minutes']} min — {r['last_log'] or 'no provision log'}")
        # exit code mirrors the state so a wrapper/heartbeat can read it: 0 OK, 2 ALERT, 3 UNREADABLE
        raise SystemExit({"OK": 0, "ALERT": 2, "UNREADABLE": 3}[result["state"]])

    def _notify(self, result):
        to = getattr(settings, "OPS_ALERT_EMAIL", "")
        kind = {"ALERT": "ops_provisioning_alert", "UNREADABLE": "ops_provisioning_unreadable", "OK": "ops_provisioning_ok"}[result["state"]]
        ctx = {"r": result, "host": os.environ.get("DJANGO_ALLOWED_HOST", "").split(",")[0]}
        if to:
            mail.notify(to, kind, ctx)
        else:
            log.warning("provisioning_watch: OPS_ALERT_EMAIL unset — %s not e-mailed", result["state"])
        hook = getattr(settings, "OPS_ALERT_WEBHOOK_URL", "")
        if hook:
            try:
                requests.post(hook, json={"source": "billing/provisioning_watch", **{k: v for k, v in result.items() if k != "trace"}}, timeout=10)
            except Exception:  # noqa: BLE001
                log.exception("provisioning_watch: webhook post failed")

    @staticmethod
    def _load(path):
        try:
            with open(path) as f:
                return json.load(f)
        except Exception:  # noqa: BLE001 — first run / unreadable file = no prior state
            return {}

    @staticmethod
    def _save(path, data):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=1, default=str)
        os.replace(tmp, path)
