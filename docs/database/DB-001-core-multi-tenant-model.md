# DB-001 — Core Multi-Tenant Data Model

Migration: `supabase/migrations/20260715032450_db_001_core_multi_tenant.sql`
Verification: `supabase/tests/db_001_verification.sql`
Applying/verifying against the real development project: `docs/database/DB-001A-apply-verify-runbook.md`

## Purpose

Establishes the foundational multi-tenant schema for the UZURI Intelligence Platform: organizations, one profile per authenticated user, organization memberships, a shared role enum, RLS, and the helper functions RLS policies depend on. It deliberately does **not** implement invitations, business modules (projects, Discovery, Assessments, Strategy, Blueprint), billing/Stripe, storage, audit logs, notifications, AI tables, or any frontend administration screens — those are later tickets.

## Entity relationship summary

```
auth.users
    1 ─── 1  profiles

auth.users
    1 ─── many  organization_memberships

organizations
    1 ─── many  organization_memberships
```

`profiles.id` and `auth.users.id` are the same UUID (not a separate surrogate key), so the 1:1 relationship is a hard invariant enforced by the primary key/foreign key being identical, not just a convention.

## Tables

### `public.organizations`

A tenant: internal (UZURI itself), a client, or a partner. `status` (`active` / `suspended` / `archived`) governs lifecycle instead of row deletion — there is no cascading delete from organizations, by design (deleting an organization with existing memberships is blocked by the membership table's foreign key until those rows are explicitly handled, which this ticket does not implement).

### `public.profiles`

A strict one-to-one extension of `auth.users`, created automatically by the `handle_new_user` trigger on signup. Holds display/contact metadata and `platform_role` — **platform-wide** privilege only (see "Platform role vs. organization role" below).

### `public.organization_memberships`

The only place organization-scoped (client) access is granted. One row per `(organization_id, user_id)` pair (enforced by a unique constraint); a user may belong to many organizations, never more than once each.

## Why `auth.users` is not duplicated

Supabase Auth owns authenticated identity in `auth.users`. This migration never creates a competing `public.users` table — `public.profiles` only ever adds application-specific columns on top of the identity Supabase already manages, keyed by the same `id`. Duplicating user identity into a second table is a common source of drift (two records that can disagree about who a user is) and is explicitly avoided here.

## Platform role vs. organization role

`public.app_role` is a single enum shared by two different concepts:

- **`profiles.platform_role`** — UZURI-wide privilege: `founder`, `platform_admin`, or `consultant` (in the platform-wide sense). Most users have `platform_role = null`. This column is never sufficient by itself to grant access to any specific organization's data.
- **`organization_memberships.role`** — access scoped to one organization: `client_admin`, `client_user`, `viewer`, or (for a consultant's engagement-specific access) other values from the same enum.

Client/consultant access to a given organization's data is **always** checked through `organization_memberships`, never inferred from `profiles.platform_role` alone. The helper functions in the migration (`is_org_member`, `has_org_role`) exist specifically to keep that check consistent everywhere instead of re-implemented ad hoc per policy.

## RLS approach

RLS is enabled on all three tables with no anonymous access (`anon` has no grants at all — enforced at the GRANT level, not only by policy). The full set of policies:

| Table                      | Policy                                         | Allows                                                                   |
| -------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------ |
| `profiles`                 | `profiles_select_own`                          | a user to select their own row                                           |
| `profiles`                 | `profiles_select_admin`                        | founder/platform_admin to select all rows                                |
| `profiles`                 | `profiles_update_own`                          | a user to update their own row                                           |
| `organizations`            | `organizations_select_member`                  | a user to select organizations they're an active member of               |
| `organizations`            | `organizations_select_admin`                   | founder/platform_admin to select all organizations                       |
| `organization_memberships` | `organization_memberships_select_own`          | a user to select their own membership rows                               |
| `organization_memberships` | `organization_memberships_select_admin`        | founder/platform_admin to select all membership rows                     |
| `organization_memberships` | `organization_memberships_select_client_admin` | a `client_admin` to select all membership rows in their own organization |

No `insert`/`update`/`delete` policy exists for `authenticated` on `organizations` or `organization_memberships` in this ticket — organization creation and membership management are backend-only (`service_role`) operations until a controlled, narrowly scoped path (e.g. an invitation-acceptance flow) is designed in a later ticket. This is intentional, not an oversight: the ticket's brief explicitly says not to allow direct browser insert/update/delete for these tables yet.

### Why the helper functions are `SECURITY DEFINER`

`is_platform_founder`, `is_platform_admin`, `is_org_member`, and `has_org_role` are all `SECURITY DEFINER`. Each is called from RLS policies on the very tables it queries (`profiles`, `organization_memberships`); if their internal queries were `SECURITY INVOKER`, they would themselves be subject to the calling policy, re-invoking the function recursively. `SECURITY DEFINER` makes each function's internal lookup bypass RLS instead of re-triggering it. This does not create a privilege-escalation path: every function is scoped to `auth.uid()` (the caller's own verified identity) or a caller-supplied organization id used only to scope which of the _caller's own_ rows are checked — no function accepts or exposes another user's identity, and none return anything beyond a boolean. `EXECUTE` is revoked from `PUBLIC` and granted only to `authenticated`.

### Column-level protection beyond RLS

RLS is row-level, not column-level: the `profiles_update_own` policy that lets a user update their own row cannot, by itself, stop that same statement from also setting `platform_role`, `is_active`, `id`, or `created_at`. Per the ticket's own fallback instruction, this is enforced with a `BEFORE UPDATE` trigger (`protect_profile_privileged_columns`) instead: it blocks changes to those four columns from any role except `service_role`. This is real backend enforcement, not merely a documented convention.

### `handle_new_user` security notes

`handle_new_user` is `SECURITY DEFINER` because it fires on `INSERT INTO auth.users`, which happens under Supabase's internal auth role — a role with no privilege to write to `public.profiles`. Because it's `SECURITY DEFINER`, `set search_path = pg_catalog, public` is load-bearing, not cosmetic: without a pinned search path, an object created earlier in an unpinned search path could hijack name resolution inside the function and have it execute with the definer's elevated privileges. It only ever reads `NEW` (the just-inserted `auth.users` row) and sets `id` and optionally `full_name` — it never assigns `platform_role`, so no signup can grant itself privileged access.

## Founder bootstrap process

No real Founder email or user ID is hardcoded anywhere in this migration or any seed file — none exists. The first Founder is bootstrapped **after** authentication exists (a later ticket), as a manual, admin-only step:

1. The person who will be the Founder signs up normally through the application's real auth flow, creating an `auth.users` row (and, via `handle_new_user`, a `profiles` row with `platform_role = null`).
2. An operator with direct database access (using the `service_role` credential or a direct Postgres connection — never the browser) obtains that user's `auth.users.id`.
3. The operator runs a single, explicit, manually-reviewed statement — not part of any migration or seed file:
   ```sql
   update public.profiles set platform_role = 'founder' where id = '<the-real-uuid>';
   ```
   This succeeds because `service_role` is exempt from the `protect_profile_privileged_columns` guard (see above); the same statement attempted as the row owner is rejected.
4. The action is recorded in an audit trail once an audit log table exists (explicitly out of scope for this ticket — see "Next-ticket dependencies").

No seed file was created for this ticket. If one is added later for local development, it must use synthetic test data only, never a real email or production UUID.

## Known limitations

- No `insert`/`update`/`delete` path exists yet for `organizations` or `organization_memberships` through RLS — those operations are backend-only until a later ticket designs a safe, narrow path (e.g. org creation, invitation acceptance).
- `organization_memberships_select_client_admin` is the only "view my org's members" policy implemented; broader client-facing membership management (invite, remove, change role) is not implemented.
- Column-level protection on `profiles` relies on a trigger, not RLS itself, because Postgres RLS cannot express column-level restrictions directly.
- Tenant isolation has been verified against **synthetic users in a hand-rolled local Postgres harness** (see "Testing method" below) — not against real, Supabase-authenticated users in a deployed project. Re-verification against a real Supabase project (local via Docker, or a hosted dev project) is recommended before this is relied upon in production.
- `auth.role()` is trusted for the `service_role` bypass in `protect_profile_privileged_columns`; this is standard Supabase practice (PostgREST sets this GUC from the verified JWT) but has not been exercised against real Supabase infrastructure in this ticket.

## Testing method (read this before citing "tested")

Docker was unavailable in the environment this migration was authored in (`docker info` fails to reach the daemon), so `supabase start` / a full local Supabase stack could not be run. To still get real evidence rather than a claim, the migration was applied to a genuine local **PostgreSQL 16** instance (not Supabase, not a mock) against a hand-rolled stub of the specific parts of a Supabase project this migration depends on:

- an `auth.users` table (id, email, `raw_user_meta_data`, `created_at`),
- `auth.uid()` / `auth.role()` functions reading the same `request.jwt.claim.*` session GUCs Supabase's real PostgREST layer sets per request,
- the `anon`, `authenticated`, and `service_role` Postgres roles, with `service_role` granted the broad table privileges Supabase provisions automatically at the project level (outside of any user migration).

Against that harness:

- the migration file applied with **zero errors**, unmodified;
- `supabase/tests/db_001_verification.sql` ran to completion with **zero failures** — table/constraint/index/trigger existence, RLS enablement, policy existence, anonymous access denial, `auth.uid() is null` degrade-to-false behavior, and rejection of invalid `organization_type`, invalid membership `status`, and duplicate memberships were all confirmed against the real Postgres engine;
- RLS policy _logic_ was additionally exercised with three synthetic `auth.users` rows and role-switching (`SET ROLE authenticated` plus the matching JWT-claim GUCs) to confirm: a `client_admin` sees only their own organization and its membership rows (not an unrelated organization's); a plain member sees only their own membership row; a user cannot self-assign `platform_role`; and `service_role` can, via the intended bootstrap path.

**This is not the same as testing against real Supabase infrastructure or real authenticated users**, and is not cited as such anywhere in this ticket's completion report. See the completion report for the exact status label used (`Applied locally`, not `Applied to development Supabase` or `Tested and passed` in the full sense).

## Type generation

Not run in this environment: `supabase gen types typescript` — even invoked with `--db-url` against a real, reachable Postgres instance — still shells out to Docker internally in this CLI version, and Docker is unavailable here. No types were fabricated. Once a local Supabase stack (via Docker) or a linked development project is available:

```bash
supabase gen types typescript --local > types/supabase.ts
# or
supabase gen types typescript --linked > types/supabase.ts
```

## Rollback considerations

This migration has no down-migration file (consistent with Supabase's forward-only migration convention). To reverse it manually, in dependency order:

```sql
drop policy if exists organization_memberships_select_client_admin on public.organization_memberships;
drop policy if exists organization_memberships_select_admin on public.organization_memberships;
drop policy if exists organization_memberships_select_own on public.organization_memberships;
drop policy if exists organizations_select_admin on public.organizations;
drop policy if exists organizations_select_member on public.organizations;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists profiles_select_admin on public.profiles;
drop policy if exists profiles_select_own on public.profiles;

drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists profiles_protect_privileged_columns on public.profiles;
drop trigger if exists organization_memberships_set_updated_at on public.organization_memberships;
drop trigger if exists profiles_set_updated_at on public.profiles;
drop trigger if exists organizations_set_updated_at on public.organizations;

drop function if exists public.has_org_role(uuid, public.app_role[]);
drop function if exists public.is_org_member(uuid);
drop function if exists public.is_platform_admin();
drop function if exists public.is_platform_founder();
drop function if exists public.protect_profile_privileged_columns();
drop function if exists public.handle_new_user();
drop function if exists public.set_updated_at();

drop table if exists public.organization_memberships;
drop table if exists public.profiles;
drop table if exists public.organizations;

drop type if exists public.app_role;
```

Rolling back after real organization/profile/membership data exists would destroy that data — this is only safe against an empty or purely-synthetic database, e.g. before this ticket's migration has been used for anything real.

## Next-ticket dependencies

- Login/session UI and the real Supabase auth flow (this ticket only prepares the data model; no login screen exists yet).
- A controlled admin/backend path for organization creation and archival.
- A controlled path for inviting, removing, and changing the role of organization members (currently backend-only).
- An audit log table, so the founder bootstrap step and future privileged actions have a durable record.
- Re-running this ticket's verification against a real Supabase project (local via Docker, or a hosted development project) once Docker is available.
