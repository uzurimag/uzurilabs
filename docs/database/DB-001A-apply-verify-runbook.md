# DB-001A — Apply & Verify Runbook (run on your own machine)

This is a command runbook, not something executed by the assistant in this
session — the session has no Supabase project link and no credentials, and
none should be placed in this repository or in chat. Run every command
below yourself, locally, where your Supabase CLI session and secrets
already live.

Contains no secrets. Every command below either prompts you interactively
or reads from your own shell environment/`.env.local` — never from a
committed file.

## Prerequisites

- Supabase CLI installed (this repo was authored against v2.109.1 — `npx supabase --version` to check yours).
- You know your project ref (the string in your project's dashboard URL, e.g. `abcdefghijklmnop`). Not a secret.
- You're prepared to enter your database password interactively when prompted (or have `SUPABASE_ACCESS_TOKEN` set in your own shell) — never paste it into a file in this repo or into chat.

## 1. Log in and link (read/write to your local CLI config only — no remote change yet)

```bash
supabase login
supabase link --project-ref <your-project-ref>
```

`link` will prompt for your database password on the terminal; it is not echoed and is not written anywhere in this repository.

## 2. Inspect what would be applied (read-only — safe)

```bash
supabase migration list
```

Confirm the only pending migration is `20260715032450_db_001_core_multi_tenant.sql` and that nothing unexpected shows up (e.g. a migration you didn't author, or one already partially applied).

---

## STOP — confirm before proceeding

The next command changes the real development database. Only run it once you've confirmed step 2 looks correct and you're pointed at the **development** project, not anything else.

---

## 3. Apply the migration

```bash
supabase db push
```

This applies `20260715032450_db_001_core_multi_tenant.sql` (and only that file, since it's the only one in `supabase/migrations/`) to the linked project.

## 4. Verify the schema landed correctly (read-only)

Open the linked project's SQL editor (or `supabase db execute` / `psql` using your own connection string) and run `supabase/tests/db_001_verification.sql` **sections 1–7 only** (tables, constraints, indexes, triggers, RLS enabled, policies exist, anon denied, `auth.uid()` null behavior). Skip section 8/9 of that file — those sections create and drop a `auth` schema stub and synthetic-user harness that only exists in a hand-rolled local Postgres, not in a real Supabase project; running them against real Supabase would fail (there's already a real `auth` schema) or is simply unnecessary since real `auth.uid()`/`auth.role()` already exist.

Alternatively, run these individually via the SQL editor:

```sql
select to_regclass('public.organizations'), to_regclass('public.profiles'), to_regclass('public.organization_memberships');
select typname from pg_type where typname = 'app_role';
select tgname from pg_trigger where tgname in ('organizations_set_updated_at','profiles_set_updated_at','organization_memberships_set_updated_at','on_auth_user_created','profiles_protect_privileged_columns');
select proname from pg_proc where proname in ('set_updated_at','handle_new_user','protect_profile_privileged_columns','is_platform_founder','is_platform_admin','is_org_member','has_org_role');
select relname, relrowsecurity from pg_class where relname in ('organizations','profiles','organization_memberships');
select policyname, tablename from pg_policies where schemaname = 'public';
```

For the anon-denied check, run as the `anon` role specifically (the SQL editor runs as a privileged role by default, so this needs an explicit role switch):

```sql
set role anon;
select 1 from public.organizations limit 1; -- expect: permission denied
reset role;
```

## 5. Create synthetic test users (development project only — never real client data)

Use the Auth Admin API with your own `service_role` key, kept in your own shell environment, never committed:

```bash
export SUPABASE_URL="https://<your-project-ref>.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="<kept only in your shell, never in a file>"

for user in db001a-test-a db001a-test-b db001a-test-c; do
  curl -s -X POST "$SUPABASE_URL/auth/v1/admin/users" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"$user@example.test\", \"password\": \"$(openssl rand -base64 24)\", \"email_confirm\": true}"
done
```

Record the returned `id` (UUID) for each of the three users — you'll need them below. Emails use the reserved `example.test` domain and random passwords; this is synthetic data only.

## 6. Run the behavioral tests

In the SQL editor (or `psql`), using the three UUIDs from step 5 as `user_a` / `user_b` / `user_c`:

```sql
-- Set up synthetic orgs + memberships (mirrors supabase/tests/db_001_verification.sql section 9)
insert into public.organizations (name, slug, organization_type) values ('DB-001A Org One', 'db001a-org-one', 'client') returning id; -- note as org_1
insert into public.organizations (name, slug, organization_type) values ('DB-001A Org Three', 'db001a-org-three', 'client') returning id; -- note as org_3

insert into public.organization_memberships (organization_id, user_id, role, status) values ('<org_1>', '<user_a>', 'client_admin', 'active');
insert into public.organization_memberships (organization_id, user_id, role, status) values ('<org_1>', '<user_b>', 'client_user', 'active');
insert into public.organization_memberships (organization_id, user_id, role, status) values ('<org_3>', '<user_c>', 'client_admin', 'active');
```

Then, for each behavior, `set local role authenticated;` plus the matching JWT-claim GUC before the check, e.g.:

```sql
-- Own-profile access: A can see their own profile
set local role authenticated;
set local request.jwt.claim.sub = '<user_a>';
select * from public.profiles where id = '<user_a>'; -- expect: 1 row

-- Unauthorized profile access denied: A cannot see B's profile
select * from public.profiles where id = '<user_b>'; -- expect: 0 rows

-- Membership visibility: A (client_admin of org_1) sees both org_1 rows
select count(*) from public.organization_memberships; -- expect: 2

-- Cross-organization access denied: A cannot see org_3 or its membership row
select count(*) from public.organizations; -- expect: 1 (org_1 only)

-- Self-role promotion denied
update public.profiles set platform_role = 'founder' where id = '<user_a>'; -- expect: error

-- Duplicate membership rejected
insert into public.organization_memberships (organization_id, user_id, role, status) values ('<org_1>', '<user_a>', 'client_user', 'active'); -- expect: unique_violation

-- Invalid enum/check values rejected
insert into public.organizations (name, slug, organization_type) values ('Bad', 'db001a-bad', 'not_a_real_type'); -- expect: check_violation
insert into public.organization_memberships (organization_id, user_id, role, status) values ('<org_1>', '<user_b>', 'client_user', 'not_a_real_status'); -- expect: check_violation
```

For founder/admin access behavior, promote one synthetic user via `service_role` (the only path that's allowed to):

```sql
set role service_role; -- or reset role if already privileged in the SQL editor
update public.profiles set platform_role = 'platform_admin' where id = '<user_c>';
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '<user_c>';
select count(*) from public.organizations; -- expect: all organizations, not just org_3
```

## 7. Clean up the synthetic data

```sql
delete from public.organization_memberships where organization_id in ('<org_1>', '<org_3>');
delete from public.organizations where slug in ('db001a-org-one', 'db001a-org-three', 'db001a-bad');
```

Delete the three synthetic auth users via the dashboard (Authentication → Users) or the Admin API's `DELETE /auth/v1/admin/users/<id>`.

## 8. Report back

For each of the 8 behaviors in step 6, plus the schema checks in step 4, note pass/fail. That record — not a claim from this session — is what should replace "Not tested" in the DB-001A completion report.
