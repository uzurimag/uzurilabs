# supabase/tests

Plain SQL verification scripts for the database schema — not pgTAP (not guaranteed available outside a full Supabase local stack). Run with `psql` against a database that has the corresponding migration applied; each script raises an exception on the first failed check, so reaching the final notice means every printed `PASS` is real.

- `db_001_verification.sql` — verifies DB-001 (tables, constraints, indexes, triggers, RLS, policies, grants, and RLS behavior against synthetic users). See `docs/database/DB-001-core-multi-tenant-model.md` for the honesty notes on what this can and cannot prove without a full Supabase stack.
