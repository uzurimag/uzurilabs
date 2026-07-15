# supabase/migrations

SQL migration files for the Supabase database, managed via the Supabase CLI (`supabase migration new <name>`).

## `20260715032450_db_001_core_multi_tenant.sql`

The foundational multi-tenant data model: `organizations`, `profiles` (1:1 with `auth.users`), `organization_memberships`, the shared `app_role` enum, RLS, and the helper functions RLS policies depend on. See `docs/database/DB-001-core-multi-tenant-model.md` for full documentation, the founder bootstrap process, and known limitations.

## Applying migrations

```bash
supabase start          # requires Docker
supabase db reset       # applies all migrations to the local database
```

## Generating types

Once a local or linked Supabase project is reachable:

```bash
supabase gen types typescript --local > types/supabase.ts
# or, against a linked project:
supabase gen types typescript --linked > types/supabase.ts
```

See `docs/database/DB-001-core-multi-tenant-model.md` for why this hasn't been run yet in this environment.
