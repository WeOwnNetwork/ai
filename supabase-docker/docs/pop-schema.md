# Pop DB → Supabase Schema Sketch

| Field | Value |
|---|---|
| **Document** | `supabase-docker/docs/pop-schema.md` |
| **#WeOwnVer** | `v4.1.4.1` |
| **Status** | 🟡 DRAFT v0.1 — structural design complete; field shapes pending `pg_dump` access from `@CTO` |
| **Effective** | 2026-06-26 (W26 D5) |
| **CCC-ID** | `PLT_2026-W26_2002` (W26 SOW anchor) |
| **Versioning spec** | [`docs/VERSIONING_WEOWNVER.md`](../../docs/VERSIONING_WEOWNVER.md) |

## Purpose

Sketch the schema design for migrating Pop DB into a self-hosted Supabase Postgres instance. Per the W26 SOW (PLT_2026-W26_2002), the goal this week is **scaffolding + first tables migrated + design review with @CTO**, not full migration.

This document captures the proposed structure, multi-tenancy approach, and RLS pattern for @CTO review before any prod data move.

## Source

Per @CTO's W26 spec (Signal, Wed Jun 24):

> "6 Pop DB tables migrate 1:1 into a `pop` schema: `people`, `organizations`, `places`, `interactions`, `tags`, `contact_tags`. Add `tenant_id` column on every row (this closes Pop DB's biggest gap — was built single-tenant). Build the tenants registry table (holds per-tenant RLS key + API key)."

## Constraints

1. **1:1 table migration** — preserve existing Pop DB structure; do not refactor field-level schema beyond adding `tenant_id`.
2. **Schema scope this week**: only the 6 `pop` schema tables + the `tenants` registry. Other schemas (sessions, context, governance) **out of scope** per @CTO.
3. **Multi-tenancy**: RLS-based isolation (shared `pop` schema, per-row `tenant_id`). Schema-per-tenant or instance-per-tenant for external paying customers (CPAs, financial advisors) = **later, don't over-build this week**.
4. **Tenants this week**: shared/staff tenants only.
5. **Field-level schema below is PROPOSED** — final field set requires verification against the actual existing Pop DB `pg_dump` before migration. Structural decisions (tenant_id placement, foreign keys, indexes, polymorphic join strategy, etc.) are **made and documented** in the Decisions Captured section; field shapes are the only piece blocked on data access.

## Target schema layout

```text
supabase postgres instance
├── public                  (Supabase-managed defaults)
│   └── tenants             (NEW — tenant registry, cross-cutting)
├── auth                    (GoTrue managed)
└── pop                     (NEW — Pop DB tables migrated 1:1 per @CTO spec)
    ├── people
    ├── organizations
    ├── places
    ├── interactions
    ├── tags
    └── contact_tags
```

## Tenants registry

The `tenants` table holds per-tenant configuration. Lives in `public` (not `pop`) because it's cross-cutting.

```sql
create table public.tenants (
    id            uuid primary key default gen_random_uuid(),
    slug          text not null unique,                    -- short identifier ('weown-staff', etc.)
    name          text not null,                           -- display name
    api_key       text not null unique,                    -- service-to-service auth (hashed in prod)
    rls_key       text,                                    -- per-tenant signing key (optional)
    metadata      jsonb default '{}'::jsonb,
    is_active     boolean default true,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index idx_tenants_slug on public.tenants (slug);
create index idx_tenants_active on public.tenants (is_active) where is_active = true;
```

## Pop schema tables (proposed field shape)

Each table gets:

- `tenant_id uuid not null` — references `public.tenants(id)`
- Index on `tenant_id` (RLS hot-path optimization)
- Standard `id`, `created_at`, `updated_at` columns
- Real field shape verified against existing Pop DB dump

### `pop.people`

```sql
create table pop.people (
    id            uuid primary key default gen_random_uuid(),
    tenant_id     uuid not null references public.tenants(id) on delete restrict,
    name          text,
    email         text,
    phone         text,
    metadata      jsonb default '{}'::jsonb,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index idx_people_tenant on pop.people (tenant_id);
create index idx_people_email on pop.people (tenant_id, email);
```

### `pop.organizations`

```sql
create table pop.organizations (
    id            uuid primary key default gen_random_uuid(),
    tenant_id     uuid not null references public.tenants(id) on delete restrict,
    name          text,
    type          text,
    website       text,
    metadata      jsonb default '{}'::jsonb,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index idx_organizations_tenant on pop.organizations (tenant_id);
```

### `pop.places`

```sql
create table pop.places (
    id            uuid primary key default gen_random_uuid(),
    tenant_id     uuid not null references public.tenants(id) on delete restrict,
    name          text,
    address       text,
    city          text,
    state         text,
    country       text,
    coordinates   point,
    metadata      jsonb default '{}'::jsonb,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index idx_places_tenant on pop.places (tenant_id);
```

### `pop.interactions`

```sql
create table pop.interactions (
    id            uuid primary key default gen_random_uuid(),
    tenant_id     uuid not null references public.tenants(id) on delete restrict,
    person_id     uuid references pop.people(id) on delete set null,
    type          text,                                  -- 'call', 'email', 'meeting', etc.
    subject       text,
    notes         text,
    occurred_at   timestamptz,
    metadata      jsonb default '{}'::jsonb,
    created_at    timestamptz not null default now()
);

create index idx_interactions_tenant on pop.interactions (tenant_id);
create index idx_interactions_person on pop.interactions (tenant_id, person_id);
create index idx_interactions_occurred on pop.interactions (tenant_id, occurred_at desc);
```

### `pop.tags`

```sql
create table pop.tags (
    id            uuid primary key default gen_random_uuid(),
    tenant_id     uuid not null references public.tenants(id) on delete restrict,
    name          text not null,
    color         text,
    created_at    timestamptz not null default now(),
    unique (tenant_id, name)
);

create index idx_tags_tenant on pop.tags (tenant_id);
```

### `pop.contact_tags`

Polymorphic join — a tag can be attached to either a person or an organization. Preserved as a single table per `@CTO`'s 1:1 migration directive.

```sql
create table pop.contact_tags (
    id              uuid primary key default gen_random_uuid(),
    tenant_id       uuid not null references public.tenants(id) on delete restrict,
    contact_id      uuid not null,                       -- references people.id OR organizations.id
    contact_type    text not null check (contact_type in ('person', 'organization')),
    tag_id          uuid not null references pop.tags(id) on delete cascade,
    created_at      timestamptz not null default now(),
    unique (tenant_id, contact_id, contact_type, tag_id)
);

create index idx_contact_tags_tenant on pop.contact_tags (tenant_id);
create index idx_contact_tags_contact on pop.contact_tags (tenant_id, contact_id, contact_type);
create index idx_contact_tags_tag on pop.contact_tags (tenant_id, tag_id);
```

> **Note on polymorphic FK + recommendation for `@CTO`**: Postgres has no native polymorphic foreign key. As designed above, the `contact_id` column carries no FK constraint (it points at either `pop.people.id` or `pop.organizations.id`); integrity is enforced at the application layer + `contact_type` check constraint. Implemented this way per `@CTO`'s 1:1 migration spec. **Recommendation**: splitting into `pop.person_tags` + `pop.organization_tags` would give DB-level FK enforcement + native cascade deletes — aligning with the same "Postgres enforces, not app code" philosophy used for RLS. The 1:1 directive may have been about scope/data-semantics rather than table count specifically; flagged as an open ask for `@CTO` to confirm 1:1 strict or open to split.

## Migration path

Per @CTO's spec:

1. **Snapshot** — capture current Pop DB state via `pg_dump`
2. **Dual-write window** — application writes to both old Pop DB + new Supabase
3. **Cut reads over** to Supabase once parity verified
4. **No prod data move** without @CTO sign-off

## Decisions captured

| # | Decision | Rationale |
|---|---|---|
| 1 | Tenants registry lives in `public.tenants` | Cross-cutting concern; not specific to `pop` schema |
| 2 | Polymorphic `contact_tags` = single table + `contact_type` check constraint (per `@CTO`'s 1:1 spec) | Implemented per spec; split-table alternative raised as open ask #2 below for `@CTO` to confirm 1:1 strict or open to splitting. |
| 3 | `tenant_id` FK behavior = `on delete restrict` | Cascade on tenants = catastrophic data loss risk; restrict is the safe default |
| 4 | `metadata jsonb` field on every table | Standard pattern; useful escape hatch for tenant-specific extensions |
| 5 | `updated_at` auto-update via trigger function | Less app-level discipline required; consistent across PostgREST/admin paths |

## Open asks for @CTO

1. **Field-level Pop DB verification** — is a current `pg_dump` of Pop DB available so we can verify the field shapes match the live schema? Field shapes above are proposed based on typical contact/CRM model; structural decisions stand regardless.

2. **`contact_tags` table strategy** — implemented as single table per your 1:1 migration spec. Recommendation: splitting into `person_tags` + `organization_tags` gains DB-level FK enforcement + native cascade deletes (same "Postgres enforces, not app code" philosophy applied to RLS). Confirm 1:1 strict, or open to splitting?

## RLS pattern

See [`docs/pop-rls.md`](./pop-rls.md) for the Row-Level Security policy pattern using `current_setting('app.tenant')` from JWT.

## Related documents

- [W26 SOW PLT_2026-W26_2002](../README.md#status) — anchor
- [`supabase-docker/README.md`](../README.md) — substrate template overview
- [`supabase-docker/CHANGELOG.md`](../CHANGELOG.md) — version history
- [`docs/pop-rls.md`](./pop-rls.md) — RLS policy pattern
