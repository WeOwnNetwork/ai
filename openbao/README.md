# OpenBao — reusable deploy + governance (Wave 0 / POC)

Implements **Part A** of [`docs/DESIGN-openbao-reusable-deploy-and-secret-store-poc.md`](../docs/DESIGN-openbao-reusable-deploy-and-secret-store-poc.md)
(A572, PRJ-433.1) and the **locked §2 governance** (ELF research, G5-locked
2026-08-17). House standard: **tofu provisions the box, ansible installs the
software** — so this is an ansible role, not a `*-docker` compose stack. OpenBao
is the trust root; it runs as a host systemd service, not a container that would
depend on the same docker daemon everything else does.

> ## ⚠️ POC POSTURE — do not put real fleet secrets here yet
>
> The role defaults to a **dev/POC** posture (TLS disabled, 1-of-1 unseal,
> synthetic secrets). **Real secrets are gated on the unseal-custody decision**
> (DESIGN §5 / governance §2.6 — who holds the Shamir shares, and the recovery
> drill). Until Nik answers that, a box stood up from here is for proving the
> shape, nothing more. The role prints this warning on every successful run.

## What's here

| Path | What |
| --- | --- |
| `ansible/roles/openbao/` | install → configure → systemd → init/unseal → **verify** |
| `ansible/deploy-openbao.yml` | the playbook (targets a tofu-provisioned host) |
| `ansible/inventory.example.ini` | copy to `inventory.ini`, point at the POC box |
| `governance/policies/*.tpl` + `secrets-admin.hcl` | the **four locked §2.3 policy shapes** |
| `governance/bootstrap-governance.sh` | mounts `weown/`, renders one policy per shape, asserts the no-`weown/data/*` invariant |
| `seam/secret-lib.sh` | **the store-agnostic seam** (DESIGN §4) — `secret_run` / `secret_get`, dispatch on `SECRET_BACKEND` |
| `seam/entrypoint-secrets.sh` | drop-in for the ADR-006 entrypoint; infisical path unchanged |
| `seam/test-seam.sh` | dispatch tests (stubbed backends, no live store) |

## The three safety properties (why this isn't just "install a binary")

Straight from the design, because they are the difference between a reusable
playbook and a data-loss tool:

1. **Idempotent** — re-running an initialised box converges; it never re-inits.
2. **Fails closed** — storage present but node sealed and no shares supplied →
   the play STOPS. It never starts an empty server (the Keycloak-empty-volumes
   class of bug, worse blast radius).
3. **Asserts the real contract** — success = `/v1/sys/health` initialised +
   unsealed **and** a write→read round-trip, not "systemd says active".

## The seam is the highest-value piece

`SECRET_BACKEND` (`infisical` | `openbao` | `sops`) turns "migrate the fleet
off Infisical" into "flip a per-instance variable and redeploy", tested one
instance at a time. With it unset or `infisical`, behaviour is **identical to
today** — this is a refactor, not a migration. Worth doing even if we never
leave Infisical (DESIGN §4).

## How to run (Wave 0)

The agent authored the IaC; the credential-gated apply is the operator's, per
the house rule (agent writes the playbook, human runs `ansible-playbook`).

1. **Provision a POC droplet with tofu** (hardware — not this repo's job here).
2. **Point the inventory at it:** `cp ansible/inventory.example.ini ansible/inventory.ini` and edit.
3. **Install OpenBao:**

   ```bash
   PYENV_VERSION=3.12.12 ansible-playbook -i openbao/ansible/inventory.ini openbao/ansible/deploy-openbao.yml
   ```

   The run ends by telling you where the init material (root token + unseal
   share) landed and that you must move it into custody and delete it.
4. **Apply the governance shapes** (from the box or a jump host with `bao`):

   ```bash
   BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN=<root/admin> ./openbao/governance/bootstrap-governance.sh
   ```

## Validation done in-repo (no live box needed)

- `ansible-playbook --syntax-check` — clean
- `bash -n` + `shellcheck -S error` on all scripts — clean
- `seam/test-seam.sh` — 6/6 dispatch cases pass (each backend routes correctly,
  unknown backend fails closed, target command execs)
- policy templates verified to carry only their intended placeholders

The parts that need a live node (idempotency, the fail-closed gate, the
round-trip) are asserted by the role itself when it runs — that's what step 3
proves on the POC box.

## Not in scope for Wave 0 (gated)

- Real secrets → **unseal custody (§2.6), Nik**
- Per-instance AppRole/secret-id issuance → the provisioner (weown-fleet), at
  provision time; this repo holds the policy shapes it instantiates
- The actual Infisical→OpenBao migration → per-instance waves once B (the
  store decision) and custody are settled; the seam is what makes it per-instance
