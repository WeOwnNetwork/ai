"""Report provisioning outcome back into billing (operator/worker side).

    set_instance_status <subdomain> active --log "provisioned by fleet run 123"
"""
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from core.models import Instance


class Command(BaseCommand):
    help = "Update an instance's lifecycle status (and optionally its provisioning log)"

    def add_arguments(self, parser):
        parser.add_argument("subdomain")
        parser.add_argument("status", choices=[c for c, _ in Instance.Status.choices])
        parser.add_argument("--log", default="")

    def handle(self, *args, **o):
        inst = Instance.objects.filter(subdomain=o["subdomain"]).first()
        if not inst:
            raise CommandError(f"No instance with subdomain {o['subdomain']}")
        inst.status = o["status"]
        if o["log"]:
            inst.provision_log = o["log"][:5000]
        if o["status"] == Instance.Status.ACTIVE and not inst.provisioned_at:
            inst.provisioned_at = timezone.now()
        if o["status"] == Instance.Status.DESTROYED and not inst.destroyed_at:
            inst.destroyed_at = timezone.now()
        inst.save()
        self.stdout.write(f"{inst.subdomain} -> {inst.status}")
