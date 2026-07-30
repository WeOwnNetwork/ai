-- 001_pop_schema.sql
--
-- Pop DB → Supabase migration: schema + tables + RLS.
--
-- Applied by ansible/deploy.yml (roles/supabase) on a fresh Supabase
-- instance once the `pop` schema is not yet present. See
-- docs/pop-schema.md + docs/pop-rls.md for design rationale and the
-- Decisions captured tables.
--
-- Idempotency: uses IF NOT EXISTS, CREATE OR REPLACE, and
-- DROP POLICY IF EXISTS ... CREATE POLICY where PostgreSQL doesn't
-- otherwise support idempotent creation. Rerunning against a
-- fully-migrated database is a no-op.
--
-- Field-level shapes are PROPOSED; final field set requires
-- verification against the existing Pop DB pg_dump before the actual
-- data move. Structural decisions (tenant_id placement, polymorphic
-- contact_tags, RLS pattern, on-delete semantics) are frozen per
-- @CTO's W26 spec — see docs/pop-schema.md §"Decisions captured".

set client_min_messages = warning;

-- =============================================================================
-- Extensions
-- =============================================================================

create extension if not exists pgcrypto;   -- gen_random_uuid()

-- =============================================================================
-- Schema
-- =============================================================================

create schema if not exists pop;

comment on schema pop is
    'Pop DB tables migrated 1:1 from the pre-migration Pop DB per @CTO W26 spec. '
    'Tenant isolation enforced via RLS reading current_setting(''app.tenant'').';

-- =============================================================================
-- updated_at trigger helper (pop-schema.md Decision #5)
-- =============================================================================

create or replace function public.set_updated_at()
    returns trigger
    language plpgsql
    as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

comment on function public.set_updated_at is
    'Trigger function that stamps updated_at = now() on any UPDATE. '
    'Applied to every table with an updated_at column.';

-- =============================================================================
-- Tenants registry (pop.tenants — cross-cutting, not scoped to pop)
-- =============================================================================

create table if not exists pop.tenants (
    id            uuid primary key default gen_random_uuid(),
    slug          text not null unique,                    -- short identifier ('weown-staff', etc.)
    name          text not null,                           -- display name
    api_key       text not null unique,                    -- service-to-service auth (should be hashed at app layer before insert)
    rls_key       text,                                    -- optional per-tenant signing key
    metadata      jsonb not null default '{}'::jsonb,
    is_active     boolean not null default true,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index if not exists idx_tenants_slug   on pop.tenants (slug);
create index if not exists idx_tenants_active on pop.tenants (is_active) where is_active = true;

drop trigger if exists trg_tenants_updated_at on pop.tenants;
create trigger trg_tenants_updated_at
    before update on pop.tenants
    for each row execute function public.set_updated_at();

-- =============================================================================
-- pop.people
-- =============================================================================

create table if not exists pop.people (
    id            uuid primary key default gen_random_uuid(),
    tenant_id     uuid not null references pop.tenants(id) on delete restrict,
    first_name    text not null,
    last_name     text not null,
    email         text,
    phone         text,
    metadata      jsonb not null default '{}'::jsonb,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index if not exists idx_people_tenant on pop.people (tenant_id);
create index if not exists idx_people_email  on pop.people (tenant_id, email);

drop trigger if exists trg_people_updated_at on pop.people;
create trigger trg_people_updated_at
    before update on pop.people
    for each row execute function public.set_updated_at();

-- =============================================================================
-- pop.organizations
-- =============================================================================

create table if not exists pop.organizations (
    id            uuid primary key default gen_random_uuid(),
    tenant_id     uuid not null references pop.tenants(id) on delete restrict,
    name          text,
    type          text,
    website       text,
    metadata      jsonb not null default '{}'::jsonb,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index if not exists idx_organizations_tenant on pop.organizations (tenant_id);

drop trigger if exists trg_organizations_updated_at on pop.organizations;
create trigger trg_organizations_updated_at
    before update on pop.organizations
    for each row execute function public.set_updated_at();

-- =============================================================================
-- pop.places
-- =============================================================================

create table if not exists pop.places (
    id            uuid primary key default gen_random_uuid(),
    tenant_id     uuid not null references pop.tenants(id) on delete restrict,
    name          text,
    address       text,
    city          text,
    state         text,
    country       text,
    coordinates   point,
    metadata      jsonb not null default '{}'::jsonb,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index if not exists idx_places_tenant on pop.places (tenant_id);

drop trigger if exists trg_places_updated_at on pop.places;
create trigger trg_places_updated_at
    before update on pop.places
    for each row execute function public.set_updated_at();

-- =============================================================================
-- pop.interactions
-- =============================================================================

create table if not exists pop.interactions (
    id            uuid primary key default gen_random_uuid(),
    tenant_id     uuid not null references pop.tenants(id) on delete restrict,
    person_id     uuid references pop.people(id) on delete set null,
    type          text,                                  -- 'call', 'email', 'meeting', etc.
    subject       text,
    notes         text,
    occurred_at   timestamptz,
    metadata      jsonb not null default '{}'::jsonb,
    created_at    timestamptz not null default now()
);

create index if not exists idx_interactions_tenant   on pop.interactions (tenant_id);
create index if not exists idx_interactions_person   on pop.interactions (tenant_id, person_id);
create index if not exists idx_interactions_occurred on pop.interactions (tenant_id, occurred_at desc);

-- =============================================================================
-- pop.tags
-- =============================================================================

create table if not exists pop.tags (
    id            uuid primary key default gen_random_uuid(),
    tenant_id     uuid not null references pop.tenants(id) on delete restrict,
    name          text not null,
    color         text,
    created_at    timestamptz not null default now(),
    unique (tenant_id, name)
);

create index if not exists idx_tags_tenant on pop.tags (tenant_id);

-- =============================================================================
-- pop.contact_tags (polymorphic join — 1:1 migration per @CTO spec)
-- =============================================================================
-- contact_id has NO FK constraint — it points at either pop.people.id or
-- pop.organizations.id. Integrity enforced at app layer + the contact_type
-- CHECK constraint. Splitting into pop.person_tags + pop.organization_tags
-- would give DB-level FK enforcement — flagged as pop-schema.md open ask #2
-- for @CTO's 1:1 strict vs open-to-split confirmation.

create table if not exists pop.contact_tags (
    id              uuid primary key default gen_random_uuid(),
    tenant_id       uuid not null references pop.tenants(id) on delete restrict,
    contact_id      uuid not null,
    contact_type    text not null check (contact_type in ('person', 'organization')),
    tag_id          uuid not null references pop.tags(id) on delete cascade,
    created_at      timestamptz not null default now(),
    unique (tenant_id, contact_id, contact_type, tag_id)
);

create index if not exists idx_contact_tags_tenant  on pop.contact_tags (tenant_id);
create index if not exists idx_contact_tags_contact on pop.contact_tags (tenant_id, contact_id, contact_type);
create index if not exists idx_contact_tags_tag     on pop.contact_tags (tenant_id, tag_id);

-- =============================================================================
-- RLS session-variable helper (Approach A — PostgREST pre-request hook)
-- =============================================================================
-- Called by PostgREST's pre-request hook once per session. Reads tenant_id
-- from the validated JWT claims and stores it in app.tenant for policy use.
-- Fail-closed: missing/empty JWT tenant_id → app.tenant = '' → policies
-- match zero rows. See docs/pop-rls.md §"Approach A".

create or replace function public.set_tenant_from_jwt() returns void
    language plpgsql
    security definer
    as $$
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

comment on function public.set_tenant_from_jwt is
    'Reads tenant_id from request.jwt.claims and sets app.tenant for the '
    'session. Called by PostgREST pre-request hook. See docs/pop-rls.md.';

-- =============================================================================
-- Enable Row-Level Security
-- =============================================================================

-- tenants holds per-tenant api_key / rls_key: RLS ON with a service_role-only
-- policy, so anon/authenticated can never read other tenants' credentials
-- (without this, the blanket pop-schema grant made tenants world-readable).
alter table pop.tenants       enable row level security;
alter table pop.people        enable row level security;
alter table pop.organizations enable row level security;
alter table pop.places        enable row level security;
alter table pop.interactions  enable row level security;
alter table pop.tags          enable row level security;
alter table pop.contact_tags  enable row level security;

-- =============================================================================
-- RLS policies (4 per table — select/insert/update/delete)
-- =============================================================================
-- Same pattern for every table. UPDATE policy carries both USING and WITH CHECK
-- so an update cannot change tenant_id to a different tenant (data
-- exfiltration guard — see docs/pop-rls.md §"Gotchas #4").

-- pop.people ------------------------------------------------------------------
drop policy if exists tenant_isolation_select on pop.people;
create policy tenant_isolation_select on pop.people
    for select
    using (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_insert on pop.people;
create policy tenant_isolation_insert on pop.people
    for insert
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_update on pop.people;
create policy tenant_isolation_update on pop.people
    for update
    using (tenant_id::text = current_setting('app.tenant', true))
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_delete on pop.people;
create policy tenant_isolation_delete on pop.people
    for delete
    using (tenant_id::text = current_setting('app.tenant', true));

-- pop.organizations -----------------------------------------------------------
drop policy if exists tenant_isolation_select on pop.organizations;
create policy tenant_isolation_select on pop.organizations
    for select
    using (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_insert on pop.organizations;
create policy tenant_isolation_insert on pop.organizations
    for insert
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_update on pop.organizations;
create policy tenant_isolation_update on pop.organizations
    for update
    using (tenant_id::text = current_setting('app.tenant', true))
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_delete on pop.organizations;
create policy tenant_isolation_delete on pop.organizations
    for delete
    using (tenant_id::text = current_setting('app.tenant', true));

-- pop.places ------------------------------------------------------------------
drop policy if exists tenant_isolation_select on pop.places;
create policy tenant_isolation_select on pop.places
    for select
    using (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_insert on pop.places;
create policy tenant_isolation_insert on pop.places
    for insert
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_update on pop.places;
create policy tenant_isolation_update on pop.places
    for update
    using (tenant_id::text = current_setting('app.tenant', true))
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_delete on pop.places;
create policy tenant_isolation_delete on pop.places
    for delete
    using (tenant_id::text = current_setting('app.tenant', true));

-- pop.interactions ------------------------------------------------------------
drop policy if exists tenant_isolation_select on pop.interactions;
create policy tenant_isolation_select on pop.interactions
    for select
    using (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_insert on pop.interactions;
create policy tenant_isolation_insert on pop.interactions
    for insert
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_update on pop.interactions;
create policy tenant_isolation_update on pop.interactions
    for update
    using (tenant_id::text = current_setting('app.tenant', true))
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_delete on pop.interactions;
create policy tenant_isolation_delete on pop.interactions
    for delete
    using (tenant_id::text = current_setting('app.tenant', true));

-- pop.tags --------------------------------------------------------------------
drop policy if exists tenant_isolation_select on pop.tags;
create policy tenant_isolation_select on pop.tags
    for select
    using (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_insert on pop.tags;
create policy tenant_isolation_insert on pop.tags
    for insert
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_update on pop.tags;
create policy tenant_isolation_update on pop.tags
    for update
    using (tenant_id::text = current_setting('app.tenant', true))
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_delete on pop.tags;
create policy tenant_isolation_delete on pop.tags
    for delete
    using (tenant_id::text = current_setting('app.tenant', true));

-- pop.contact_tags ------------------------------------------------------------
drop policy if exists tenant_isolation_select on pop.contact_tags;
create policy tenant_isolation_select on pop.contact_tags
    for select
    using (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_insert on pop.contact_tags;
create policy tenant_isolation_insert on pop.contact_tags
    for insert
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_update on pop.contact_tags;
create policy tenant_isolation_update on pop.contact_tags
    for update
    using (tenant_id::text = current_setting('app.tenant', true))
    with check (tenant_id::text = current_setting('app.tenant', true));

drop policy if exists tenant_isolation_delete on pop.contact_tags;
create policy tenant_isolation_delete on pop.contact_tags
    for delete
    using (tenant_id::text = current_setting('app.tenant', true));

-- =============================================================================
-- Roles + grants
-- =============================================================================
-- pop_admin: BYPASSRLS, used by migrations, backups, tenant provisioning,
-- Pop DB → Supabase dual-write sync. Password intentionally NOT set here —
-- the ansible step immediately after this migration runs ALTER ROLE with the
-- POP_ADMIN_PASSWORD value fetched from Infisical. Never commit a password.
--
-- anon / authenticated / service_role are Supabase-managed and already exist
-- on any fresh Supabase Postgres install. We only grant them the minimum
-- schema/table access; RLS handles the actual per-row filtering.

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'pop_admin') then
        create role pop_admin with login bypassrls password null;
        raise notice 'created role pop_admin (password not set — apply ALTER ROLE from Infisical next)';
    else
        raise notice 'role pop_admin already exists — skipping create';
    end if;
end
$$;

grant usage on schema pop to pop_admin;
grant all on all tables    in schema pop to pop_admin;
grant all on all sequences in schema pop to pop_admin;
grant all on all functions in schema pop to pop_admin;
alter default privileges in schema pop grant all on tables    to pop_admin;
alter default privileges in schema pop grant all on sequences to pop_admin;
alter default privileges in schema pop grant all on functions to pop_admin;

-- anon + authenticated: usage + RLS-filtered CRUD on pop; SELECT on tenants only.
do $$
declare
    r text;
begin
    for r in select unnest(array['anon', 'authenticated']) loop
        if exists (select 1 from pg_roles where rolname = r) then
            execute format('grant usage on schema pop to %I', r);
            execute format('grant usage on schema public to %I', r);
            execute format('grant select, insert, update, delete on all tables in schema pop to %I', r);
            -- NOTE: the blanket grant above includes pop.tenants, but RLS on
            -- tenants (service_role-only policy) blocks anon/authenticated rows.
            execute format('revoke insert, update, delete on pop.tenants from %I', r);
            execute format('alter default privileges in schema pop grant select, insert, update, delete on tables to %I', r);
        end if;
    end loop;
end
$$;

drop policy if exists tenants_service_role_all on pop.tenants;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        create policy tenants_service_role_all on pop.tenants
            for all to service_role using (true) with check (true);
    end if;
end
$$;

-- service_role: full CRUD on pop + tenants (still RLS-filtered).
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant usage on schema pop to service_role;
        grant usage on schema public to service_role;
        grant select, insert, update, delete on all tables in schema pop to service_role;
        grant select, insert, update, delete on pop.tenants to service_role;
        alter default privileges in schema pop grant select, insert, update, delete on tables to service_role;
    end if;
end
$$;

-- =============================================================================
-- Migration marker
-- =============================================================================
-- Lightweight per-instance record of which migration files have been applied.
-- The ansible role's "check if pop schema exists" step is the primary
-- idempotency gate; this table gives operators a manual audit trail.

create table if not exists public.pop_migrations (
    id         serial primary key,
    version    text not null unique,
    applied_at timestamptz not null default now()
);

insert into public.pop_migrations (version)
    values ('001_pop_schema')
    on conflict (version) do nothing;
