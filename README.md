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
services/             Clients/wrappers for external services (e.g. future Supabase client)
types/                Shared TypeScript types
public/               Static assets served as-is
tests/                Test specs (no test framework wired up yet — see Outstanding issues)
docs/                 Project documentation and ADRs
supabase/migrations/  SQL migrations for the future Supabase integration
```

## Environment variables

Copy `.env.example` to `.env.local` and fill in real values. `.env.local` (and all other real `.env*` files) are git-ignored; only `.env.example`, which contains placeholders only, is committed.

## Supabase

This repository is prepared for a future Supabase integration (`services/`, `types/`, and `supabase/migrations/` exist for that purpose, and `.env.example` lists the expected variable names). No Supabase client, authentication, or database schema is implemented in this ticket — that is deliberately out of scope.

## Deploying

This is a standard Next.js App Router project and deploys to [Vercel](https://vercel.com) with zero additional configuration — connect the repository in the Vercel dashboard and set the environment variables from `.env.example` with real values. No production domain has been connected as part of this ticket.

## Outstanding / next steps

- No test framework is configured yet. Recommended: Vitest + React Testing Library for unit tests, and/or Playwright for e2e, with specs under `tests/`.
- Supabase client, auth, and database schema/migrations are intentionally not implemented here.
- `package-lock.json` is committed locally but was too large to push through this session's API-based push path; run `npm install` after cloning to regenerate it if it's missing on the remote.
