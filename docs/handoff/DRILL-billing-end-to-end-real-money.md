# Drill — end-to-end real-money test: buy → trial → charge → split → refund

**Purpose.** Prove the whole commercial path with real money before a customer
touches it. Runs against a **cheap product** ($1–$5) in the same live Stripe
account that will sell the $1,000 product, because test mode does not exercise
the parts that actually break: real Connect payouts, real balance timing, real
fee arithmetic, real webhook delivery.

**Who runs it.** An operator with Stripe dashboard access + the ability to
restart the billing stack. ~30 minutes of work, spread over 14 days of waiting
(or minutes, using Stripe's trial-end shortcut in step 5).

> ⚠️ **Reversal (step 8) is NOT built yet.** Refund → affiliate clawback is a
> P1 item; today a refund reverses WeOwn's revenue but leaves the affiliate
> paid. Run steps 1–7 now; step 8 documents what to observe so the gap is
> measured rather than assumed, and becomes a pass/fail step when the clawback
> lands. Prior art for the exposure: `OWNER-GUIDE-stripe-connect-and-splits.md` §Refunds.

---

## 0. Pre-flight

| Check | How | Expected |
| --- | --- | --- |
| Which product is the site selling? | `STRIPE_PRICE_ID` in Infisical | the DRILL price, not the $1,000 one |
| Trial length | `STRIPE_TRIAL_DAYS` in compose env | `14` (or the value under test) |
| Split rates + COGS | Django admin → Split configs → latest row | **matches the agreed numbers** — see the warning below |
| Customer agreement published | Django admin → Contract templates → kind=customer, active | exactly one row |
| Webhooks reaching us | Stripe → Developers → Webhooks → the billing endpoint | recent 200s, no failures |

> 🚨 **Do not run the drill until the split numbers are settled.** As shipped,
> the seeded row is **tier1 20% / tier2 5% / COGS $0**, while the vault's
> Affiliate Split Terms says **50/35/15 on net profit**. Whatever the drill pays
> out is what the code believes; if that is the wrong number, you have proven
> the plumbing and mispaid a real person. Set the `SplitConfig` row first.

---

## 1. Point the deployment at the drill product

► **RUN FROM: your Mac** — 🔑 PROMPTS: none (Infisical CLI already logged in)

```bash
cd ~/projects/ai/billing-docker/sites/billing && grep -n "STRIPE_TRIAL_DAYS" docker/compose.prod.yaml
```

Set `STRIPE_PRICE_ID` to the drill price in Infisical (UI or CLI), then bounce
the app so the entrypoint re-fetches secrets:

► **RUN FROM: the billing droplet** — 🔑 PROMPTS: none (key-based ssh)

Substitute your own ssh alias for the billing host (this repo is public, so the
fleet's host aliases are not written down here — see the operator's `~/.ssh/config`).

```bash
ssh <BILLING_DROPLET_HOST> 'cd /opt/billing && docker compose restart app && sleep 20 && docker compose logs --tail=20 app | grep -i "listening\|error"'
```

---

## 2. Sign up as a customer (through an affiliate link)

1. Open `https://billing.weown.dev/?ref=<affiliate-code>` in a private window.
   Using the ref link is the point — attribution is frozen at checkout and
   cannot be added afterwards.
2. Sign in with a **test customer** Keycloak account (not your own admin login).
3. You are sent to **`/agreement/`**. Read it, type a full name, tick the box.
   ✅ **Expect:** you cannot reach the instance form without this.
4. Choose a subdomain → **"Start my 14-day free trial"**.
5. Enter a **real card**. ✅ **Expect: $0.00 due today.**

**Verify:**

```
Django admin → Customer contracts   → one row, correct name/IP/hash
Django admin → Subscriptions        → status = trialing, trial_end ≈ now + 14d
Django admin → Webhook events       → checkout.session.completed + customer.subscription.created, processed
Stripe → Customers → the customer   → subscription "Trialing", card attached
```

---

## 3. Confirm the trial pays nobody

This is the step the whole trial design hinges on.

```
Django admin → Split payouts → filter by the trial invoice
```

✅ **Expect: NO rows at all** for the $0 trial invoice. A `skipped_no_profit`
row would also be wrong here — the invoice must not reach the split maths.
Cross-check the app log for `is zero-amount (trial or credit) — no splits computed`.

❌ **If a transfer went out:** stop the drill. Refund it manually in Stripe and
file a P0 — an affiliate has been paid commission on money nobody paid.

---

## 4. Confirm the instance actually works during the trial

The trial is worthless if the product is locked. Log into the provisioned
instance as the customer. ✅ **Expect:** it loads (trialing is an entitled
state), Keycloak shows `subscription_active=true` on the user.

---

## 5. Force the trial to end (don't wait 14 days)

Stripe → the subscription → **Actions → End trial now**. This bills the first
real invoice immediately.

✅ **Expect within ~1 minute:**

```
Stripe        → invoice paid for the drill amount
Subscriptions → status = active, trial_end EMPTY (not a stale date)
Webhook events→ invoice.paid + customer.subscription.updated, processed=true
```

---

## 6. Confirm the split fired correctly

```
Django admin → Split payouts → the new invoice
```

Check the arithmetic by hand, once, on paper:

```
profit = amount_paid − actual Stripe fee (from the charge's balance transaction) − COGS
cut    = profit × tier %
```

✅ **Expect:** a `paid` row per leg with a real `stripe_transfer_id`, and
tier-2 present only if the affiliate has a sponsor. Confirm the money landed:
Stripe → Connect → the affiliate's account → Transfers.

⚠️ A `skipped_no_account` row means the affiliate never finished Connect
onboarding — that is a correct outcome, not a bug, but the money is owed and
unpaid. Chase the onboarding, then use the retry path.

---

## 7. Cancel and confirm suspension

Cancel the subscription in Stripe.

✅ **Expect:** `Subscriptions.status = canceled`, Keycloak
`subscription_active=false`.

⚠️ **KNOWN GAP (P1):** the instance dashboard authorizes on the `groups` claim
and **never reads `subscription_active`**, so the cancelled customer's instance
keeps working. Record what you observe; this step becomes pass/fail when
entitlement enforcement lands.

---

## 8. Refund and observe the clawback gap

Refund the drill charge in Stripe.

**Today's expected (wrong) behaviour:** WeOwn's revenue reverses; the
affiliate's transfer does **not**. Record:

- the refunded amount,
- the affiliate transfer that stayed out,
- whether any `charge.refunded` webhook was received at all (there is no
  handler, so the event should appear unprocessed or unhandled).

When the P1 clawback ships, this step becomes: ✅ reversal rows appear for every
leg, proportional to the refund, and the net position returns to zero.

---

## Pass criteria (steps 1–6)

- [ ] Checkout is impossible without a recorded customer signature
- [ ] Card collected, $0 charged at signup, subscription `trialing`
- [ ] Zero split rows for the $0 trial invoice
- [ ] Instance usable during the trial
- [ ] Trial end produces a real charge, status `active`, `trial_end` cleared
- [ ] Split rows `paid` with real transfer ids, arithmetic matches by hand
- [ ] Every webhook event `processed=true`, no 500s in the Stripe dashboard

## Rollback

Point `STRIPE_PRICE_ID` back at the live price and restart. Refund any drill
charges. Drill customers/subscriptions can stay — they are real records of a
real (tiny) transaction, and deleting them would falsify the ledger.
