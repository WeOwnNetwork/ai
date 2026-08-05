"""List instances awaiting provisioning, as TSV for the fleet-side worker.

The billing droplet deliberately holds NO fleet credentials — provisioning runs
on the operator side (weown-fleet), which reads this over SSH and reports back
with set_instance_status.
"""
from django.core.management.base import BaseCommand

from core.models import Instance


class Command(BaseCommand):
    help = "TSV: id, subdomain, email, display_name for instances needing provisioning"

    def add_arguments(self, parser):
        parser.add_argument("--status", default=Instance.Status.PROVISIONING)

    def handle(self, *args, **o):
        for i in Instance.objects.filter(status=o["status"]).select_related("customer__user"):
            self.stdout.write(
                f"{i.pk}\t{i.subdomain}\t{i.customer.user.email}\t{i.display_name}"
            )
