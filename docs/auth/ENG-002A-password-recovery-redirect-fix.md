# ENG-002A — Fix Password Recovery Redirect

## Symptom

The live password-reset email opened the deployed homepage (`https://uzurilabs-platform-zeta.vercel.app/`) instead of `/reset-password`.

## Root cause

`app/forgot-password/actions.ts` built `resetPasswordForEmail`'s `redirectTo` from `process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000"`. `NEXT_PUBLIC_APP_URL` was never configured in Vercel's production environment (`.env.example` only ever documented the localhost value), so in production this fell back to `http://localhost:3000` — producing:

```
http://localhost:3000/auth/callback?next=/reset-password
```

That URL is both unreachable for a real visitor and (most likely) not present in the Supabase project's Redirect URLs allow-list. Supabase's GoTrue rejects a `redirectTo` that isn't allow-listed and falls back to the project's **Site URL** instead — which, for the production project, is presumably the deployed homepage. That fallback is what actually produced the reported symptom: the browser was never sent to `/auth/callback` at all in production, so no code in this repository was executing incorrectly at the point of failure — the wrong URL was constructed one step earlier, before Supabase ever saw the request.

## Fix

`lib/app-url.ts` (new): `getAppUrl()` returns the exact required production origin (`https://uzurilabs-platform-zeta.vercel.app`) whenever `NODE_ENV === "production"`, **unconditionally** — no longer dependent on `NEXT_PUBLIC_APP_URL` being configured correctly in Vercel. Non-production (local dev) still derives the origin from `NEXT_PUBLIC_APP_URL`, falling back to `http://localhost:3000` if unset, unchanged from before.

`app/forgot-password/actions.ts` now calls `getAppUrl()` instead of reading the env var directly.

`app/auth/callback/route.ts`: the fallback used when `next` is missing/invalid was already `/dashboard`, never `/` — confirmed and given an explicit named constant (`DEFAULT_CALLBACK_REDIRECT`) with a comment stating the invariant, so a future edit can't accidentally reintroduce a `/` default. No behavioral change here; this was already correct.

## Verified locally (no real Supabase project — see limitations)

```
$ NODE_ENV=production, NEXT_PUBLIC_APP_URL unset
getAppUrl() -> https://uzurilabs-platform-zeta.vercel.app
resetPasswordForEmail redirectTo -> https://uzurilabs-platform-zeta.vercel.app/auth/callback?next=/reset-password
```

`/auth/callback` with no `code` → redirects to `/auth/error`. `/auth/callback` with an invalid `code` (exchange fails) → redirects to `/auth/error`, **even when a malicious `next` is supplied** (`next=https://evil.example.com` still lands on `/auth/error`, never the external URL — the failure path never reaches the point where `next` would be used). `/login`, `/dashboard`'s signed-out redirect, and the absence of `/signup`/`/register` are all unchanged.

**Not verified:** the actual production email link, end to end, since this session has no credentials for the real Supabase project or Vercel deployment. See "Required manual action" below.

## Required manual action (cannot be done from this session)

The Supabase **production** project's Redirect URLs allow-list must include:

```
https://uzurilabs-platform-zeta.vercel.app/auth/callback
```

If it doesn't already, the code fix alone will not resolve the symptom — Supabase will keep falling back to Site URL regardless of what `redirectTo` the app sends, because the fallback happens on Supabase's side before the browser ever reaches this app's code. This is a dashboard change only the Founder (or whoever holds production Supabase credentials) can make; it is not something this session can do or verify, consistent with the credential boundary established in `docs/database/DB-001A-apply-verify-runbook.md` and `docs/auth/ENG-002-testing-runbook.md`.

After that dashboard change, also confirm `NEXT_PUBLIC_APP_URL` is set correctly (or left unset — it no longer matters for production, since `getAppUrl()` no longer depends on it) and, ideally, set it explicitly anyway for clarity/consistency with other tooling that may read it.

## Known limitation

`getAppUrl()` keys off `NODE_ENV === "production"`, which `next build` sets for **every** production-mode build — including a Vercel Preview deployment, not only the one production deployment. A preview deployment would currently also resolve to the hardcoded production URL rather than its own preview URL. This repository has no preview/production Vercel distinction configured yet (per ENG-000, no production domain is connected), so this wasn't in scope to solve here; a future ticket that adds real preview deployments should switch this to Vercel's `VERCEL_ENV`/`NEXT_PUBLIC_VERCEL_URL` instead of `NODE_ENV` alone.
