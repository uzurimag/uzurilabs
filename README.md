# UZURI Intelligence Platform™

Engineering foundation for the UZURI Intelligence Platform — a Next.js (App Router) + TypeScript + Tailwind CSS application.

## Stack

- [Next.js](https://nextjs.org) (App Router) — React framework
- TypeScript
- Tailwind CSS v4
- ESLint (`eslint-config-next`)
- Prettier (with `prettier-plugin-tailwindcss` for class sorting)

## Prerequisites

- Node.js `>= 20.9.0`
- npm

## Local setup

```bash
npm install
cp .env.example .env.local   # fill in real values locally; never commit .env.local
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Scripts

| Command                | Purpose                                  |
| ---------------------- | ---------------------------------------- |
| `npm run dev`          | Start the local dev server               |
| `npm run build`        | Production build                         |
| `npm run start`        | Serve the production build locally       |
| `npm run lint`         | Run ESLint                               |
| `npm run typecheck`    | Run the TypeScript compiler (`--noEmit`) |
| `npm run format`       | Format the codebase with Prettier        |
| `npm run format:check` | Check formatting without writing changes |

## Directory layout

```
app/                  Next.js App Router routes, layouts, and pages
components/           Shared, reusable UI components
features/             Feature-based modules (components, hooks, logic per feature)
lib/                  Framework-agnostic utilities and helpers
services/             Clients/wrappers for external services (includes services/supabase/)
types/                Shared TypeScript types
public/               Static assets served as-is
tests/                Test specs (no test framework wired up yet — see Outstanding issues)
docs/                 Project documentation and ADRs
supabase/migrations/  SQL migrations for the future Supabase integration
```

## Environment variables

Copy `.env.example` to `.env.local` and fill in real values. `.env.local` (and all other real `.env*` files) are git-ignored; only `.env.example`, which contains placeholders only, is committed.

## Supabase

The app is connected to a Supabase project at the client level (`services/supabase/client.ts` for Browser/Client Components, `services/supabase/server.ts` for Server Components and Server Actions, `services/supabase/proxy.ts` for session refresh in `proxy.ts`). Email/password authentication is implemented (see "Authentication" below); RBAC, invitations, and organization onboarding are not yet.

### Get your project values

1. Open your project at [supabase.com/dashboard](https://supabase.com/dashboard).
2. Go to **Settings > API**.
3. Copy the **Project URL** and the **publishable** key. Leave the **service_role** key alone unless a future ticket explicitly calls for it — it bypasses Row Level Security.

### Populate `.env.local`

```bash
cp .env.example .env.local
```

Fill in:

| Variable                               | Visibility              | Description                                                                                                               |
| -------------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `NEXT_PUBLIC_SUPABASE_URL`             | Public (browser-safe)   | Your Supabase project's API URL.                                                                                          |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Public (browser-safe)   | The publishable key. Safe to ship to the browser — access is governed by RLS, not secrecy.                                |
| `SUPABASE_SERVICE_ROLE_KEY`            | **Server-only, secret** | Bypasses RLS. Never prefix with `NEXT_PUBLIC_`, never import into client components, and unused by this codebase for now. |

Any variable prefixed `NEXT_PUBLIC_` is bundled into browser JavaScript by Next.js; anything without that prefix stays server-only and is never sent to the client.

### Run the connection check

With `.env.local` populated, start the dev server and visit the development-only diagnostic page:

```bash
npm run dev
```

Open [http://localhost:3000/dev/supabase-check](http://localhost:3000/dev/supabase-check). It reports, without printing any secret values:

- whether `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` are configured
- whether the server Supabase client initializes
- whether the browser Supabase client initializes
- whether a real, unauthenticated request actually reaches the configured Supabase project (`Connection successful` / `Connection failed`, plus a sanitized error category such as `network` or `configuration` — never a key, token, or raw error message)

This route 404s when `NODE_ENV=production` and should be deleted once the Supabase integration is further along.

## Authentication

Email/password sign-in, sign-out, and password recovery are implemented (`/login`, `/forgot-password`, `/reset-password`, `/auth/callback`, `/auth/error`, and a minimal protected `/dashboard` placeholder). Public self-registration does not exist — accounts are created manually in the Supabase dashboard (invitation-only). See `docs/auth/ENG-002-authentication-and-sessions.md` for the full design and `docs/auth/ENG-002-testing-runbook.md` to configure and test it against a real Supabase project.

## Deploying

This is a standard Next.js App Router project and deploys to [Vercel](https://vercel.com) with zero additional configuration — connect the repository in the Vercel dashboard and set the environment variables from `.env.example` with real values. No production domain has been connected as part of this ticket.

## Outstanding / next steps

- No test framework is configured yet. Recommended: Vitest + React Testing Library for unit tests, and/or Playwright for e2e, with specs under `tests/`.
- Supabase auth, database schema/migrations, RLS policies, storage, Stripe, and Resend are intentionally not implemented here.
- `package-lock.json` is committed locally but was too large to push through this session's API-based push path; run `npm install` after cloning to regenerate it if it's missing on the remote.
