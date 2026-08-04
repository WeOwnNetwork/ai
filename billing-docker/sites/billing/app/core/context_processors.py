"""Nav context: the customer's instance link and affiliate status are needed on
every page, not just the dashboard."""
from .models import Affiliate, Customer


def nav(request):
    if not request.user.is_authenticated:
        return {}
    customer = Customer.objects.filter(user=request.user).only("instance_url", "instance_status").first()
    return {
        "nav_instance_url": customer.instance_url if customer else "",
        "nav_is_affiliate": Affiliate.objects.filter(user=request.user).exists(),
    }
