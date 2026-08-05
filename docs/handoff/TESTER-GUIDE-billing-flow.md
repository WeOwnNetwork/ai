# WeOwn billing + affiliate flow — tester guide

**Who this is for:** the WeOwn testing team — anyone testing the
customer signup → payment → instance → affiliate-split flow.

**Everything here is Stripe TEST mode.** No real money moves. Use the test card
`4242 4242 4242 4242`, any future expiry, any CVC, any postal code.

**Start here:** <https://billing.weown.dev>

---

## 1. Sign up as a customer (2 min)

1. If someone sent you a **referral link** (`https://billing.weown.dev/?ref=SOMECODE`),
   open that link — not the bare domain. The referral is remembered in your
   browser even if you leave and come back later.
2. Click **Create your account** → on the WeOwn sign-in screen choose **Register**.
3. Register with an email you can read (your `@weown.net` address or a personal
   one). Confirm the verification email, then sign back in.

## 2. Create an instance and pay (3 min)

4. Click **Create your AI instance**.
5. Pick a name — it becomes `yourname.weown.dev`. The form tells you live
   whether it's available (reserved and taken names are rejected).
6. **Continue to payment** → Stripe Checkout → card `4242 4242 4242 4242`.
7. You land on the welcome page. Your account page now lists the instance as
   **being set up** — provisioning is operator-run today (see §5), so expect a
   WeOwn person to flip it live shortly rather than instantly.

## 3. Become an affiliate (2 min, self-serve)

8. Click **Earn with WeOwn** in the top nav → **Become an affiliate**.
9. Choose your referral code (it tells you live whether it's free), read the
   agreement, type your full legal name, tick the box, **Sign and join**.
   Signing activates you immediately — no waiting on WeOwn.
10. Your referral link is shown straight away. Share it with the next tester —
    whoever signs up through it counts as your referral, and **you** become
    their tier-2 sponsor if they join as an affiliate too.

> Testing the chain properly: have tester A join, share A's link with tester B,
> have B join through it and then refer a paying customer. A earns tier‑2 on
> B's referral. That is the whole two-tier model in three clicks.

## 4. Watch the money (the point of the exercise)

11. When someone signs up through your link **and pays**, the invoice produces a
    split automatically. On your **Affiliate** page you'll see:
    - **paid** — transferred to your Stripe payout account already, and
    - **pending** — accrued, waiting for you to finish Stripe payout onboarding.
12. Splits are a share of **profit**, not the sticker price: payment minus the
    actual Stripe processing fee minus running costs (COGS), then tier-1 % to
    your referrer and tier-2 % to their sponsor.
13. **Attribution is frozen at signup.** Whoever referred that subscription keeps
    it; it is never re-pointed later. If you sign up under a different link next
    time, that new affiliate is credited for that new account.

## 5. What is automatic today, and what isn't

| Step | Today |
|---|---|
| Register, verify email, sign in | automatic (Keycloak self-registration) |
| Claim subdomain, availability check | automatic |
| Payment → subscription → entitlement | automatic (Stripe webhooks) |
| Affiliate attribution + split computation + audit trail | automatic |
| Payout transfer to affiliate | automatic **once** that affiliate finishes Stripe Connect onboarding |
| Non-payment → access suspended → payment → restored | automatic (identity flag) |
| **Instance provisioning** | **operator-run** — one idempotent command per instance; the customer sees "being set up" until it completes |
| Instance teardown | operator-run, records retained |

## 6. Reporting problems

Say what you did, what you expected, what you saw, plus the time. Useful detail:
the instance subdomain, the email you signed up with, and whether you used a
referral link. Anything money-related, include the invoice date from the Stripe
portal (**Manage billing** on your account page).

## 7. Notes for the WeOwn operator running this

- Register an affiliate:
  `create_affiliate <email> <code> [--parent <sponsor-code>] [--create-user]`
- Mint a payout onboarding link: `connect_onboarding <code>`
  (needs Connect enabled on the Stripe account first)
- See what needs provisioning: `pending_instances`
- Provision: `weown-fleet/scripts/provision-instance.sh <slug> --apply`
  (idempotent; one known manual step — creating the AnythingLLM admin key on
  first boot)
- Report the result back: `set_instance_status <subdomain> active`
- Change attribution (admins only): Django admin → Subscriptions → affiliate

All commands run on the billing droplet as:
`docker compose run --rm -T web python manage.py <command>`
