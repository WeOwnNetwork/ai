# Secrets Governance — requirements

**Status:** draft (plan locked in the vault 2026-08-17) · **Owner:** Nik · **Source:** *ELF Research — Agency Deployment + OpenBao Governance — 2026-08-17* (WeOwn vault), §2

Repo copy of the **locked** secrets-governance plan: the naming convention and least-privilege model
that every OpenBao grant, identity, and register row must follow. Authored and human-reviewed
**before** any secret moves; it gates the store, register, and migration packages.

Capability: [secrets-management](../capabilities/secrets-management.md).

## 1. Principles

1. **Deny-by-default; scope = the blast radius.** A compromised agency instance reads its own
   secrets and nothing else.
2. **Path leaf ≡ identity name ≡ register row.** One name across store, identity, and register.
3. **No secret value in any agent context, ever** (blind pipelines; store-to-store).
4. **No shared human super-credential.** Human access via OIDC against the WeOwn SSO (individually
   attributable); break-glass via Shamir quorum — never a shared password row.
5. **Registry-first:** the register row exists (status `building`) before the secret does.

## 2. Naming convention (mount + path scheme)

One KV-v2 mount, `weown/`:

```text
weown/<tier>/<scope>/<service>/<key>

tier ∈ { platform | agency | infra }

platform/  → WeOwn-shared services (one scope per service)
  weown/platform/sso-keycloak/{POSTGRES_PASSWORD, KEYCLOAK_ADMIN_PASSWORD, ...}
  weown/platform/gitea-git/{...}
  weown/platform/billing/{OIDC_RP_CLIENT_SECRET, KC_ADMIN_CLIENT_SECRET, STRIPE_*}
  weown/platform/hermes/{OPENROUTER_API_KEY, ...}

agency/    → per-agency, then per-platform-instance (mirrors Infisical folder-per-instance)
  weown/agency/<agency-slug>/<platform>/<instance>/<key>
  e.g. weown/agency/volcarian/chat/prod/OPENROUTER_API_KEY

infra/     → provider credentials + tofu vars (mirrors Infisical /infra/shared)
  weown/infra/do/{TF_VAR_do_token}
  weown/infra/spaces/{TF_VAR_spaces_access_key, SPACES_ACCESS_KEY, ...}
```

Rules:

- Lowercase kebab-case scopes.
- Key names stay the env-var names the templates already consume — migration is a mapping, not a
  rename; no new name pairs invented (the existing Spaces two-pair naming standard stands).
- Every path's first two segments are exactly what its policy grants on.

Mapping from today's Infisical layout is mechanical:

| Infisical today | OpenBao path |
| --- | --- |
| `weown-tofu` project, `/infra/shared` | `weown/infra/*` |
| app project `GiteaGit`, `/` | `weown/platform/gitea-git/*` |
| `WeOwn-Chat` project, `/sites/weown-chat-sales` | `weown/agency/weown/chat/sales/*` (WeOwn as its own agency; the first external agency lands beside it) |

## 3. Least-privilege policy model (four templates, never bespoke)

| Policy template | Grants (KV-v2 `data/` paths) | Bound to |
| --- | --- | --- |
| `svc-platform-<service>` | read `weown/data/platform/<service>/*` | that service's AppRole |
| `svc-agency-<agency>-<platform>-<instance>` | read `weown/data/agency/<agency>/<platform>/<instance>/*` | that instance's AppRole |
| `operator-<area>` | CRUD on one tier subtree (e.g. `weown/data/agency/<agency>/*`) — humans, via OIDC group | Keycloak group → OIDC role |
| `secrets-admin` | policy/auth/mount admin, **no blanket data read** | named humans via OIDC; root token sealed away after setup |

Hard rules:

- **No policy ever grants `weown/data/*`** — a tier root is the widest legal grant, operators only.
- Machine identities get read-only on exactly one leaf subtree.
- Deny is the default; no wildcard convenience grants to route around it.
- Cross-agency read paths are structurally impossible: no template spans two `<agency>` values.

## 4. Machine identity model (what kills the Infisical bill)

- **One AppRole per instance-service**, named identically to its policy
  (e.g. `svc-agency-volcarian-chat-prod`). AppRoles are free and unlimited — this is the cost fix.
- role-id baked into the instance render (not secret); **secret-id delivered via response-wrapped
  token at provision time** (playbook hands the wrapped token to the box; box unwraps; value never
  transits an agent or a chat). secret-id is TTL'd + renewable; CIDR-bound to the instance where
  practical.
- Human auth: **OIDC against the WeOwn SSO** (Keycloak) → group-mapped to `operator-*` /
  `secrets-admin`. Honest circularity: Keycloak is itself a platform service whose secrets live in
  the store; break-glass for "SSO down AND we need the store" is the root-token ceremony via unseal
  quorum, documented as a drill, never improvised.

## 5. Unseal custody (owner decision; recommendation)

- Shamir **3-of-5**, shares with five named humans across WeOwn and the contractor side, each in an
  **individual** password manager — never the shared vault.
- No cloud auto-unseal at this stage; alert on sealed state + a written 15-minute unseal runbook.
- Quarterly drill: seal → quorum unseals → write/read round-trip → logged.

## Acceptance criteria

- [ ] Plan human-reviewed and `published` before the first real secret moves (target lock 2026-08-20).
- [ ] `weown/` KV-v2 mount is the only fleet secrets mount; every path matches
      `weown/<tier>/<scope>/<service>/<key>` with `tier ∈ {platform, agency, infra}`.
- [ ] Exactly four policy templates exist in the implementation repo; every live policy is an
      instance of one; an automated check asserts no policy grants `weown/data/*`.
- [ ] Every machine identity is an AppRole named identically to its policy, read-only on one leaf
      subtree; secret-ids are issued response-wrapped.
- [ ] Human access is OIDC-only; no shared human credential exists for the store.
- [ ] Unseal custody decided and the first drill logged before wave 1.

## Change log

| Date | Change | By |
| --- | --- | --- |
| 2026-08-19 | Restructured to WeOwn doc conventions: dropped internal taxonomy frontmatter + trace sections, renamed off `CAP-`/`RP-` prefixes | Nik |
| 2026-08-19 | Landed from vault outline (draft) | Nik |
