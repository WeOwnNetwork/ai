"""Free trial + customer click-wrap agreement.

Two changes that together let a customer start a 14-day trial under a signed
agreement:

1. `Subscription.trial_end` and the `trialing` status — both entitled states,
   because a trial with no working instance is not a trial.
2. `ContractTemplate.kind` + `CustomerContract` — the affiliate agreement
   machinery generalised to cover customers. The old single-active-template
   constraint was GLOBAL, so publishing a customer agreement would have
   silently deactivated the affiliate one; it becomes one-active-PER-KIND, and
   version uniqueness becomes per-kind too.

Seeds a placeholder customer agreement so the checkout gate has something to
show on a fresh deployment. It is deliberately a DB row: the business replaces
the wording by adding a NEW ContractTemplate row in admin — no deploy, and
existing signatures keep pointing at the exact text they accepted.
"""
from django.db import migrations, models
import django.db.models.deletion

PLACEHOLDER_CUSTOMER = """WeOwn Chat Service Agreement — v0.1 (PLACEHOLDER)

This placeholder is in force until WeOwn publishes the legal-approved
agreement as a new version. Replace it before taking live payments.

1. Service. WeOwn provides a private AI assistant instance on infrastructure
   WeOwn operates, reachable at the subdomain you choose, together with the
   embeddable website chat widget.
2. Trial and fees. If a free trial is offered at signup, no charge is made
   during the trial. Your payment method is charged the subscription fee shown
   at checkout when the trial ends, and monthly thereafter until cancelled.
3. Term and cancellation. The initial term is 90 days from the first charge.
   You may cancel at any time; cancellation takes effect at the end of the
   period already paid for, and fees already collected are not refunded except
   where required by law.
4. Your content. Documents you upload remain yours. They are stored on your
   instance and are not used to train third-party models; WeOwn routes model
   requests through zero-data-retention providers.
5. Acceptable use. You are responsible for the content you upload and for what
   your website visitors are told by the assistant. The assistant produces
   general information, not professional advice.
6. Availability and liability. The service is provided on a commercially
   reasonable-efforts basis. WeOwn's total liability is limited to the fees you
   paid in the three months before the claim.
7. Changes. WeOwn may publish a revised agreement; continued use after the
   revision takes effect constitutes acceptance.
"""


def seed_customer_agreement(apps, schema_editor):
    ContractTemplate = apps.get_model("core", "ContractTemplate")
    # Existing rows pre-date `kind` and are all affiliate agreements. The field
    # default covers them, but be explicit — a mislabelled agreement is the
    # kind of thing nobody notices until a dispute.
    ContractTemplate.objects.filter(kind="").update(kind="affiliate")
    if not ContractTemplate.objects.filter(kind="customer").exists():
        ContractTemplate.objects.create(
            kind="customer", version="0.1", body_md=PLACEHOLDER_CUSTOMER, active=True,
        )


def unseed(apps, schema_editor):
    ContractTemplate = apps.get_model("core", "ContractTemplate")
    # Only remove the untouched placeholder — never a template someone signed.
    ContractTemplate.objects.filter(
        kind="customer", version="0.1", customercontract__isnull=True,
    ).delete()


class Migration(migrations.Migration):

    dependencies = [("core", "0007_splitpayout_error_and_more")]

    operations = [
        # ── trial ──────────────────────────────────────────────────────────
        migrations.AddField(
            model_name="subscription",
            name="trial_end",
            field=models.DateTimeField(
                blank=True, null=True,
                help_text="When the free trial converts to a paid charge (empty if there was no trial)",
            ),
        ),
        migrations.AlterField(
            model_name="subscription",
            name="status",
            field=models.CharField(
                choices=[("active", "Active"), ("trialing", "Trialing"),
                         ("past_due", "Past Due"), ("canceled", "Canceled"),
                         ("incomplete", "Incomplete")],
                default="incomplete", max_length=16,
            ),
        ),
        # ── contract templates become kind-scoped ──────────────────────────
        # Drop the old constraints FIRST: `version` carried a field-level
        # unique=True and `active` a global partial-unique, both of which the
        # per-kind replacements would otherwise collide with.
        migrations.RemoveConstraint(
            model_name="contracttemplate", name="one_active_contract_template",
        ),
        migrations.AlterField(
            model_name="contracttemplate",
            name="version",
            field=models.CharField(max_length=20),
        ),
        migrations.AddField(
            model_name="contracttemplate",
            name="kind",
            field=models.CharField(
                choices=[("affiliate", "Affiliate agreement"), ("customer", "Customer agreement")],
                db_index=True, default="affiliate", max_length=16,
                help_text="Who signs this — affiliates at join, customers at checkout",
            ),
        ),
        migrations.AddConstraint(
            model_name="contracttemplate",
            constraint=models.UniqueConstraint(fields=("kind", "version"), name="one_version_per_kind"),
        ),
        migrations.AddConstraint(
            model_name="contracttemplate",
            constraint=models.UniqueConstraint(
                condition=models.Q(("active", True)), fields=("kind",),
                name="one_active_template_per_kind",
            ),
        ),
        # ── customer signatures ────────────────────────────────────────────
        migrations.CreateModel(
            name="CustomerContract",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("body_sha256", models.CharField(max_length=64)),
                ("signed_name", models.CharField(help_text="Name typed by the signer", max_length=120)),
                ("signer_email", models.EmailField(max_length=254)),
                ("signer_ip", models.GenericIPAddressField(blank=True, null=True)),
                ("user_agent", models.CharField(blank=True, max_length=300)),
                ("signed_at", models.DateTimeField(auto_now_add=True)),
                ("customer", models.ForeignKey(
                    on_delete=django.db.models.deletion.PROTECT, related_name="contracts",
                    to="core.customer")),
                ("template", models.ForeignKey(
                    on_delete=django.db.models.deletion.PROTECT, to="core.contracttemplate")),
            ],
        ),
        migrations.AddConstraint(
            model_name="customercontract",
            constraint=models.UniqueConstraint(
                fields=("customer", "template"), name="one_customer_signature_per_version",
            ),
        ),
        migrations.RunPython(seed_customer_agreement, unseed),
    ]
