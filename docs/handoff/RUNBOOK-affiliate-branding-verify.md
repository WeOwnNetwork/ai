# Runbook — verify an affiliate's white-label branding (create → render → stored-row)

For every new or edited affiliate row (Larry/Volcarian, demo rows, all future ones).
Interpretive canon (what an unbranded page does and does not prove, the don't-re-create
rule) lives in the WeOwn vault register (A627); this file is the **runnable** half and
must track the deploy — update it when container names, the command, or the render
pipeline change.

## Why this order

`create_affiliate` runs `full_clean`, so a malformed hex colour or non-https logo URL
fails **loudly at the terminal** — a printed receipt rules out a bad write. The render
layer (`app/core/context_processors.py`) re-validates at request time and **silently
falls back to WeOwn defaults**, so a bad value written via Django admin (where model
validators do not run on a bare `.save()`) silently *un-brands* the page. Consequence:
an unbranded page is ambiguous between "row missing" and "row present, admin-written bad
values" — resolve it by reading the stored row, **never by re-creating**.

> ⚠️ Every `manage.py` invocation goes through `/opt/weown_billing/entrypoint-infisical.sh`
> (the compose entrypoint): secrets are injected per-process by `infisical run`, so a bare
> `docker exec … python manage.py …` dies on `KeyError: 'DJANGO_SECRET_KEY'`
> (measured 2026-08-30).

## 1. Create (write receipt)

```bash
ssh weown-billing 'docker exec weown_billing-web-1 /opt/weown_billing/entrypoint-infisical.sh \
  python manage.py create_affiliate \
  <email> <code> --create-user \
  --display-name "<Brand>" --logo-url "https://<logo>" \
  --primary-color "#RRGGBB" --support-email "<support@brand>"'
```

Success prints `created: <code> (user <email>, …, brand=<Brand>)` — that line is the
receipt; it echoes the stored brand. A validation failure raises here and nothing is
written. Prefer this command over Django admin for all brand-field edits.

## 1b. Activate (the step a fresh row ALWAYS needs)

`create_affiliate` writes `active=False` — `Affiliate.active` defaults to False
(`app/core/models.py:134`, *"Only set after their contract is signed"*), and the render
layer filters on it: `_referring_affiliate()` looks up
`Affiliate.objects.filter(code=…, active=True)` (`app/core/context_processors.py:47`).

**So step 2 fails on every brand-new row until it is activated**, and it fails in the
one way this runbook warns about — by rendering WeOwn branding, indistinguishable from
"row missing". Measured 2026-08-31 on `demo-brand`: the create receipt was clean, the
render verify showed WeOwn defaults, and only an activation flip fixed it.

Read the receipt from step 1: it ends `active=False … — they must sign the agreement at
/affiliate/ to activate`. Two ways forward, and they are not equivalent:

- **Intended path (real affiliates):** they sign the agreement at
  `https://billing.weown.dev/affiliate/`, which sets `active=True` and creates the
  contract row. Their branded link only works after they sign — say so when you send it.
- **Operator flip (demo/throwaway rows only):**

  ```bash
  ssh weown-billing 'docker exec weown_billing-web-1 /opt/weown_billing/entrypoint-infisical.sh \
    python manage.py shell -c "
  from core.models import Affiliate
  a = Affiliate.objects.get(code=\"<code>\"); a.active = True; a.save()
  print(a.code, a.active)"'
  ```

  ⚠️ This **bypasses the contract gate** — no signature, no contract row, and a payout
  path opens the moment a sale lands (the live exhibit behind WO-Disc-1045: activation is
  one shell command with no contract check). Use it only for a tracked throwaway with a
  named teardown owner, never to shortcut a real affiliate onto the money path.

## 2. Render verify (the proof step)

Branding keys off **referral context** — a bare visit shows WeOwn branding BY DESIGN,
and only `active=True` affiliates brand a page (step 1b). Verify **through the referral
link**:

```bash
curl -s "https://billing.weown.dev/?ref=<code>" -c /tmp/ref.jar -o /dev/null \
  && curl -s -b /tmp/ref.jar "https://billing.weown.dev/" | grep -o '<Brand>\|#RRGGBB' | sort | uniq -c
```

(The `?ref=` visit sets `session['ref_code']` via middleware; the second request renders
with it. A browser screenshot through the `?ref=` link is the customer-facing proof —
take any screenshot **through the link**, never on a bare URL.)

## 3. Stored-row read (only if 1 and 2 disagree)

Read-only probe — resolves the unbranded-page ambiguity without mutating anything:

```bash
ssh weown-billing 'docker exec weown_billing-web-1 /opt/weown_billing/entrypoint-infisical.sh \
  python manage.py shell -c "
from core.models import Affiliate
a = Affiliate.objects.filter(code=\"<code>\").first()
print(\"MISSING\" if a is None else (a.code, a.active, a.display_name, a.logo_url, a.primary_color, a.support_email))"'
```

- `MISSING` → the create genuinely did not land — re-run step 1.
- Row present, fields populated, page still unbranded → check `active` **first; on a
  fresh row that is almost always the answer** (step 1b — only active affiliates brand).
  Then check the render fallbacks (non-https logo → dropped; non-`#RRGGBB` colour →
  WeOwn default). Fix the **value** via step 1's command; do not re-create.
