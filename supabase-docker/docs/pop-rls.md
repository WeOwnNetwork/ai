# Pop Schema RLS Pattern

| Field | Value |
|---|---|
| **Document** | `supabase-docker/docs/pop-rls.md` |
| **#WeOwnVer** | `v4.1.4.1` |
| **Status** | 🟡 DRAFT v0.1 — design complete; awaiting GoTrue tenant assignment direction from `@CTO` |
| **Effective** | 2026-06-26 (W26 D5) |
| **CCC-ID** | `PLT_2026-W26_2002` (W26 SOW anchor) |
| **Versioning spec** | [`docs/VERSIONING_WEOWNVER.md`](../../docs/VERSIONING_WEOWNVER.md) |

## Purpose

Define the Row-Level Security pattern for the `pop` schema. Per @CTO's W26 spec: Postgres enforces tenant isolation, not application code.

> "RLS pattern (the whole point): `tenant_id = current_setting('app.tenant')`. tenant_id comes from JWT. Postgres enforces, not app code. One tenant can't see another's rows even if MCP/app layer has a bug."

## Trust model

- **JWT is the source of truth** for `tenant_id`. JWTs are signed by GoTrue (auth service) and cannot be forged without the signing secret.
- **PostgREST + GoTrue handle JWT validation** at request time, then forward claims to Postgres via `set_config('request.jwt.claims', ...)`.
- **Postgres reads `tenant_id` from JWT claims** via `current_setting('request.jwt.claims', true)::json ->> 'tenant_id'`, then sets `app.tenant` for the session.
- **RLS policies enforce row-level filtering** based on `app.tenant`. No app layer can bypass.

## JWT claim shape

When GoTrue issues a JWT, include `tenant_id` as a custom claim:

```json
{
  "iss": "https://example.com/auth/v1",
  "sub": "user-uuid-here",
  "aud": "authenticated",
  "exp": 1750000000,
  "iat": 1749996400,
  "email": "user@example.com",
  "role": "authenticated",
  "tenant_id": "uuid-of-tenant",
  "app_metadata": {
    "tenant_id": "uuid-of-tenant"
  },
  "user_metadata": {}
}
```

GoTrue injects `tenant_id` from `app_metadata` set at signup (or via admin API). The `tenant_id` field at top level is denormalized for easier RLS reading.

## Session variable pattern

Before any query touching `pop`, Postgres needs `app.tenant` set. Primary path via PostgREST pre-request hook (Approach A, chosen). Approach B documented for batch/admin contexts only.

### Approach A — PostgREST pre-request hook (chosen)

PostgREST automatically sets `request.jwt.claims` from the validated JWT. A trigger-style function reads the claim and sets `app.tenant`:

```sql
create or replace function set_tenant_from_jwt() returns void
language plpgsql as $$
begin
    perform set_config(
        'app.tenant',
        coalesce(
            current_setting('request.jwt.claims', true)::json ->> 'tenant_id',
            ''
        ),
        true  -- session-local
    );
end;
$$;
```

Call once per session (via PostgREST's `pre-request` hook or similar). This is the canonical PostgREST + RLS pattern.

### Approach B — direct app set (batch/admin only)

For server-side flows not going through PostgREST (batch jobs, migration scripts, admin tooling), the app sets `app.tenant` directly:

```sql
set local app.tenant = 'uuid-of-tenant';
```

Depends on app discipline to set it on every connection — acceptable trade-off for batch/admin where the alternative is granting `bypassrls` to non-admin roles. Never used for user-facing request handling.

## RLS policies (one per table)

Enable RLS first:

```sql
alter table pop.people enable row level security;
alter table pop.organizations enable row level security;
alter table pop.places enable row level security;
alter table pop.interactions enable row level security;
alter table pop.tags enable row level security;
alter table pop.contact_tags enable row level security;
```

Per-table policy (template — apply to all 6 `pop` tables):

```sql
-- pop.people
create policy tenant_isolation_select on pop.people
    for select
    using (tenant_id::text = current_setting('app.tenant', true));

create policy tenant_isolation_insert on pop.people
    for insert
    with check (tenant_id::text = current_setting('app.tenant', true));

create policy tenant_isolation_update on pop.people
    for update
    using (tenant_id::text = current_setting('app.tenant', true))
    with check (tenant_id::text = current_setting('app.tenant', true));

create policy tenant_isolation_delete on pop.people
    for delete
    using (tenant_id::text = current_setting('app.tenant', true));
```

Repeat for `organizations`, `places`, `interactions`, `tags`, `contact_tags`.

## Service-role bypass

Admin/migration scripts need to bypass RLS. Use Postgres `bypassrls` attribute:

```sql
create role pop_admin bypassrls login password 'fetched-from-infisical-at-runtime';
grant all on schema pop to pop_admin;
grant all on all tables in schema pop to pop_admin;
```

This role is used by:

- Migration scripts
- Backup/restore operations
- Tenant provisioning (creating new tenant rows)
- Pop DB → Supabase dual-write sync

**Never grant `bypassrls` to PostgREST's `anon` or `authenticated` roles.**

## Roles needed

| Role | RLS | Purpose | Source of credentials |
|---|---|---|---|
| `anon` | enforced | PostgREST anonymous (pre-auth, no tenant access) | PostgREST default |
| `authenticated` | enforced | Logged-in user; reads `tenant_id` from JWT | GoTrue-issued JWTs |
| `service_role` | enforced | Service-to-service calls; trusted but still tenant-scoped | Infisical `SERVICE_ROLE_KEY` |
| `pop_admin` | bypassed | Migrations, backups, tenant provisioning | Infisical, restricted access |

## Hot-path optimization

RLS policies become part of every query's WHERE clause. Without indexes, full scans happen on each query.

**Required indexes** (already in [`pop-schema.md`](./pop-schema.md)):

- `idx_<table>_tenant on pop.<table> (tenant_id)` — primary RLS lookup
- Compound indexes `(tenant_id, <other_column>)` for common filter combos

Run `EXPLAIN ANALYZE` on representative queries before declaring victory. Watch for `Seq Scan` on `pop.*` tables — that means RLS is forcing a full scan despite the index.

## Gotchas

1. **Trailing `, true` in `current_setting`** — without it, missing setting raises an error instead of returning empty. Always include for resilience.
2. **`coalesce(..., '')` in `set_tenant_from_jwt`** — if JWT has no `tenant_id`, `app.tenant` is empty string. Policies will match no rows (correct fail-closed behavior).
3. **`uuid::text` comparison** — `current_setting` returns text, `tenant_id` is uuid. Cast `tenant_id::text` (chosen) or `current_setting::uuid` — pick one convention.
4. **`with check` on UPDATE** — without it, an update can change `tenant_id` to a different tenant (data exfiltration). Always include.
5. **`bypassrls` role exposure** — never expose to PostgREST API surface. Use only via admin scripts running with Infisical credentials.

## Decisions captured

| # | Decision | Rationale |
|---|---|---|
| 1 | `app.tenant` set via PostgREST pre-request hook (Approach A) | Canonical pattern; agent-independent; no app-level discipline required |
| 2 | JWT claim placement = both top-level `tenant_id` AND `app_metadata.tenant_id` | Standards-compatible (app_metadata) + clean policy reads (top-level); minor denormalization for ergonomics |
| 3 | `bypassrls` admin role = `pop_admin` | Sane default; can rename if WeOwn convention emerges |
| 4 | Per-tenant signing keys implemented per @CTO's spec | Tenants registry holds per-tenant RLS key + API key as specified |

## Open ask for @CTO

**GoTrue tenant assignment flow** — how do new users get a `tenant_id` claim at signup? Admin API call? Default tenant for staff users? External provisioning trigger? Need governance direction on tenant onboarding to wire GoTrue + the tenants registry correctly.

## Verification approach

Once deployed, verify isolation with two test users in different tenants:

```sql
-- as tenant A
set local app.tenant = 'tenant-a-uuid';
select count(*) from pop.people;
-- should see only tenant A's rows

-- as tenant B
set local app.tenant = 'tenant-b-uuid';
select count(*) from pop.people;
-- should see only tenant B's rows

-- as no tenant
set local app.tenant = '';
select count(*) from pop.people;
-- should see 0 rows
```

Plus integration tests through PostgREST endpoints with JWTs from each tenant.

## Related documents

- [`docs/pop-schema.md`](./pop-schema.md) — table layouts
- [`supabase-docker/README.md`](../README.md) — substrate template overview
- W26 SOW PLT_2026-W26_2002 — Pop DB → Supabase + RLS substrate
