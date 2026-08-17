# Design — reusable OpenBao deploy, and the secret-store POC

**Status:** proposal, not built. Requested by Tyler + Jason (2026-08-16, PRJ-433.1):
make the OpenBao deploy *reusable, not one-and-done*. Cost driver: Infisical
self-host pricing.

**Read this first:** the ask contains **two separable questions**, and conflating
them is the main risk. One is cheap and safe to build now. The other is a
migration decision that should not be made on vibes.

| | Question | Cost | Reversible? |
| --- | --- | --- | --- |
| **A** | Can we stamp an OpenBao server onto any box, repeatably? | small | yes — it's a playbook |
| **B** | Should OpenBao replace Infisical as the fleet secret store? | large | **no, not cheaply** |

**Recommendation: build A now. Gate B on measured numbers and one prerequisite
that nobody has costed yet (§5).**

---

## 1. What is actually coupled to Infisical today

Measured, not estimated:

| Fact | Count |
| --- | --- |
| `*-docker` templates | **13** |
| Files invoking `infisical run` | **310** |
| Templates whose runtime depends on it | **all 13** |

But the raw file count overstates the coupling, because **ADR-006 already
funnelled everything through one seam**. Every container starts like this:

```text
container start
  → entrypoint-infisical.sh  (bind-mounted, read-only)
      → reads /.infisical-auth.env   (machine-identity client id + secret)
      → infisical login --method=universal-auth
      → exec infisical run -- <the image's real entrypoint>
```

That single wrapper — plus the ansible tasks and `backup.sh`/`restore.sh` that
call the CLI directly — is the real surface. **The swap is cheap at the seam and
ruinous everywhere else**, which is what §4 is about.

---

## 2. Part A — the reusable deploy (build this)

House standard applies: **tofu for hardware, ansible for software**. So the
deliverable is an **ansible role**, not a shell script and not a bespoke
per-box install.

```text
ansible/roles/openbao/
  defaults/main.yml     # version, listener addr, storage path, TLS mode
  tasks/main.yml        # install → configure → systemd → init/unseal → verify
  templates/            # openbao.hcl.j2, systemd unit
  handlers/main.yml
```

Properties it must have, in priority order:

1. **Idempotent.** Re-running against an initialised box converges; it must
   never re-init and orphan the existing data. This is the failure that turns a
   "reusable" playbook into a data-loss tool.
2. **Fails closed on init state.** If storage exists but the node is sealed, the
   play stops and says so — it does not silently start an empty server.
   (Precedent: the Keycloak render that starts on empty volumes behind green
   healthchecks. Same class of bug, worse blast radius.)
3. **Asserts the real contract, not a proxy.** "systemd says active" is not
   success. Verify `/v1/sys/health` reports initialised + unsealed, and that a
   write-then-read round-trip works.
4. **Storage on the encrypted volume**, same as every other stateful service in
   the fleet — DO block storage is platform-encrypted at rest, droplet local
   disk is not.
5. **Backed up before it is trusted.** Nothing goes in it until its backup is
   proven by a restore rehearsal, per the fleet rule that "backups exist" is not
   the same as "restores are rehearsed".

Buildable without any decision from anyone. Standing one up costs a droplet and
proves the operational shape, which is exactly what makes question B answerable.

---

## 3. Part B — the POC, and what it must actually measure

The stated driver is **cost**. That number does not exist in writing yet, and
the decision is not safe without it.

**Needed before the comparison means anything:**

| Input | Who has it |
| --- | --- |
| Current Infisical spend, and what drives it (projects? identities? seats?) | WeOwn.Dev now owns the bill (WO-Disc-977); Jason has the portal |
| Projected count at 100 instances under the current per-instance folder model | derivable from the fleet registry |
| The negotiated price, if the Diego/Infisical conversation lands | that negotiation is live — a migration decision taken before it concludes may be solving a problem that is about to change |

**Comparison axes that matter more than sticker price:**

- **Custody burden** (§5 — the big one).
- **Migration cost**: 13 templates, the ADR-006 wrapper, ansible, backup/restore
  scripts, and every per-instance machine identity re-issued.
- **Operational failure modes**: Infisical down = containers can't start.
  Self-hosted OpenBao down = *same*, but now it is our pager and our restore.
- **Agent compatibility**: fleet tooling reads secrets in-process
  (`infisical export | jq`). Any replacement must support the same
  never-print-it pattern, or it breaks the secret-handling rules wholesale.

**SOPS is a different shape and worth stating plainly:** it is
encrypted-secrets-in-git, not a server. It removes the runtime dependency
entirely (no service to be down) at the cost of rotation being a commit and a
redeploy rather than a value change. For a fleet whose secrets rotate rarely and
whose main pain is per-project pricing, that tradeoff deserves a real look
rather than being treated as the junior option.

---

## 4. What would make a migration cheap (do this regardless)

Whatever wins, the fleet should not be welded to a vendor at 310 call sites.
**Introduce the store-agnostic seam now**, while it is a refactor and not a
migration:

```text
entrypoint-secrets.sh          # dispatches on SECRET_BACKEND
  ├── infisical  → infisical run -- "$@"     (today, unchanged)
  ├── openbao    → bao agent / exec wrapper
  └── sops       → decrypt to env, then exec
```

Same for the CLI-side reads in ansible and `backup.sh` — one `secret_get`
function, one place to change. This is worth doing **even if we never leave
Infisical**, because it turns "migrate the fleet" into "flip a per-instance
variable and redeploy", which is also how a migration gets tested one instance
at a time instead of all at once.

FLEET_OPERATIONS_DESIGN.md already anticipates this: *"the store-agnostic
tooling pattern keeps this swappable."* It is not built yet. Building it is the
highest-value item in this whole document.

---

## 5. ⚠️ The prerequisite nobody has costed: unseal-key custody

This is the part most likely to be underestimated, so it gets its own section.

**Infisical today:** authentication is a machine identity. If we lose the
credential, we mint a new one. Nothing is unrecoverable.

**Self-hosted OpenBao:** the server boots **sealed**. Unsealing needs a quorum
of key shares (Shamir) or an auto-unseal KMS. Which means:

- **Lose the unseal shares → every secret in the store is unrecoverable.** Not
  "inconvenient" — gone, including the credentials needed to rebuild the things
  that held them.
- **Every reboot needs unsealing.** Unattended reboot + manual unseal = an
  outage that lasts until a human with shares wakes up. Auto-unseal fixes it by
  moving trust to a cloud KMS — which is a dependency on exactly the kind of
  vendor we would be self-hosting to avoid.
- **The shares cannot live with the agents.** Per the secret-handling rules,
  no agent may hold them; and per credential-at-rest policy they cannot sit
  plaintext on the box they unseal. So custody is: which humans, holding what,
  stored where, and what happens when one is unreachable.

**None of that is a reason not to do it.** It is a reason the decision needs an
owner who has answered "who holds the shares, and what is the recovery drill"
*before* the first secret is migrated. Recommend the reusable playbook (Part A)
default to a **dev/POC posture** with this stated in its README, so nobody
mistakes a POC instance for something safe to put real fleet secrets in.

---

## 6. Proposed sequence

1. **Build the ansible role** (Part A) → stamp a POC box. No decisions required.
2. **Build the store-agnostic seam** (§4) → migration becomes per-instance
   config. Valuable whatever we choose.
3. **Get the cost numbers** (§3) → hand them to Jason with the negotiation
   status alongside; the two are the same decision.
4. **Answer the custody question** (§5) → this gates any real migration.
5. **Then decide**, one instance first, never fleet-wide in one step.

## 7. Open questions for Nik / Jason / Tyler

| # | Question | Owner |
| --- | --- | --- |
| 1 | What is Infisical actually costing, and on what axis? | Jason (portal) |
| 2 | Does the Infisical negotiation change the premise? | Jason |
| 3 | Is the goal cost, sovereignty, or both? They point at different answers — sovereignty argues for self-hosting, cost might be solved by a discount | Nik/Jason |
| 4 | Who holds unseal shares, and what is the recovery drill? | Nik — **blocks any real migration** |
| 5 | Is SOPS in scope as a serious candidate, or is a server assumed? | Nik |
