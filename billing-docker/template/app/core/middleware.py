class ReferralCodeMiddleware:
    """Capture ?ref=<code> into the session so the referral survives the OIDC
    round-trip and lands on the Customer at checkout time."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        ref = request.GET.get("ref")
        if ref:
            request.session["ref_code"] = ref[:32]
        return self.get_response(request)
