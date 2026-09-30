# ADR-007: Billing Keycloak registration vs sign-in + no-instance paywall

**Status**: Accepted  
**Version**: v4.4.3.1 (#WeOwnVer — Season 4, month 4 (Sep), ISO-week offset 3 of Sep, iteration 1; per [`docs/VERSIONING_WEOWNVER.md`](../docs/VERSIONING_WEOWNVER.md): 2026-09-15 = ISO W38; first ISO week containing 2026-09-01 = W36; offset = 38 − 36 + 1 = 3)  
**Date**: 2026-09-15  
**Deciders**: `@SinachPat` (implementation), WeOwnChat onboarding  
**Related**: mozilla-django-oidc auth on billing; Stripe trial (`STRIPE_TRIAL_DAYS`); landing-purchase CTAs; PR WeOwnNetwork/ai#252

---

## Context

First-time WeOwnChat customers were dropped on Keycloak's **login** screen and asked to find Register themselves. Product requires:

1. Landing **Create account** → Keycloak **registrations**
2. Landing **Sign in** → Keycloak **auth**
3. After SSO, no unpaid live Harbor View space — billing home blocks until `new_instance` / trial / pay
4. Marketing promises a **14-day** trial with card on file (the recorded commercial default, `copier.yaml` `trial_period_days`, #169)

mozilla-django-oidc only knows the authorize (login) endpoint. Keycloak exposes registrations as a sibling URL with the same query string and shared callback.

## Decision

1. **`OIDCRegistrationRequestView`** (subclass of `OIDCAuthenticationRequestView`) at `/oidc/register/` (`oidc_registration_init`) swaps `/protocol/openid-connect/auth` → `/protocol/openid-connect/registrations` while reusing mozilla session `oidc_states` (nonce, optional PKCE verifier) and `/oidc/callback/`.
2. **`GET /register/`** remains a thin alias that redirects to `oidc_registration_init` so landing URLs (`https://billing.weown.dev/register/`) stay stable.
3. **No-instance paywall** on billing home is a **non-modal** blocking overlay (`role="dialog"` without `aria-modal`) with Create-instance CTA and an in-card Sign out, so assistive tech can still leave the wrong account.
4. **`STRIPE_TRIAL_DAYS=14`** is set in this render's `compose.prod.yaml` and is the authoritative trial length for production messaging, matching the `copier.yaml` default. Infisical must **not** set the same key (override risk under `infisical run`).
5. **Deploy order**: billing (with `/register/` + paywall) before landing static that points Create account at `/register/`.

## Consequences

- Keycloak realm must allow user registration for the `billing` client; callback URI must match.
- Enabling `OIDC_USE_PKCE` is supported by the upstream mozilla view; register alias does not re-implement PKCE.
- Harbor View entitlement remains separate (`subscription_active`); unpaid users simply never receive an instance URL until checkout succeeds.
- **Realm self-registration blast radius, checked before enabling it**: turning on self-registration for the `weown-chat` realm lets anyone create a *realm* account, not just a `billing` one — every client trusting that realm is affected. In this repo, the only other realm-relying client is the per-tenant AnythingLLM customer dashboard (`anythingllm-docker/template/dashboard/server.js`), and it gates SSO login on Keycloak **group** membership (`OIDC.group`, a per-tenant group claim) independent of registration — a bare self-registered account carries no groups and is rejected with 403 ("this account is not authorized for this dashboard") before it reaches any tenant data. Tenant client/group provisioning itself lives in `weown-fleet` (`kc-provision-tenant.sh`), a separate repository not covered by this review — confirm there that no tenant client is configured to admit any realm user without an explicit group/role check before flipping registration on in production.

## Compliance

| Concern | How this ADR addresses it |
|---|---|
| Authn initiation clarity (PR.AC) | Separate registrations vs auth endpoints; shared callback/state contract |
| Deploy / config integrity (CM) | Document Infisical vs compose ownership of `STRIPE_TRIAL_DAYS`; deploy ordering |
| Accessibility of blocking UX | Non-modal overlay + Sign out inside the card |
