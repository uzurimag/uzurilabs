# services

Clients and wrappers for external services (third-party APIs). Keep network/IO boundaries here rather than in components.

## supabase/

- `client.ts` — Supabase client for Browser/Client Components (`"use client"`).
- `server.ts` — Supabase client for Server Components and Server Actions. Reads/writes auth cookies via `next/headers`.

Both read `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Neither uses `SUPABASE_SERVICE_ROLE_KEY` — that key stays server-only and unused until a ticket specifically requires it.
