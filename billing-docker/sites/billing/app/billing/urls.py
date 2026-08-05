from django.contrib import admin
from django.urls import include, path

from core import views

urlpatterns = [
    path("healthz", views.healthz),
    path("admin/", admin.site.urls),
    path("oidc/", include("mozilla_django_oidc.urls")),
    path("", views.home, name="home"),
    path("subscribe/", views.subscribe, name="subscribe"),
    path("instances/new/", views.new_instance, name="new_instance"),
    path("instances/check/", views.check_subdomain, name="check_subdomain"),
    path("subscribe/success/", views.subscribe_success, name="subscribe_success"),
    path("portal/", views.customer_portal, name="portal"),
    path("suspended/", views.suspended, name="suspended"),
    path("affiliate/", views.affiliate_home, name="affiliate_home"),
    path("affiliate/join/", views.affiliate_join, name="affiliate_join"),
    path("affiliate/payouts/", views.connect_payouts, name="connect_payouts"),
    path("affiliate/check/", views.check_affiliate_code, name="check_affiliate_code"),
    path("affiliate/contract/", views.affiliate_contract, name="affiliate_contract"),
    path("webhooks/stripe/", views.stripe_webhook, name="stripe_webhook"),
]
