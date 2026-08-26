"""White-label branding on Affiliate (WO-Disc-1040 / A627).

Affiliates sell under their own brand and the billing funnel is the only
WeOwn-controlled surface a customer sees before paying. All four fields are
optional — blank falls back to WEOWN_BRAND — so this migration is additive and
changes nothing for existing affiliates until an operator fills them in.
"""
import django.core.validators
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0010_refund_clawback"),
    ]

    operations = [
        migrations.AddField(
            model_name="affiliate",
            name="display_name",
            field=models.CharField(
                blank=True, max_length=80,
                help_text="Brand shown to customers in the signup funnel (e.g. 'Vulcarian'). Empty = WeOwn.",
            ),
        ),
        migrations.AddField(
            model_name="affiliate",
            name="logo_url",
            field=models.URLField(
                blank=True,
                validators=[django.core.validators.URLValidator(schemes=["https"])],
                help_text="HTTPS URL of the affiliate's logo, shown in the billing header. HTTPS only — "
                          "an http:// logo would make the payment page mixed-content.",
            ),
        ),
        migrations.AddField(
            model_name="affiliate",
            name="primary_color",
            field=models.CharField(
                blank=True, max_length=7,
                validators=[django.core.validators.RegexValidator(
                    "^#[0-9A-Fa-f]{6}$", "Use a 6-digit hex colour such as #2563eb.")],
                help_text="Brand accent as #RRGGBB, used for buttons and links.",
            ),
        ),
        migrations.AddField(
            model_name="affiliate",
            name="support_email",
            field=models.EmailField(
                blank=True, max_length=254,
                help_text="Where this affiliate's customers should be told to get help. Empty = WeOwn support.",
            ),
        ),
    ]
