# Powered-off droplet audit — 2026-07-18 (decision doc)

> Status: draft · read-only audit for owner decision · Author: ncimino
> Context: [`anythingllm-production.md`](anythingllm-production.md) fleet-map
> note — 3 of the 12 `anythingllm`-tagged droplets are powered **off**.
> **DigitalOcean bills powered-off droplets at the full rate** (CPU/RAM/disk
> stay reserved) — off ≠ free.

## Decision table

| # | Droplet | Created | Size | Est. cost/mo* | What's on disk (best evidence) | Recommendation |
|---|---|---|---|---|---|---|
| 1 | `s004-ccc-bot-2vcpu-4gb-amd-atl1` | 2026-05-20 | 2vCPU/4GB/80GB (AMD) | ~$24 | The **pre-resize s004 box** superseded by `int-s004-anythingllm` (8GB) during the 2026-06-10 OOM remediation; s004 app state was carried to the new droplet (see `sites/s004.ccc.bot/RESIZE_RUNBOOK.md`). Held as rollback insurance; the rollback window is long past. | **Snapshot → destroy** (Recommended) |
| 2 | `ceo-weown-team-2vcpu-4gb-amd-atl1` | 2026-04-01 | 2vCPU/4GB/80GB (AMD) | ~$24 | Unknown-content AnythingLLM instance ("ceo-weown-team"); no site dir in this repo, no backup cron evidence. Owner memory required — may hold un-backed-up workspace data. | **Snapshot → confirm owner → destroy** |
| 3 | `lite-ocpa-group-1vcpu-2gb-70gb-atl1` | 2026-02-19 | 1vCPU/2GB/70GB (Intel) | ~$14 | OCPA "lite" instance; **two snapshots already exist** (`ocpa-lite-pre-upgrade-anythingllm-v1.11.2` ×2), taken pre-upgrade — disk state likely already captured. No site dir in this repo. | **Destroy** (snapshots exist; dedupe the two snapshots to one) |

\* Approximate on-demand list prices; exact figures in the DO billing page.
Combined run-rate of the three: **~$62/mo for machines that are off**.
Snapshots bill ~$0.06/GB/mo (≈$5/mo per 80GB image) — an order of magnitude
cheaper than keeping the droplets.

## Snapshot-then-destroy recipe (per box)

Destruction is irreversible — the snapshot step is the safety net. Run one box
at a time; verify the snapshot exists before the destroy.

```bash
cd ~/projects/ai
# 1) snapshot (droplet is off — snapshot is consistent)
doctl compute droplet-action snapshot <droplet-id> \
  --snapshot-name "<name>-decommission-2026-07-18" --wait

# 2) verify the snapshot landed
doctl compute snapshot list --resource droplet --format Name,ResourceId,Size

# 3) destroy (removes the droplet, keeps the snapshot)
doctl compute droplet delete <droplet-id>
```

Droplet IDs: `572181823` (#1) · `562341974` (#2) · `553048192` (#3).

Post-destroy hygiene:

- Remove the boxes from any DO firewalls/load balancers that reference them.
- If a reserved IP was attached, release or reassign it (reserved IPs bill
  when unassigned).
- For #3, delete one of the two duplicate `ocpa-lite-pre-upgrade-…` snapshots.
- Record the outcome in the Resource Registry (vault) — created-for /
  destroyed-on / snapshot name.

## Open questions for the owner

1. Does anyone still need anything from `ceo-weown-team` (created 2026-04-01)?
   That is the only box whose contents lack any captured backup or snapshot.
2. Snapshot retention: keep decommission snapshots 60 days (backup-retention
   parity) then delete?
