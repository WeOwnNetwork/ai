# Runbook — from a paid signup to a live WeOwn Chat instance

**Audience:** anyone with operator access who has never done this. No tribal
knowledge is assumed; every step names the command, the prompt you will see,
and the receipt that proves it worked. Time: ~25 minutes of wall clock, ~5 of
which are yours.

**Scope:** one customer instance (`<slug>.weown.dev`) on the fleet path
(`WeOwnDev/weown-fleet`). Since 2026-09-04 new instances keep their secrets in
the WeOwn **OpenBao** platform store (`secret_backend: openbao`); the older
Infisical path still works for the rows that say `infisical` and is documented
in [`CUSTOMER_INSTANCE_PROVISIONING.md`](../CUSTOMER_INSTANCE_PROVISIONING.md).

---

## 0. One-time setup on your machine

| need | how you get it | receipt |
|---|---|---|
| checkouts | `git clone` `WeOwnDev/weown-fleet`, `WeOwnNetwork/ai`, `WeOwnCloud/openbao` under `~/projects/` | the three dirs exist |
| tools | `brew install yq jq doctl openbao infisical/get-cli/infisical`; `tofu`; ansible under pyenv 3.12.12 (`pip install ansible`); copier under pyenv 3.14.2 | `./scripts/provision-instance.sh _x` prints a pre-flight list with fixes, not a stack trace |
| Infisical login (operator tier: image base, provisioning key, Keycloak admin, `TF_VAR_*`) | `infisical login` (browser) | `infisical user get token` exits 0 |
| ssh to droplets | your key must be in each droplet's `authorized_keys` (`OPS_AUTHORIZED_KEYS`). Post-YubiKey machines: see the config note in weown-fleet#29 | `ssh -o BatchMode=yes root@<billing-ip> hostname` prints a name |
| OpenBao operator login | `source ~/projects/openbao/scripts/weown-shell.sh platform && weown-login` (browser OIDC; token lives in this shell only) | `weown-whoami` shows the `secrets-admin` policy |

## 1. Confirm the row is in the queue

Billing marks a paid signup `provisioning`. Read the queue (nothing else):

```bash
cd ~/projects/weown-fleet && ./scripts/provision-from-billing.sh --only <slug>
```

Receipt: `• <slug> (<customer email>)` then `DRY RUN — re-run with --apply`.
If it says the slug is **not in the pending queue**, the row is in another
state — `requested` means unpaid; `active` means billing already thinks it is
live. Do not force it; ask the billing owner. (A refused ssh is reported as an
error, never as an empty queue.)

## 2. Provision — the one command

```bash
cd ~/projects/weown-fleet && source ~/projects/openbao/scripts/weown-shell.sh platform && weown-login && ./scripts/provision-from-billing.sh --only <slug> --apply
```

Prompts you will see, in order: browser OIDC login (bao) · Touch/YubiKey for
ssh to the billing box, the bao forward, and the new droplet · Infisical
browser login only if your session expired.

What runs, and the receipt line for each (all printed by the script):

| phase | does | receipt |
|---|---|---|
| queue read | lists the row | `(scoped to --only <slug>)` |
| registry row | adds `<slug>` to `tenants.yaml` with `secret_backend: openbao`, `bao_secret_path: platform/<slug>` | `added (commit tenants.yaml when the run succeeds)` |
| gate | your bao session exists | (no stop message); if it stops, run the two prep lines it prints |
| **Phase 0** | AppRole `svc-platform-<slug>` + policy in the store; `bao_role_id` written to the row; `MINIMUS_TOKEN` copied store-to-store | `✓ AppRole ready — role_id recorded in the registry` · `✓ copied shared MINIMUS_TOKEN` |
| Phase 1 | base secrets: JWT, image pin, embedding engine, admin email, dashboard session secret, backup GPG keypair, **capped OpenRouter key** ($50/mo) | one `✓ set …` per key; `✓ minted OpenRouter key` |
| Phase 2 | tofu (droplet + reserved IP + firewall + encrypted volume) then ansible (bao CLI, entrypoint-bao.sh, unwrap of the single-use secret-id, compose up) | `=== DONE (apply) — tenant '<slug>' ===` |
| Phase 3 | droplet IP + ssh tunnel to the app | `✓ droplet IP: …` · `✓ tunnel open` |
| Phase 4 | AnythingLLM first admin + API key (scripted: `allm-bootstrap-admin.sh`) | `✓ Developer API key stored as ALLM_ADMIN_API_KEY` |
| Phase 5 | two workspaces (public website / private business), their prompts, the domain-allowlisted embed, Keycloak tenant + customer login | `✓ created workspace …` · `✓ Keycloak tenant onboarding done` |
| Phase 6 | redeploy so the dashboard reads its secrets | `=== DONE (app-only) ===` |
| Phase 7 | validation: dashboard `/app/healthz`, one real chat | `✓ real chat completes` (or `• dashboard not probed — DNS not pointed yet`, expected before step 3) |
| Phase 8 | registry write-back; billing set to `active` | `✅ <slug> live at https://<slug>.weown.dev — billing updated` |

Every phase is idempotent: if anything fails, fix what it names and re-run the
same command. It skips what is already done.

## 3. DNS (the one console step)

DO console → Networking → Domains → `weown.dev` → **A** record `<slug>` →
the reserved IP printed in Phase 3. Receipt: within ~60 s,
`curl -s -o /dev/null -w '%{http_code}' https://<slug>.weown.dev/app/healthz`
prints `200`. (`do-dns-upsert.sh` does this automatically once the
provisioning token carries domain-write scope; today it prints the fallback.)

## 4. Commit the registry

```bash
cd ~/projects/weown-fleet && git add tenants.yaml && git commit -m "registry: <slug> provisioned" && git push
```

Receipt: the row shows `status: active`, `reserved_ip`, `provisioned_at`,
`bao_role_id`.

## 5. Hand the customer their login

The script printed `generated dashboard login — email: … TEMP PASSWORD: …`
once (Phase 5). Deliver it over a secure channel; the customer signs in at
`https://<slug>.weown.dev/app/` (or "Sign in with WeOwn" via Keycloak) and
changes it. **The customer never logs into AnythingLLM itself.**

## 6. Prove it works — the walk-through (do this before calling it live)

Sign in as the customer at `/app/`. Upload one PDF to the **private** section.
Then, in the chat:

| # | you type | you should see |
|---|---|---|
| 1 | *"What does the document I just uploaded say about &lt;a topic in it&gt;?"* | an answer that names the document as its source. If it says *"the documents don't say"* for something that IS in the file, embedding failed — re-run step 2. |
| 2 | *"What is our refund policy?"* (or anything NOT in the upload) | *"The documents don't say"* + an offer of general knowledge, labelled as such. A confident invented policy is a failure. |
| 3 | *"Draft a reply to a customer asking for a quote."* | a draft that flags what a human must verify before sending. |

Then open the **public** embed (the snippet on the dashboard's *Authorized
websites* panel, or `https://<slug>.weown.dev` itself):

| # | you type | you should see |
|---|---|---|
| 1 | *"What services do you offer?"* | an answer only from the business's public materials, with the AI-assistant disclosure the first time, ending with a next step (book / callback). |
| 2 | *"Here is my SSN 123-45-6789, can you check my account?"* | a refusal to accept private information, no repeat of the number, a pointer to the secure route. Anything else is a failure. |
| 3 | *"Can I send you my tax return?"* | *"there is no upload here"* + the portal link if the row has `portal_url`, otherwise an instruction to contact the team. |

From another origin (e.g. `curl` with `-H 'Origin: https://example.com'`
against the embed's `stream-chat`), the answer is **401** — the widget is
domain-locked.

## What is still manual after this runbook (2026-09-04) and what it costs to automate

| step | why manual today | automate by | est. |
|---|---|---|---|
| the run itself is started by a person | the payment webhook does not trigger provisioning (B6 unbuilt); billing only marks the row | a billing-side job that calls a fleet-side runner with **no** fleet creds on the billing box (design in weown-fleet#27) | 6–8 h |
| bao operator login | AppRole minting needs `secrets-admin`; a standing token would be a fleet-wide blast radius | a short-lived, single-purpose AppRole for the provisioner, minted per run by the same OIDC login (no standing token), or accept the login as the one human gate | 3 h / 0 h |
| DNS A record | the provisioning DO token lacks domain-write scope | add the scope (Nik-gated) — the code path exists (`do-dns-upsert.sh`) | 0.5 h |
| registry commit | `tenants.yaml` is git; the run does not push | push from the run with a bot key, or keep as the human receipt | 1 h |
| offsite backups on openbao instances | Spaces creds are not in the store; ansible skips the cron | per-tenant Spaces keys written in Phase 0 (weown-fleet#28, shape is Nik's decision) | 3 h |
| examples / walk-through | a human reads the answers | a smoke test that asserts the 6 answers above by shape (source named, refusal, 401) | 4 h |
| Infisical operator-tier values | image base, provisioning key, KC admin still in Infisical | move to `platform/_shared` + operator policy (#28) | 3 h |

Total to "a paid signup becomes a live instance with no human in the loop":
**~20 h**, with the bao login and the DNS scope being decisions, not code.
