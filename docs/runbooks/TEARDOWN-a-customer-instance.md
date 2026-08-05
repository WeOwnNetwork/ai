# Runbook — tearing down a customer instance

**For:** WeOwn devops. **Time:** ~15 minutes, most of it waiting.
**Script:** `weown-fleet/scripts/teardown-instance.sh` (dry-run by default).

Teardown is the operation with no undo, so the order is deliberate:

1. **Prove the data is recoverable** — final backup, then verify it downloads
   and decrypts. A teardown that starts with an unverified backup is a data
   loss event waiting for someone to ask a question in three months.
2. **Revoke credentials while we still know what they are** — a live API key
   belonging to a destroyed instance is an unowned credential.
3. **Then** destroy infrastructure.
4. **Retire records; never delete them.**

---

## Before you start

- Confirm the teardown is actually authorised (subscription cancelled and
  grace period elapsed, or the customer asked). Check billing → the customer's
  instance status and subscription.
- Tell the customer when their data stops being retrievable (see retention).
- Have `infisical login` current and the provisioning token in place.

## Run it

Dry run first — always. It changes nothing and prints every action:

```bash
cd ~/projects/weown-fleet && ./scripts/teardown-instance.sh <slug>
```

When the plan looks right:

```bash
cd ~/projects/weown-fleet && ./scripts/teardown-instance.sh <slug> --confirm <slug>
```

The double-naming is the safety: you cannot destroy the wrong instance with a
mistyped flag, because the slug has to match itself.

## What the script does, step by step

| # | Step | Automated | Notes |
|---|---|---|---|
| 1 | Final backup on the instance | ✓ | **Hard stop** if it fails — nothing is destroyed |
| 2 | Verify the backup downloads + decrypts | ✓ | `verify-backup.sh`; a failure stops the teardown |
| 3 | Revoke the customer's capped OpenRouter key | ✓ | Falls back to a named manual step if the API call fails |
| 4 | Revoke the instance Machine Identity | ✗ **manual** | Org-level action, deliberately not automated (same reason creating it is manual) |
| 5 | Remove the DNS A record | ✓ | Needs the provisioning token's `domain` scope |
| 6 | `tofu destroy` — droplet, volume, firewall, monitors, reserved IP | ✓ | Via `render-deploy.sh <slug> --destroy` |
| 7 | Mark billing Instance `destroyed`, registry row `retired` | ✓ | Commit `tenants.yaml` afterwards |

## What is deliberately retained

- **Backups** in `s3://weown-prod-backups/<slug>/` — the retention policy
  governs these, not the teardown. This is what makes a "we deleted it by
  mistake" conversation survivable.
- **The tenant's Infisical folder** — it holds the **GPG key those backups are
  encrypted with**. Delete the folder and the retained backups become
  permanently unreadable. Do not tidy it away.
- **Registry row and billing record** — marked retired/destroyed. A retired
  instance still has to be explainable months later: who it was, when it ran,
  when it stopped.

## After the script

1. **Delete the `<slug>-prod` identity** in Infisical (org → Access Control →
   Identities). The script prints this; it is the one credential it will not
   revoke for you.
2. **Commit `tenants.yaml`** so the registry reflects reality.
3. **Diarise the data-retention end date** — when the backups themselves should
   go. Until that decision is written down, "retained" means "kept forever by
   accident".
4. **Confirm to the customer** what was removed and what is retained for how
   long.

## Verifying it actually happened

Do not trust the script's exit code — check the four places:

```bash
doctl compute droplet list --format Name | grep <slug>        # expect nothing
dig +short A <slug>.weown.dev                                  # expect nothing
aws s3 ls s3://weown-prod-backups/<slug>/ --endpoint-url https://atl1.digitaloceanspaces.com | tail -3   # expect the final backup
yq -r '.tenants."<slug>".status' ~/projects/weown-fleet/tenants.yaml                                     # expect "retired"
```

## Open questions this runbook does not settle

- **Subdomain reuse.** A retired slug can currently be claimed again by a new
  customer, which means inheriting whatever links point at the old one. Decide:
  permanent reservation, cooling-off period, or free reuse. (Register item C4.)
- **Retention period.** No policy yet for how long a former customer's
  encrypted backups are kept. Needs a decision, then automation.
- **Restore-to-scratch.** Step 2 proves the backup decrypts and lists; it does
  not restore it onto a scratch instance. That deeper drill exists
  (`verify-backup.sh` §8.5 notes) and is worth doing periodically, not on every
  teardown.
