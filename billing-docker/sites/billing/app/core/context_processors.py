"""Nav context: the customer's instance link and affiliate status are needed on
every page, not just the dashboard.

`branding` is the white-label chokepoint (WO-Disc-1040 / A627): affiliates sell
under their own brand, and the billing funnel is the ONLY WeOwn-controlled
surface an end customer sees before paying. Every pre-purchase page therefore
renders the referring affiliate's brand, not WeOwn's.
"""
import re

from .models import WEOWN_BRAND, Affiliate, Customer

#: Re-validated here rather than trusted from the DB: model validators do not
#: run on a bare .save(), and the value lands in a CSS custom property where
#: Django's HTML autoescaping gives no protection.
_HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")


def nav(request):
    if not request.user.is_authenticated:
        return {}
    customer = Customer.objects.filter(user=request.user).only("instance_url", "instance_status").first()
    return {
        "nav_instance_url": customer.instance_url if customer else "",
        "nav_is_affiliate": Affiliate.objects.filter(user=request.user).exists(),
    }


def _referring_affiliate(request):
    """The affiliate whose brand this request should wear, or None for WeOwn.

    Two sources, in order, because the referral moves as the visitor progresses:

    1. ``session['ref_code']`` — set by ReferralCodeMiddleware from ``?ref=``.
       Covers the whole anonymous funnel: landing, sign-in, agreement, checkout.
    2. the signed-in customer's ``referred_by`` — `subscribe` POPS the session
       key once it has been recorded on the Customer, so without this fallback
       the brand would revert to WeOwn at the success page and portal, i.e.
       exactly when the customer is deciding whether they were dealt with by
       the company they thought they bought from.

    Only ACTIVE affiliates brand a page: an unsigned or revoked affiliate must
    not be able to dress the payment funnel in their name.
    """
    code = request.session.get("ref_code")
    if code:
        aff = Affiliate.objects.filter(code=code, active=True).first()
        if aff:
            return aff
    user = getattr(request, "user", None)
    if user is not None and user.is_authenticated:
        customer = (Customer.objects.filter(user=user)
                    .select_related("referred_by").only("referred_by").first())
        if customer and customer.referred_by and customer.referred_by.active:
            return customer.referred_by
    return None


def branding(request):
    """`brand` on every template: the affiliate's identity, or WeOwn's."""
    aff = _referring_affiliate(request)
    brand = dict(aff.brand) if aff else dict(WEOWN_BRAND)

    # Defence in depth — a colour that is not a literal 6-digit hex never
    # reaches the stylesheet, whatever is in the database.
    if not _HEX.match(brand.get("primary_color") or ""):
        brand["primary_color"] = WEOWN_BRAND["primary_color"]
    if not (brand.get("logo_url") or "").startswith("https://"):
        brand["logo_url"] = ""

    return {"brand": brand}
