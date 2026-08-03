"""Replay unprocessed WebhookEvents from the ledger (payloads are plain JSON,
so this also recovers events that failed on a since-fixed bug without waiting
for Stripe's retry schedule)."""
from django.core.management.base import BaseCommand

from core.models import WebhookEvent
from core.views import _process_event


class Command(BaseCommand):
    help = "Re-run _process_event for every unprocessed WebhookEvent"

    def handle(self, *args, **options):
        for w in WebhookEvent.objects.filter(processed=False).order_by("received_at").iterator():
            try:
                event = {"type": w.event_type, "data": {"object": w.payload["data"]["object"]}}
                _process_event(event)
                w.processed, w.error = True, ""
            except Exception as exc:  # noqa: BLE001
                w.error = repr(exc)[:2000]
            w.save(update_fields=["processed", "error"])
            self.stdout.write(f"{w.stripe_event_id} {w.event_type} -> processed={w.processed} {w.error[:80]}")
