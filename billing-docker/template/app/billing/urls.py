from django.contrib import admin
from django.urls import include, path

from core import views

urlpatterns = [
    path("healthz", views.healthz),
    path("admin/", admin.site.urls),
    path("oidc/", include("mozilla_django_oidc.urls")),
    path("", views.home, name="home"),
    path("subscribe/", views.subscribe, name="subscribe"),
    path("subscribe/success/", views.subscribe_success, name="subscribe_success"),
    path("portal/", views.customer_portal, name="portal"),
    path("suspended/", views.suspended, name="suspended"),
    path("affiliate/", views.affiliate_home, name="affiliate_home"),
    path("affiliate/contract/", views.affiliate_contract, name="affiliate_contract"),
    path("webhooks/stripe/", views.stripe_webhook, name="stripe_webhook"),
]
