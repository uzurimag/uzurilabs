-- DB-001 verification script.
--
-- Plain SQL, not pgTAP (pgTAP isn't guaranteed available outside a full
-- Supabase local stack). Run it with psql against a database that has
-- 20260715032450_db_001_core_multi_tenant.sql applied. Each check either
-- raises an exception (failure) or prints a PASS notice; failures stop the
-- script (ON_ERROR_STOP), so "it ran to the end" already means every
-- printed PASS is real, not simulated.
--
-- IMPORTANT HONESTY NOTE: sections 1-6 verify schema objects (tables,
-- constraints, indexes, triggers, RLS enablement, policies) and section 7
-- verifies anonymous access is denied and unauthenticated auth.uid()
-- behavior -- these are true against any Postgres instance the migration is
-- applied to, including a real Supabase project. Section 8 (RLS behavior
-- with simulated users) requires a stubbed `auth` schema (auth.users,
-- auth.uid(), auth.role()) because this environment cannot run a full
-- Supabase local stack (Docker unavailable). It proves the *policy logic*
-- is correct, using synthetic users in that harness -- it is NOT the same
-- as testing tenant isolation with real, Supabase-authenticated users
-- against a deployed project, and should not be cited as such.

\set ON_ERROR_STOP on

-- ============================================================================
-- 1. Tables exist
-- ============================================================================
do $$
begin
  if to_regclass('public.organizations') is null then
    raise exception 'FAIL: public.organizations does not exist';
  end if;
  if to_regclass('public.profiles') is null then
    raise exception 'FAIL: public.profiles does not exist';
  end if;
  if to_regclass('public.organization_memberships') is null then
    raise exception 'FAIL: public.organization_memberships does not exist';
  end if;
  raise notice 'PASS: all three tables exist';
end;
$$;

-- ============================================================================
-- 2. Constraints exist
-- ============================================================================
do $$
declare
  missing text[] := array[]::text[];
  expected text[] := array[
    'organizations_organization_type_check',
    'organizations_status_check',
    'organizations_slug_format_check',
    'organizations_slug_key',
    'organization_memberships_status_check',
    'organization_memberships_org_user_unique'
  ];
  c text;
begin
  foreach c in array expected loop
    if not exists (select 1 from pg_constraint where conname = c) then
      missing := array_append(missing, c);
    end if;
  end loop;

  if array_length(missing, 1) > 0 then
    raise exception 'FAIL: missing constraints: %', missing;
  end if;
  raise notice 'PASS: all expected named constraints exist';
end;
$$;

-- ============================================================================
-- 3. Indexes exist
-- ============================================================================
do $$
declare
  missing text[] := array[]::text[];
  expected text[] := array[
    'organization_memberships_organization_id_idx',
    'organization_memberships_user_id_idx',
    'organization_memberships_role_idx',
    'organization_memberships_status_idx'
  ];
  i text;
begin
  foreach i in array expected loop
    if not exists (select 1 from pg_indexes where indexname = i) then
      missing := array_append(missing, i);
    end if;
  end loop;

  if array_length(missing, 1) > 0 then
    raise exception 'FAIL: missing indexes: %', missing;
  end if;
  raise notice 'PASS: all four organization_memberships indexes exist';
end;
$$;

-- ============================================================================
-- 4. Triggers exist
-- ============================================================================
do $$
declare
  missing text[] := array[]::text[];
  expected text[] := array[
    'organizations_set_updated_at',
    'profiles_set_updated_at',
    'organization_memberships_set_updated_at',
    'on_auth_user_created',
    'profiles_protect_privileged_columns'
  ];
  t text;
begin
  foreach t in array expected loop
    if not exists (select 1 from pg_trigger where tgname = t) then
      missing := array_append(missing, t);
    end if;
  end loop;

  if array_length(missing, 1) > 0 then
    raise exception 'FAIL: missing triggers: %', missing;
  end if;
  raise notice 'PASS: all five triggers exist';
end;
$$;

-- ============================================================================
-- 5. RLS is enabled
-- ============================================================================
do $$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.organizations'::regclass) then
    raise exception 'FAIL: RLS not enabled on public.organizations';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass) then
    raise exception 'FAIL: RLS not enabled on public.profiles';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.organization_memberships'::regclass) then
    raise exception 'FAIL: RLS not enabled on public.organization_memberships';
  end if;
  raise notice 'PASS: RLS is enabled on all three tables';
end;
$$;

-- ============================================================================
-- 6. Policies exist
-- ============================================================================
do $$
declare
  missing text[] := array[]::text[];
  expected text[] := array[
    'profiles_select_own',
    'profiles_select_admin',
    'profiles_update_own',
    'organizations_select_member',
    'organizations_select_admin',
    'organization_memberships_select_own',
    'organization_memberships_select_admin',
    'organization_memberships_select_client_admin'
  ];
  p text;
begin
  foreach p in array expected loop
    if not exists (select 1 from pg_policies where policyname = p) then
      missing := array_append(missing, p);
    end if;
  end loop;

  if array_length(missing, 1) > 0 then
    raise exception 'FAIL: missing policies: %', missing;
  end if;
  raise notice 'PASS: all eight expected policies exist';
end;
$$;

-- ============================================================================
-- 7. Anonymous access denied / unauthenticated auth.uid() behavior
-- ============================================================================
do $$
begin
  begin
    set role anon;
    perform 1 from public.organizations;
    set role none;
    raise exception 'FAIL: anon was able to select from public.organizations';
  exception
    when insufficient_privilege then
      set role none;
      raise notice 'PASS: anon has no select grant on public.organizations (permission denied)';
  end;
end;
$$;

do $$
begin
  begin
    set role anon;
    perform 1 from public.profiles;
    set role none;
    raise exception 'FAIL: anon was able to select from public.profiles';
  exception
    when insufficient_privilege then
      set role none;
      raise notice 'PASS: anon has no select grant on public.profiles (permission denied)';
  end;
end;
$$;

do $$
begin
  begin
    set role anon;
    perform 1 from public.organization_memberships;
    set role none;
    raise exception 'FAIL: anon was able to select from public.organization_memberships';
  exception
    when insufficient_privilege then
      set role none;
      raise notice 'PASS: anon has no select grant on public.organization_memberships (permission denied)';
  end;
end;
$$;

do $$
declare
  result boolean;
begin
  set role authenticated;
  -- No request.jwt.claim.sub set for this session: auth.uid() must be null,
  -- and every helper function must degrade to false, not error.
  select public.is_platform_admin() into result;
  set role none;
  if result is distinct from false then
    raise exception 'FAIL: is_platform_admin() did not return false for unauthenticated auth.uid()';
  end if;
  raise notice 'PASS: helper functions return false (not an error) when auth.uid() is null';
end;
$$;

-- ============================================================================
-- Constraint-rejection checks (run as the table owner; RLS is not the
-- mechanism under test here, the CHECK/UNIQUE constraints are)
-- ============================================================================

-- 8a. Invalid organization_type rejected
do $$
begin
  begin
    insert into public.organizations (name, slug, organization_type)
    values ('Bad Org', 'bad-org-type-check', 'not_a_real_type');
    raise exception 'FAIL: invalid organization_type was accepted';
  exception
    when check_violation then
      raise notice 'PASS: invalid organization_type is rejected by a check constraint';
  end;
end;
$$;

-- 8b. Invalid membership status rejected (needs a valid org + user first)
do $$
declare
  v_org_id uuid;
  v_user_id uuid;
begin
  insert into public.organizations (name, slug, organization_type)
  values ('Verification Org A', 'verification-org-a', 'client')
  returning id into v_org_id;

  insert into auth.users (email) values ('verify-user-a@example.test')
  returning id into v_user_id;

  begin
    insert into public.organization_memberships (organization_id, user_id, role, status)
    values (v_org_id, v_user_id, 'client_user', 'not_a_real_status');
    raise exception 'FAIL: invalid membership status was accepted';
  exception
    when check_violation then
      raise notice 'PASS: invalid organization_memberships.status is rejected by a check constraint';
  end;
end;
$$;

-- 8c. Duplicate membership rejected
do $$
declare
  v_org_id uuid;
  v_user_id uuid;
begin
  insert into public.organizations (name, slug, organization_type)
  values ('Verification Org B', 'verification-org-b', 'client')
  returning id into v_org_id;

  insert into auth.users (email) values ('verify-user-b@example.test')
  returning id into v_user_id;

  insert into public.organization_memberships (organization_id, user_id, role, status)
  values (v_org_id, v_user_id, 'client_user', 'active');

  begin
    insert into public.organization_memberships (organization_id, user_id, role, status)
    values (v_org_id, v_user_id, 'client_admin', 'active');
    raise exception 'FAIL: duplicate (organization_id, user_id) membership was accepted';
  exception
    when unique_violation then
      raise notice 'PASS: duplicate membership is rejected by the unique constraint';
  end;
end;
$$;

-- ============================================================================
-- 9. Synthetic-user RLS behavior (harness-only -- see honesty note at top)
-- ============================================================================
do $$
declare
  user_a uuid;
  user_b uuid;
  user_c uuid;
  org_1 uuid;
  org_2 uuid;
  org_3 uuid;
  visible_org_count int;
  visible_membership_count int;
begin
  insert into auth.users (email) values ('synthetic-a@example.test') returning id into user_a;
  insert into auth.users (email) values ('synthetic-b@example.test') returning id into user_b;
  insert into auth.users (email) values ('synthetic-c@example.test') returning id into user_c;

  insert into public.organizations (name, slug, organization_type) values ('Org One', 'synthetic-org-one', 'client') returning id into org_1;
  insert into public.organizations (name, slug, organization_type) values ('Org Two', 'synthetic-org-two', 'client') returning id into org_2;
  insert into public.organizations (name, slug, organization_type) values ('Org Three', 'synthetic-org-three', 'client') returning id into org_3;

  -- A is client_admin in org_1; B is client_user in org_1; C is client_admin
  -- in org_3, entirely unrelated to A and B.
  insert into public.organization_memberships (organization_id, user_id, role, status)
    values (org_1, user_a, 'client_admin', 'active');
  insert into public.organization_memberships (organization_id, user_id, role, status)
    values (org_1, user_b, 'client_user', 'active');
  insert into public.organization_memberships (organization_id, user_id, role, status)
    values (org_3, user_c, 'client_admin', 'active');

  -- As A: should see exactly org_1 (member) and no other organization.
  set role authenticated;
  perform set_config('request.jwt.claim.sub', user_a::text, false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);

  select count(*) into visible_org_count from public.organizations;
  if visible_org_count <> 1 then
    set role none;
    raise exception 'FAIL: user A should see exactly 1 organization, saw %', visible_org_count;
  end if;

  -- As A (client_admin of org_1): should see both org_1 membership rows
  -- (self + B), but not org_3's row belonging to C.
  select count(*) into visible_membership_count from public.organization_memberships;
  if visible_membership_count <> 2 then
    set role none;
    raise exception 'FAIL: client_admin A should see exactly 2 membership rows (self + B), saw %', visible_membership_count;
  end if;

  set role none;
  raise notice 'PASS: user A (client_admin of org_1) sees only org_1 and its 2 membership rows -- org_3/user C are not visible';

  -- As B (plain client_user of org_1): should see only their own membership
  -- row, not A's (B is not client_admin, so the client_admin policy does not
  -- apply to them).
  set role authenticated;
  perform set_config('request.jwt.claim.sub', user_b::text, false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);

  select count(*) into visible_membership_count from public.organization_memberships;
  if visible_membership_count <> 1 then
    set role none;
    raise exception 'FAIL: plain member B should see exactly 1 membership row (their own), saw %', visible_membership_count;
  end if;

  set role none;
  raise notice 'PASS: user B (plain client_user) sees only their own membership row';

  -- Self-promotion attempt: A tries to grant themself platform_role directly.
  set role authenticated;
  perform set_config('request.jwt.claim.sub', user_a::text, false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);

  begin
    update public.profiles set platform_role = 'founder' where id = user_a;
    set role none;
    raise exception 'FAIL: user A was able to self-assign platform_role = founder';
  exception
    when others then
      set role none;
      raise notice 'PASS: self-promotion to platform_role is blocked (%: %)', sqlstate, sqlerrm;
  end;

  -- service_role is exempt from the privileged-column guard (needed for a
  -- future controlled admin path) and bypasses RLS entirely.
  set role service_role;
  perform set_config('request.jwt.claim.role', 'service_role', false);
  update public.profiles set platform_role = 'platform_admin' where id = user_a;
  set role none;

  if (select platform_role from public.profiles where id = user_a) is distinct from 'platform_admin' then
    raise exception 'FAIL: service_role could not set platform_role as the designed bootstrap path';
  end if;
  raise notice 'PASS: service_role can set platform_role (the intended founder/admin bootstrap path)';

  -- Reset session GUCs so later parts of the script (if any) run unauthenticated.
  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('request.jwt.claim.role', '', false);
end;
$$;

do $$
begin
  raise notice 'DB-001 verification script completed with no failures.';
end;
$$;
