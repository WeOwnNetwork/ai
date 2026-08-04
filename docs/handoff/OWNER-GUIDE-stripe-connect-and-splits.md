# WeOwn payments & affiliate splits — owner's guide

**For:** the business owner and whoever handles WeOwn finance ops.
**Covers:** how money flows, the Stripe Connect decisions already made and why,
what changes for the production account, how the affiliate splits and COGS
work, who is allowed to change what, and what to watch for.

---

## 1. How the money flows

1. A customer signs up at **billing.weown.dev**, picks a name for their private
   AI instance, and subscribes — **$1,000/month**.
2. The full payment lands in the **WeOwn Stripe account**. WeOwn owns the
   customer, the invoice, and the funds.
3. Stripe deducts its processing fee (roughly 2.9% + 30¢ on card payments).
4. WeOwn's **running cost per instance (COGS)** is deducted — the droplet, the
   AI model usage, and whatever else you decide belongs in that number.
5. What's left is **profit on that invoice**. The affiliate splits are
   percentages of *that* number, not of the $1,000.
6. Each affiliate's share transfers automatically to their own Stripe account.
   WeOwn keeps the remainder.

**Worked example** at $1,000 with $40 COGS and 20% / 5% split rates:

| Line | Amount |
|---|---|
| Customer pays | $1,000.00 |
| Stripe processing fee | −$29.30 |
| WeOwn running cost (COGS) | −$40.00 |
| **Profit** | **$930.70** |
| Tier 1 — the referring affiliate (20%) | −$186.14 |
| Tier 2 — that affiliate's sponsor (5%) | −$46.53 |
| **WeOwn keeps** | **$698.03** |

Every one of those numbers is recorded per invoice and visible in the admin —
nothing is estimated after the fact.

---

## 2. The Stripe Connect decisions (already made, and why)

| Question | Choice | Why |
|---|---|---|
| Who collects payment? | **Buyers purchase from WeOwn** | WeOwn owns the customer relationship, the invoice and the funds; affiliates are paid afterwards |
| Payout shape | **Payouts split between sellers** | One $1,000 payment funds two payouts (tier 1 + tier 2) from the same charge |
| How affiliates create accounts | **Stripe-hosted onboarding** | Their ID and bank details go straight to Stripe, never through WeOwn — smallest possible compliance burden for us |
| How affiliates manage their account | **Express dashboard** | Stripe handles payout timing, bank changes and tax forms; WeOwn's own affiliate page explains *why* they earned |

Consequence worth knowing: because the money lands with WeOwn first, **refunds
and chargebacks are WeOwn's exposure**, not the affiliate's. If a customer
charges back after a split was paid, the affiliate has already been paid and
recovering it is a manual conversation.

---

## 3. Going live (what changes from the test setup)

The current system runs entirely in Stripe **test mode**. Live mode is a
separate world — nothing carries over automatically.

1. **Activate the Stripe account** for live payments (business details, bank
   account, tax ID). Stripe walks you through it.
2. **Enable Connect in live mode** with the same four answers from §2.
3. **Re-create the product** ("WeOwn Chat", $1,000/month) in live mode and note
   its new price ID.
4. **New API keys and a new webhook** endpoint pointing at
   `https://billing.weown.dev/webhooks/stripe/` with the same event list.
   These get stored by an engineer — they are secrets and never travel by chat
   or email.
5. **Every affiliate re-onboards.** Test-mode Connect accounts do not exist in
   live mode; each affiliate gets a fresh onboarding link.
6. **Fund flow check:** payouts come out of the WeOwn balance. Early on, watch
   that the balance covers the splits — Stripe holds new-account funds briefly
   before they're available.

---

## 4. The COGS number — what it is and who sets it

COGS = **what it costs WeOwn to run one instance for one month.** Today that's
mainly the server and the AI model usage. It is deducted before splits so that
affiliates share in *profit*, not revenue.

- It is stored **in cents** (e.g. `4000` = $40.00) to avoid rounding drift.
- It applies to every invoice paid **after** it is set.
- Raising it lowers every affiliate's cut; lowering it raises them. That is a
  commercial decision with a real effect on partner earnings — treat it as a
  policy change, not a config tweak.

**Recommendation:** review it quarterly against actual infrastructure and model
spend, and tell affiliates before it changes materially.

---

## 5. Changing the split rates

- Rates live in **Split configs** in the admin: a tier‑1 %, a tier‑2 %, and the
  COGS number.
- **You cannot edit an existing row — you add a new one.** The newest row
  applies to future invoices; old rows stay exactly as they were.
- That immutability is deliberate: an affiliate's past earnings can never be
  silently rewritten, and any dispute can be answered with the exact rates that
  applied on the day.
- Individual affiliates can also have a **personal override** (e.g. a 25%
  founding partner) without changing the global default.

**Who does this:** the finance/ops owner. It needs an admin login and is two
fields plus Save — no engineer required. Ask an engineer only if you want a new
*kind* of rule (e.g. tiered by volume, or different rates per product).

---

## 6. Affiliate attribution — the rules

- Attribution is captured **when the subscription is created** and frozen there.
- It is never re-derived later. Money already collected is never re-split.
- **Customers cannot change who referred them.** Only an admin can, on the
  subscription record — use this for genuine corrections, not for goodwill.
- If someone signs up a second account through a different affiliate's link,
  that second account is credited to the new affiliate. Referral links are
  remembered in the customer's browser between visits, so a link clicked days
  before signup still counts.
- Back-dating a concession (paying an affiliate for something outside these
  rules) is a **manual credit decision** — deliberately not automated, because
  retroactive splitting gets complicated and contentious fast.

---

## 7. Affiliates: from sign-up to getting paid

There are **two ways in**, and both end at the same signed agreement.

**A. Self-serve (the normal path — no WeOwn involvement)**

1. They register at billing.weown.dev like any customer.
2. They click **Earn with WeOwn** in the top nav → **Become an affiliate**.
3. They choose their own referral code (checked live for availability), read the
   agreement, type their full legal name and tick the box.
4. Signing **is** the activation — they're live immediately, with their referral
   link on screen.
5. If they arrived through someone else's referral link, that person is
   automatically recorded as their **tier-2 sponsor**. This is how the two-tier
   tree grows without anyone administering it.

**B. Operator-registered (for partners you recruit directly)**

1. A WeOwn operator runs one command with their email, their chosen code, and
   optionally their sponsor — it works even before that person's first login.
2. They still have to **sign the agreement** in the portal before any payout.

**Then, either way:** they complete Stripe's hosted onboarding (identity + bank
details), and splits transfer automatically on every paid invoice.

**What the signature captures:** the exact agreement text (fingerprinted, so it
can be proven unchanged), their typed name, their email, their IP address, and
the timestamp. It is stored read-only — nobody, including admins, can edit or
delete a signature. That is your evidence if a payout is ever disputed.

**No agreement, no payouts** — the system enforces it, not a person.

Earnings they haven't onboarded for still accrue and show as **pending** — they
are not lost; they transfer once onboarding completes.

> ⚠️ The agreement text currently published is a **placeholder marked
> non-binding**, for testing. Publishing the legally reviewed version is a
> prerequisite before real affiliates sign. It ships as a *new version* —
> earlier signatures stay intact against the text those people actually saw.

---

## 8. Tax — what to be aware of

Not tax advice; these are the things to raise with the accountant.

- **Affiliates are independent contractors**, not employees. In the US, Stripe
  can collect their tax details and issue **1099s** for Express accounts — worth
  enabling so WeOwn isn't chasing W‑9s by hand.
- **Splits are a business expense** for WeOwn (partner commission), not a
  reduction of revenue: WeOwn books the full $1,000 as revenue and the split as
  cost. Your bookkeeping should mirror that.
- **Sales tax / VAT on the $1,000 subscription** is a separate question from
  splits. If WeOwn owes tax on the sale, Stripe Tax can calculate and collect
  it. Decide this before live launch — retrofitting it across existing
  subscriptions is painful.
- **International affiliates** bring their own withholding and reporting rules.
  Check before onboarding the first non-US partner.
- The split math deducts the *actual* Stripe fee per invoice, so the profit
  figure in the ledger reconciles to the Stripe payout report.

---

## 9. What to watch, month to month

| Watch for | Why it matters | Where |
|---|---|---|
| Payouts stuck as **pending** | An affiliate never finished Stripe onboarding and thinks they're unpaid | Split payouts (status) |
| **No profit** rows | COGS is set higher than the margin — nobody earns | Split payouts (status) |
| Failed webhooks | A payment that didn't register as active access | Webhook events (processed) |
| Past-due subscriptions | Stripe is retrying a card; access continues until it gives up | Subscriptions (status) |
| Balance vs upcoming payouts | Payouts draw on the WeOwn balance | Stripe dashboard |
| Refunds after a split was paid | Affiliate was already paid; recovery is manual | Stripe dashboard |

---

## 10. Who can do what

| Task | Who |
|---|---|
| Change split rates or COGS | Finance/ops owner, in the admin (add a new config row) |
| Register a new affiliate / set their sponsor | Nobody needs to — affiliates self-serve. Operator command exists for partners you recruit directly |
| Correct an attribution | Admin only, on the subscription record |
| Issue a refund or a goodwill credit | Finance owner, in Stripe |
| Publish a new agreement version | Owner, after legal review |
| Anything involving API keys or secrets | Engineer only — never over chat or email |
