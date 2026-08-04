# Reading the money in Stripe — owner's walkthrough

**For:** the business owner and whoever handles WeOwn finance ops.
**Companion to:** the splits & Connect guide (how the money is *decided*). This
one is about *seeing* it — where to log in, what each screen means, and how to
answer "did this person pay, and what did we keep?"

---

## 1. Logging in

1. Go to <https://dashboard.stripe.com> and sign in with your WeOwn Stripe
   account. Turn on two-factor authentication if you haven't — this account can
   move money.
2. **Check the mode toggle.** Stripe has two completely separate worlds:
   - **Test mode / Sandbox** — everything the team is testing now. Fake cards,
     fake money, safe to click anything.
   - **Live mode** — real customers, real money.
   They share nothing: a customer in test does not exist in live. If a payment
   you expect is "missing", check the toggle first — it is the single most
   common confusion.

---

## 2. The screens that matter

### Home

Gross volume, net balance, and what's about to pay out to your bank. Good for
"how are we doing", not for answering questions about one customer.

### Payments

Every charge. Click one to see the customer, the amount, the **fee Stripe took**,
and the **net** that reached WeOwn. Statuses worth knowing:

- **Succeeded** — money captured.
- **Failed** — card declined; Stripe will retry a subscription charge on its own
  schedule and email the customer.
- **Refunded / partially refunded** — you (or someone) sent money back.
- **Disputed** — the customer told their bank it was wrong. See §5.

### Customers

One row per paying customer, with their subscriptions, invoices and payment
methods. This is where you answer "is this person actually paying us?"

### Subscriptions

The recurring plans themselves — who's **active**, **past due** (a payment
failed and Stripe is retrying), or **canceled**. WeOwn's own system reads these
same events, so what you see here matches what the customer sees in their
account.

### Connect → Accounts

Your **affiliates**. Each row is one affiliate's payout account. Watch for:

- **Restricted / information needed** — they started onboarding but didn't
  finish, so their money is accruing but not transferring.
- **Complete** — transfers flow automatically.

### Connect → Transfers

Every affiliate split that actually moved, with the invoice it came from.
Transfers from the same customer payment are grouped together, so a $1,000
invoice shows its tier‑1 and tier‑2 payouts side by side.

### Balance → Payouts

Money moving from Stripe to WeOwn's bank account, on Stripe's schedule.
"Balance" is what Stripe is holding; "payout" is the bank transfer.

---

## 3. Answering the three questions you'll actually be asked

**"Did this customer pay?"**
Customers → search their email → look at Subscriptions (active?) and Invoices
(paid?). The WeOwn admin shows the same answer under Subscriptions.

**"What did we keep on that sale?"**
Payments → open the charge → note the amount and the fee. Then WeOwn admin →
Split payouts → find that invoice: it shows gross, the same Stripe fee, the
running cost deducted, the profit, and each affiliate's cut. What WeOwn keeps is
profit minus those cuts.

**"Why hasn't this affiliate been paid?"**
Connect → Accounts → find them. If **restricted**, they haven't finished
onboarding — their earnings show as *pending* in WeOwn and transfer the moment
they do. If **complete**, check Connect → Transfers for the invoice.

---

## 4. Where WeOwn's own admin is better than Stripe

Stripe knows about money. It does **not** know about affiliates, tiers, or your
cost per instance. For anything about *why* a number is what it is, use the WeOwn
admin:

| Question | Look in |
|---|---|
| Who referred this customer, at what tier | WeOwn admin → Subscriptions |
| The full profit math on one invoice | WeOwn admin → Split payouts |
| Current split rates and running cost | WeOwn admin → Split configs |
| Whether an affiliate signed the agreement | WeOwn admin → Affiliate contracts |
| Whether a payment registered as access | WeOwn admin → Webhook events |

---

## 5. Things to watch for

- **Disputes (chargebacks).** The customer's bank pulls the money back and
  Stripe charges a dispute fee. Because WeOwn collects the payment and pays
  affiliates afterwards, **an affiliate may already have been paid on a disputed
  sale** — recovering that is a manual conversation, not an automatic reversal.
  Respond to disputes promptly in Stripe; there's a deadline.
- **Past-due subscriptions.** Stripe retries on its own for a while. Access
  continues during retries and is cut automatically only when Stripe gives up —
  that's deliberate, so a temporarily-declined card doesn't lock out a paying
  customer.
- **Restricted Connect accounts** that never complete onboarding — someone is
  waiting for money and may not know why.
- **Balance vs upcoming payouts.** Affiliate transfers draw on the WeOwn
  balance. New accounts have a holding period before funds are available, so
  early on make sure the balance covers what's owed.
- **Refunds.** Refunding a customer does not claw back a split that already
  paid. Check Split payouts before refunding a sale with an affiliate on it.
- **Test vs live confusion.** Before reporting anything as a real number, check
  the mode toggle.

---

## 6. Who to call

- **A number looks wrong** (split, profit, rate) → WeOwn engineering; the audit
  trail per invoice makes this quick to settle.
- **Changing split rates or the running-cost figure** → you can do it yourself
  in the WeOwn admin (add a new config row — see the splits guide).
- **Anything involving API keys, webhooks, or Stripe account settings** →
  engineering. Never share keys over chat or email.
