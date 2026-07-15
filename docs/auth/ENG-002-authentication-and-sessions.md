# ENG-002 — Authentication and Session Management

Testing/execution runbook against the real UZURI Development Supabase project: `docs/auth/ENG-002-testing-runbook.md`
Production password-recovery redirect incident and fix: `docs/auth/ENG-002A-password-recovery-redirect-fix.md`

## ARCH-000 status

`docs/architecture/ARCH-000-engineering-principles.md` **does not exist** in this repository. This is reported as instructed, not fabricated — no approval status is claimed for a document that isn't there. This ticket instead followed the specific principles listed inline in the ticket itself (security by default, least privilege, backend enforcement, evidence over claims, no secrets in source code, test critical workflows, smallest usable release).

## Scope

Real Supabase email/password authentication and session handling only. Explicitly not implemented: RBAC, founder bootstrap, invitations, organization creation/membership assignment, client onboarding, MFA, OAuth, custom SMTP/Resend, audit events, the full dashboard, an admin interface, or billing.

## Route structure and why `/dashboard`

The ticket allowed either `/app` or `/dashboard` for the protected placeholder. `/dashboard` was chosen: the App Router's own project directory is already named `app/`, and a route segment also named `/app` (i.e. `app/app/page.tsx` → `/app`) would be a confusing, purely coincidental collision with that directory name for no benefit. `/dashboard` is unambiguous and is what section 6 of the ticket itself refers to as "the protected application route."

## Implemented routes

| Route              | Type                 | Purpose                                                                        |
| ------------------ | -------------------- | ------------------------------------------------------------------------------ |
| `/login`           | Page + Server Action | Email/password sign-in form                                                    |
| `/forgot-password` | Page + Server Action | Request a password-reset email                                                 |
| `/reset-password`  | Page + Server Action | Complete a password reset (requires an active recovery session)                |
| `/auth/callback`   | Route Handler (GET)  | PKCE code exchange for both email-confirmation and password-recovery links     |
| `/auth/error`      | Page                 | Safe, generic failure state for any auth flow                                  |
| `/dashboard`       | Page + Server Action | Minimal authenticated placeholder (signed-in status, email, user id, sign-out) |

No `/signup` or `/register` route exists — confirmed by requesting both and receiving `404` (see the testing runbook).

## Authentication flow

1. `/login` renders `LoginForm` (Client Component), which calls the `signIn` Server Action via `useActionState` (form `action`), so it works with JS disabled too and gets a real `pending` state for free — used to disable the submit button during submission.
2. `signIn` (`app/login/actions.ts`) normalizes the email (trim + lowercase), rejects empty/malformed input before ever calling Supabase, then calls `supabase.auth.signInWithPassword({ email, password })` using the existing `services/supabase/server.ts` cookie-aware client.
3. Any failure — wrong password, unknown account, or anything else — is collapsed to one message: `"Invalid email or password."` The raw Supabase error is never shown, and no code path distinguishes "account doesn't exist" from "wrong password," so no account-existence signal is exposed regardless of what the provider returns today or in the future.
4. On success, `signIn` redirects to the `next` path from a hidden form field, validated through `lib/safe-redirect.ts` both when it's read from the incoming query string (page level) and again inside the Server Action before use (defense in depth — never trust a value handed back through a form).

## SSR cookie strategy

`services/supabase/client.ts` (Browser/Client Components, unchanged from ENG-001) and `services/supabase/server.ts` (Server Components/Server Actions/Route Handlers, unchanged except a stale comment) are reused as-is, per the ticket's "reuse existing utilities" instruction. Both are thin wrappers around `@supabase/ssr`'s `createBrowserClient`/`createServerClient` — no custom/parallel session system exists, no token is ever stored in `localStorage`, and no token appears in a URL.

`services/supabase/server.ts`'s `setAll` swallows the "cookies are read-only" error that `next/headers`' `cookies().set()` throws when called from a plain Server Component (as opposed to a Server Action or Route Handler). That's safe specifically _because_ `proxy.ts` refreshes the session on every matched request before a Server Component ever runs — Server Components only ever need to _read_ an already-current session, never write one.

## Proxy behavior (`proxy.ts` / `services/supabase/proxy.ts`)

Next.js 16 renamed `middleware.ts` to `proxy.ts` (same `NextRequest`/`NextResponse` APIs, same `config.matcher`, purely a rename per the framework's own migration notes — confirmed against `node_modules/next/dist/docs` before writing this, since this Next.js version's conventions can't be assumed from training data).

`proxy.ts` at the repo root is a thin wrapper that calls `updateSession()` from `services/supabase/proxy.ts`, which:

1. Builds a mutable `NextResponse` and a cookie-aware Supabase client whose `setAll` writes to _both_ the request (so this same request's downstream Server Components see refreshed cookies) and the response (so the browser receives the refreshed `Set-Cookie` headers) — the standard `@supabase/ssr` proxy/middleware pattern.
2. Calls `supabase.auth.getClaims()` — **not** `getSession()` — to establish identity. `getClaims()` verifies the JWT (locally via WebCrypto for asymmetric signing keys, or against the Auth server otherwise) and transparently refreshes an about-to-expire session first; `getSession()` merely trusts whatever the cookie already says without verifying it, which is exactly what this ticket says never to use for an authorization decision.
3. Redirects unauthenticated requests to `/dashboard` (or any nested path under it) to `/login?next=<original-path>`.
4. Redirects authenticated requests to `/login` or `/forgot-password` to `/dashboard`. `/reset-password` is deliberately excluded from this list — a recovery link signs the user in, and redirecting them away would break the very flow they're completing (ticket section 6).
5. Every redirect is built by copying the refreshed response's cookies onto the redirect response (`redirectPreservingCookies`) — constructing a bare `NextResponse.redirect(url)` directly would silently drop any session cookie refreshed earlier in the same request.
6. `config.matcher` excludes `_next/static`, `_next/image`, `favicon.ico`, and common static asset extensions, so Proxy doesn't run on every CSS/JS/image request.

Proxy does **not** implement role/organization authorization (out of scope for this ticket) and is not treated as the sole authorization boundary — see "Protected-route strategy" below.

## Protected-route strategy

Two independent, server-side layers, not one:

1. **Proxy** redirects unauthenticated requests before `/dashboard` ever renders (covers the common case, and covers it before any page code runs).
2. **The page itself** (`app/dashboard/page.tsx`) independently calls `getClaims()` again and `redirect("/login")` if there's no valid session. This is intentionally redundant with Proxy — hiding a "Dashboard" nav link is not protection, and this ticket explicitly requires the enforcement to be server-side and not solely dependent on Proxy always having run for a given request.

Both layers were exercised locally (see "Testing procedure").

## Password-reset flow

1. `/forgot-password` collects an email and calls `requestPasswordReset` (`app/forgot-password/actions.ts`), which validates the email format itself, then calls `supabase.auth.resetPasswordForEmail(email, { redirectTo: '<app-url>/auth/callback?next=/reset-password' })`, where `<app-url>` comes from `lib/app-url.ts`'s `getAppUrl()` — the exact deployed production origin when `NODE_ENV === "production"`, unconditionally (not dependent on an env var being configured correctly in the deployment; see `docs/auth/ENG-002A-password-recovery-redirect-fix.md` for why that distinction matters), or `NEXT_PUBLIC_APP_URL` (falling back to `http://localhost:3000`) otherwise.
2. Regardless of whether the account exists, or whether the send happened to fail for a reason other than rate-limiting, the same neutral message is shown: _"If an account exists for that email, a password reset link has been sent."_ A `429` (rate-limited) response is the one exception — it gets its own message, since disclosing "you're sending too many requests" doesn't reveal account existence.
3. Supabase's own `/recover` endpoint is itself designed not to reveal account existence (it responds success-shaped regardless), so this app-level neutrality is defense in depth, not the only thing preventing enumeration.
4. Clicking the emailed link lands on `/auth/callback?code=...&next=/reset-password`, which exchanges the code for a (recovery) session and redirects to `/reset-password`.
5. `/reset-password` (`app/reset-password/page.tsx`) calls `getClaims()`; if there's no valid session (expired/already-used link), it shows a safe "invalid or expired" message with a link back to `/forgot-password` instead of the form.
6. Submitting the form calls `updatePassword` (`app/reset-password/actions.ts`), which checks the two passwords match and meet the minimum length **before** calling `supabase.auth.updateUser({ password })`. Any failure (mismatch aside) collapses to one generic message — it does not surface the provider's own error text.

**Password policy note (do not skip):** `MIN_PASSWORD_LENGTH = 8` (`lib/auth-validation.ts`) is a baseline client/server check, not a production password policy. The actual, authoritative policy is whatever is configured in the Supabase project's Auth settings (minimum length, leaked-password protection, etc.), which can be stricter than this baseline and is enforced by Supabase itself regardless of what this app checks first.

## Callback flow

`app/auth/callback/route.ts` is a single Route Handler used by **both** email-confirmation and password-recovery links (both are PKCE code-exchange flows):

1. Reads `code` and `next` from the query string. `next` is validated through `getSafeRedirectPath` (defaults to `/dashboard`) before ever being used in a redirect — an external or protocol-relative `next` value is silently replaced with the default rather than followed.
2. No `code` → redirect to `/auth/error`.
3. `supabase.auth.exchangeCodeForSession(code)` — using the cookie-aware server client, so the resulting session is written to cookies as part of the same response.
4. Exchange failure → redirect to `/auth/error`. Success → redirect to the validated `next`.
5. The code and any token are never logged or included in a response body — only used as an opaque exchange input.

## Required Supabase dashboard settings

**Development project** (to be configured manually by the Founder):

- **Site URL:** `http://localhost:3000`
- **Redirect URLs** (Authentication → URL Configuration → Redirect URLs): `http://localhost:3000/auth/callback`

**Production project** (see `docs/auth/ENG-002A-password-recovery-redirect-fix.md` for the incident this addresses):

- **Redirect URLs** must include: `https://uzurilabs-platform-zeta.vercel.app/auth/callback`

In both cases only one redirect URL is required per environment: this implementation always routes both email-confirmation and password-recovery links through `/auth/callback` (with a `next` query param distinguishing the two), rather than pointing `resetPasswordForEmail`'s `redirectTo` directly at `/reset-password`. `/reset-password` itself is never used as a Supabase-configured redirect URL — it's only ever reached _through_ the callback. If the production project's Redirect URLs allow-list doesn't include the exact URL above, Supabase falls back to its Site URL (the production homepage) regardless of what the app sends — this was the actual root cause of the ENG-002A incident, and is a dashboard-only fix this session cannot make itself.

No secret keys are referenced or required for this dashboard configuration step.

## Development test user

Public self-registration is intentionally absent. To create a synthetic user for local testing: **Supabase Dashboard → Authentication → Users → Add user**, using a synthetic `@example.test`-style email — never the Founder's real email, and never committed to source control or any migration. See the testing runbook for the exact steps and the profile-creation check that follows.

## Testing procedure

See `docs/auth/ENG-002-testing-runbook.md` for the full step-by-step procedure against the real development Supabase project (dashboard configuration, creating a synthetic user, and walking through every flow in a browser), and the completion report for exactly which of the ticket's required checks were run in this session versus deferred to that runbook.

What _was_ verified in this session, without any real Supabase project (using placeholder env vars, since these checks only depend on routing/redirect logic, not a live backend):

- `/login` and `/forgot-password` return `200` when signed out.
- `/dashboard` returns `307` to `/login?next=%2Fdashboard` when signed out.
- `/signup` and `/register` both return `404` — no public self-registration route exists.
- `/reset-password` with no session renders the safe "invalid or expired" state, not the form.
- `/auth/error` returns `200`.
- `/auth/callback` with no `code` returns a `307` redirect to `/auth/error`.
- `/login` and `/forgot-password` render the expected accessible form fields (labeled `email`/`password` inputs, a "Forgot password?" link, a "Send reset link" button).

What was **not** verified in this session (requires a real Supabase project and/or a real browser session): successful sign-in, session cookie creation and persistence across reload, sign-out clearing the session, the full password-recovery round trip, and `public.profiles` row creation for a newly authenticated user. See the completion report's status labels.

## Known limitations

- No rate limiting is implemented at the application layer for `/login` or `/forgot-password` beyond what Supabase Auth itself enforces server-side.
- The password policy baseline (`MIN_PASSWORD_LENGTH = 8`) is not necessarily the production policy — see the callout above.
- `getClaims()`'s local (WebCrypto) verification path requires the Supabase project to use asymmetric JWT signing keys; projects still on the legacy symmetric (HS256) secret fall back to a network request per call (functionally correct, just not the fast path). This wasn't something this ticket could configure or verify without dashboard access.
- No automated test framework exists in this repository yet (still true as of ENG-000/DB-001's notes); verification here is either local route-level smoke testing (this session) or a manual runbook (real-Supabase steps). Playwright's browser binaries are pre-installed in this sandbox but the `playwright` npm package itself was deliberately not added as a project dependency for a one-off check — see the completion report.

## Deferred capabilities

RBAC/authorization, founder bootstrap, invitations, organization creation and membership assignment, client onboarding, MFA, OAuth/social login, magic links, phone login, custom SMTP/Resend, audit events, the real dashboard, an admin interface, and billing — all explicitly out of scope per the ticket and left for later tickets.

## Security considerations

- **Backend enforcement, twice over:** route protection is enforced in both Proxy and the protected page itself, not just by hiding navigation.
- **No account enumeration:** sign-in and password-reset failures are both collapsed to generic, identical-shaped messages regardless of cause.
- **Open-redirect prevention:** every `next`/`return` value (from a query string, a hidden form field, or the callback) is validated through the same `getSafeRedirectPath` helper before being used, both when first read and again at the point of use.
- **No secrets in source:** only `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` are read (both already public/browser-safe per ENG-001), and `NEXT_PUBLIC_APP_URL` for constructing the password-reset redirect URL. `SUPABASE_SERVICE_ROLE_KEY` is not used anywhere in this ticket.
- **No manual session storage:** no `localStorage`, no custom cookie/session table, no token in a URL (the PKCE `code` in `/auth/callback`'s query string is a single-use exchange code, not a session token, and is discarded immediately after exchange).
- **Caching:** every route that depends on auth state (`/login`, `/forgot-password`, `/reset-password`, `/auth/error`, `/dashboard`) sets `export const dynamic = "force-dynamic"` explicitly, in addition to being implicitly dynamic already from reading cookies — this is belt-and-suspenders against a future refactor accidentally making one of these pages static and cacheable across users.
- **Dev-only diagnostic unaffected:** `/dev/supabase-check` (from ENG-001/ENG-001B) still 404s in production, unchanged by this ticket, and its route falls outside Proxy's protected/guest-only lists so it isn't redirected.
