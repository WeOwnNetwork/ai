from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0006_subscription_affiliate_alter_subscription_customer_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='splitpayout',
            name='error',
            field=models.TextField(blank=True),
        ),
        migrations.AlterField(
            model_name='splitpayout',
            name='status',
            field=models.CharField(choices=[('paid', 'Paid'), ('skipped_no_account', 'Skipped — affiliate has no Connect account'), ('skipped_no_profit', 'Skipped — no profit on this invoice'), ('failed', 'Transfer failed — see error')], max_length=24),
        ),
    ]
