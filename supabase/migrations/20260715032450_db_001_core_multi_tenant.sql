-- DB-001: Core multi-tenant data model
--
-- Establishes the foundation for the UZURI Intelligence Platform's
-- multi-tenant model: organizations, one profile per authenticated user,
-- organization memberships, a shared role enum, RLS, and the narrowly
-- scoped helper functions RLS policies depend on.
--
-- Explicitly out of scope for this migration: invitations, projects,
-- Discovery/Assessment/Strategy/Blueprint tables, billing/Stripe tables,
-- storage buckets, audit logs, notifications, AI tables, and any frontend
-- administration screens. See docs/database/DB-001-core-multi-tenant-model.md.
--
-- Supabase Auth owns authenticated identities in auth.users. This
-- migration never creates a competing public users table -- public.profiles
-- is a strict 1:1 extension of auth.users, keyed by the same id.
--
-- gen_random_uuid() is built into Postgres 13+, but pgcrypto is created
-- defensively in case this migration ever runs against an older/minimal
-- Postgres instance where it isn't already available.
create extension if not exists pgcrypto;

-- ============================================================================
-- 1. ROLE ENUM
-- ============================================================================
--
-- public.app_role is shared by both profiles.platform_role (UZURI-wide,
-- platform-level privilege) and organization_memberships.role
-- (organization-scoped access). The two are deliberately different concepts
-- that happen to share a value set -- see the docs for the platform-role vs
-- organization-role distinction. Not every value is meaningful in both
-- contexts (e.g. "client_user" as a platform_role would be unusual), but a
-- single enum keeps role values consistent and avoids duplicated app_role
-- definitions drifting apart over time.
create type public.app_role as enum (
  'founder',
  'platform_admin',
  'consultant',
  'client_admin',
  'client_user',
  'viewer'
);

-- ============================================================================
-- 2. ORGANIZATIONS
-- ============================================================================
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  organization_type text not null,
  status text not null default 'active',
  industry text,
  website text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Intentionally no ON DELETE CASCADE / SET NULL here: an organization must
  -- keep its own lifecycle after its creator's auth.users row is removed.
  created_by uuid references auth.users (id),
  constraint organizations_organization_type_check check (
    organization_type in ('internal', 'client', 'partner')
  ),
  constraint organizations_status_check check (
    status in ('active', 'suspended', 'archived')
  ),
  -- Lowercase, URL-safe, hyphen-separated slug (e.g. "acme-consulting").
  -- No leading/trailing hyphens, no consecutive hyphens, no uppercase.
  constraint organizations_slug_format_check check (
    slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
  )
);

comment on table public.organizations is
  'Tenant organizations (internal UZURI, client, or partner). No automatic cascade delete -- archiving is done via status, not row deletion.';

-- ============================================================================
-- 3. PROFILES
-- ============================================================================
--
-- One row per auth.users row. id is the same UUID as auth.users.id (not a
-- separate surrogate key), enforced by both the FK and the PK being the
-- same column, so "one profile per authenticated user" is a hard invariant,
-- not just documentation.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  display_name text,
  avatar_url text,
  job_title text,
  phone text,
  timezone text,
  locale text not null default 'en',
  -- Platform-wide privilege only (founder / platform_admin / consultant).
  -- This is NOT where organization-level (client) access is granted or
  -- checked -- that always goes through organization_memberships. A row
  -- with platform_role = null is the normal case for a client user.
  platform_role public.app_role,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'One-to-one extension of auth.users. platform_role is platform-wide privilege only; organization access always goes through organization_memberships, never through this table alone.';
comment on column public.profiles.platform_role is
  'UZURI-wide privileged role (founder, platform_admin, consultant) or null. Never sufficient on its own to grant access to a specific organization''s data.';

-- ============================================================================
-- 4. ORGANIZATION MEMBERSHIPS
-- ============================================================================
create table public.organization_memberships (
  id uuid primary key default gen_random_uuid(),
  -- No ON DELETE CASCADE from organizations: matches "do not cascade-delete
  -- organizations automatically". Deleting an organization while memberships
  -- reference it is blocked (default NO ACTION) until those rows are
  -- explicitly handled -- there is no membership cleanup path in this ticket.
  organization_id uuid not null references public.organizations (id),
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.app_role not null,
  status text not null default 'active',
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  constraint organization_memberships_status_check check (
    status in ('invited', 'active', 'suspended', 'removed')
  ),
  -- A user may belong to many organizations, but only one membership row
  -- per organization.
  constraint organization_memberships_org_user_unique unique (organization_id, user_id)
);

comment on table public.organization_memberships is
  'Scopes a user''s role to a single organization. One row per (organization_id, user_id). Client/consultant access is always checked through this table, never through profiles.platform_role.';

create index organization_memberships_organization_id_idx
  on public.organization_memberships (organization_id);
create index organization_memberships_user_id_idx
  on public.organization_memberships (user_id);
create index organization_memberships_role_idx
  on public.organization_memberships (role);
create index organization_memberships_status_idx
  on public.organization_memberships (status);

-- ============================================================================
-- 5. SHARED updated_at TRIGGER
-- ============================================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'Reusable BEFORE UPDATE trigger function that stamps updated_at = now(). Applied to organizations, profiles, and organization_memberships.';

revoke execute on function public.set_updated_at() from public;

create trigger organizations_set_updated_at
  before update on public.organizations
  for each row execute function public.set_updated_at();

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger organization_memberships_set_updated_at
  before update on public.organization_memberships
  for each row execute function public.set_updated_at();

-- ============================================================================
-- 6. PROFILE CREATION TRIGGER (auth.users -> public.profiles)
-- ============================================================================
--
-- SECURITY IMPLICATIONS:
--
-- This function must be SECURITY DEFINER: it is fired by an INSERT on
-- auth.users, which happens under Supabase's internal auth role, not the
-- end user's own role. That role has no privilege to write to
-- public.profiles, so the function needs to run with the definer's (the
-- migration-running role's) privileges to perform the insert at all.
--
-- Because it is SECURITY DEFINER, `set search_path = pg_catalog, public` is
-- mandatory, not optional: without a pinned search_path, a caller able to
-- create objects earlier in an unpinned search_path (e.g. a same-named
-- function or table in a schema that resolves first) could hijack name
-- resolution inside this function and have it execute with the definer's
-- elevated privileges. Every identifier below is additionally schema-qualified
-- as defense in depth on top of the pinned search_path.
--
-- Privilege escalation is prevented structurally: this function only ever
-- reads from NEW (the just-inserted auth.users row) and only ever sets
-- public.profiles.id and, optionally, full_name from user-editable signup
-- metadata. It never sets platform_role, so no new account can grant itself
-- founder/platform_admin/consultant access via signup metadata. Founder
-- bootstrap is a separate, manual, admin-only step -- see
-- docs/database/DB-001-core-multi-tenant-model.md.
--
-- ON CONFLICT DO NOTHING makes this safe to re-run / idempotent if a profile
-- row already exists for the id (e.g. manual backfill before this trigger
-- existed).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    nullif(trim(both from (new.raw_user_meta_data ->> 'full_name')), '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'SECURITY DEFINER trigger: creates a public.profiles row after signup. Never assigns platform_role. See in-line comment for the full security rationale.';

revoke execute on function public.handle_new_user() from public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- 6b. PROFILE PRIVILEGED-COLUMN GUARD
-- ============================================================================
--
-- Row Level Security is row-level, not column-level: an RLS policy that lets
-- a user UPDATE their own profile row cannot, by itself, stop that same
-- statement from also changing platform_role, is_active, id, or created_at.
-- Per the ticket's own fallback instruction, that column-level restriction is
-- enforced here with a BEFORE UPDATE trigger instead of relying on RLS alone.
--
-- service_role (backend/admin code) is exempt via auth.role() = 'service_role'
-- so that legitimate administrative role changes (a future admin action or
-- server action, not implemented in this ticket) are not blocked by this
-- guard. Everything else -- including the row owner via the UPDATE policy
-- below -- is blocked from changing these four columns.
create or replace function public.protect_profile_privileged_columns()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if auth.role() = 'service_role' then
    return new;
  end if;

  if new.id is distinct from old.id then
    raise exception 'profiles.id cannot be changed';
  end if;

  if new.created_at is distinct from old.created_at then
    raise exception 'profiles.created_at cannot be changed';
  end if;

  if new.platform_role is distinct from old.platform_role then
    raise exception 'profiles.platform_role cannot be changed by the profile owner';
  end if;

  if new.is_active is distinct from old.is_active then
    raise exception 'profiles.is_active cannot be changed by the profile owner';
  end if;

  return new;
end;
$$;

comment on function public.protect_profile_privileged_columns() is
  'BEFORE UPDATE guard on public.profiles: blocks changes to id/created_at/platform_role/is_active from any role except service_role. Compensates for RLS being row-level, not column-level.';

revoke execute on function public.protect_profile_privileged_columns() from public;

create trigger profiles_protect_privileged_columns
  before update on public.profiles
  for each row execute function public.protect_profile_privileged_columns();

-- ============================================================================
-- 7. HELPER FUNCTIONS
-- ============================================================================
--
-- All four functions are SECURITY DEFINER. This is required to avoid
-- recursive RLS evaluation: each function is called from RLS policies on the
-- very tables it queries (profiles / organization_memberships), and if the
-- function's own internal query were SECURITY INVOKER it would itself be
-- subject to the calling policy, re-invoking the function, recursively.
-- SECURITY DEFINER makes the function's internal lookup bypass RLS instead
-- of triggering it again.
--
-- This does not create a privilege-escalation path: every function is
-- narrowly scoped to auth.uid() (the caller's own identity, taken from the
-- verified JWT, never a client-supplied value) or a caller-supplied
-- organization id used only to scope which of the CALLER's own rows are
-- checked. No function accepts or exposes another user's identity, and none
-- return any information beyond a boolean. EXECUTE is revoked from PUBLIC
-- and granted only to `authenticated`, since `anon` has no table grants that
-- would ever need these functions and `service_role` bypasses RLS entirely.
create or replace function public.is_platform_founder()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    (
      select p.platform_role = 'founder' and p.is_active
      from public.profiles p
      where p.id = auth.uid()
    ),
    false
  );
$$;

comment on function public.is_platform_founder() is
  'True only for the caller''s own active founder profile. False when auth.uid() is null. SECURITY DEFINER to avoid recursive RLS on profiles -- see section 7 comment.';

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  -- Founders are treated as a superset of platform_admin for the purposes of
  -- this function, so RLS policies that mean "founder or platform_admin" can
  -- call this single function instead of two.
  select coalesce(
    (
      select p.platform_role in ('founder', 'platform_admin') and p.is_active
      from public.profiles p
      where p.id = auth.uid()
    ),
    false
  );
$$;

comment on function public.is_platform_admin() is
  'True for the caller''s own active founder or platform_admin profile. False when auth.uid() is null. SECURITY DEFINER to avoid recursive RLS on profiles -- see section 7 comment.';

create or replace function public.is_org_member(target_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = target_org_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;

comment on function public.is_org_member(uuid) is
  'True when the caller has an active membership in target_org_id. False when auth.uid() is null. SECURITY DEFINER to avoid recursive RLS on organization_memberships -- see section 7 comment.';

create or replace function public.has_org_role(
  target_org_id uuid,
  allowed_roles public.app_role[]
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = target_org_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role = any (allowed_roles)
  );
$$;

comment on function public.has_org_role(uuid, public.app_role[]) is
  'True when the caller has an active membership in target_org_id with a role in allowed_roles. False when auth.uid() is null. SECURITY DEFINER to avoid recursive RLS -- see section 7 comment.';

revoke execute on function public.is_platform_founder() from public;
revoke execute on function public.is_platform_admin() from public;
revoke execute on function public.is_org_member(uuid) from public;
revoke execute on function public.has_org_role(uuid, public.app_role[]) from public;

grant execute on function public.is_platform_founder() to authenticated;
grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.has_org_role(uuid, public.app_role[]) to authenticated;

-- ============================================================================
-- 8. ENABLE ROW LEVEL SECURITY
-- ============================================================================
alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.organization_memberships enable row level security;

-- ============================================================================
-- 9. RLS POLICIES
-- ============================================================================

-- --- profiles ---------------------------------------------------------------

create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using (id = auth.uid());

create policy profiles_select_admin
  on public.profiles
  for select
  to authenticated
  using (public.is_platform_admin());

-- Column-level protection for platform_role/is_active/id/created_at is
-- enforced by the profiles_protect_privileged_columns trigger above, not by
-- this policy -- RLS alone cannot express "these specific columns are
-- read-only" (see section 6b).
create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- No insert policy: rows are created exclusively by the handle_new_user
-- trigger (SECURITY DEFINER, bypasses RLS). No delete policy: deleting a
-- profile is not a supported client operation in this ticket.

-- --- organizations -----------------------------------------------------------

create policy organizations_select_member
  on public.organizations
  for select
  to authenticated
  using (public.is_org_member(id));

create policy organizations_select_admin
  on public.organizations
  for select
  to authenticated
  using (public.is_platform_admin());

-- No insert/update/delete policy for `authenticated`: organization
-- creation/archival is a backend-only (service_role) operation until a
-- controlled admin path exists in a later ticket. This is intentional, not
-- an oversight -- see docs/database/DB-001-core-multi-tenant-model.md.

-- --- organization_memberships -------------------------------------------------

create policy organization_memberships_select_own
  on public.organization_memberships
  for select
  to authenticated
  using (user_id = auth.uid());

create policy organization_memberships_select_admin
  on public.organization_memberships
  for select
  to authenticated
  using (public.is_platform_admin());

-- Safe to add now (unlike a naive version of this policy) only because
-- has_org_role() is SECURITY DEFINER and therefore does not recursively
-- re-evaluate this same policy while it looks up the caller's own role.
create policy organization_memberships_select_client_admin
  on public.organization_memberships
  for select
  to authenticated
  using (public.has_org_role(organization_id, array['client_admin']::public.app_role[]));

-- No insert/update/delete policy for `authenticated`: a user must never be
-- able to insert their own membership, change their own role, or remove
-- another member's row from the browser. Membership management is
-- backend-only (service_role) until a controlled, narrowly scoped path
-- (e.g. accepting an invitation) is designed in a later ticket.

-- ============================================================================
-- 10. GRANTS
-- ============================================================================
--
-- `anon` gets no grants at all on these tenant tables -- there is no
-- anonymous use case for organization/profile/membership data, so the
-- absence of a grant is the enforcement, not just RLS. `authenticated` gets
-- only the operations an RLS policy above actually supports: select on all
-- three tables, plus update on profiles (further restricted by the trigger
-- in section 6b). `service_role` is Supabase's backend-only role -- it
-- already bypasses RLS via its `bypassrls` attribute and has schema-level
-- privileges from Supabase's default project setup; no additional grants are
-- defined here, and this key must never be shipped to browser code (enforced
-- at the application layer -- see services/supabase/server.ts).
revoke all on public.organizations from anon, authenticated;
revoke all on public.profiles from anon, authenticated;
revoke all on public.organization_memberships from anon, authenticated;

grant select on public.organizations to authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.organization_memberships to authenticated;
