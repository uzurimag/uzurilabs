# ENG-002 — Testing Runbook (run on your own machine)

Like `docs/database/DB-001A-apply-verify-runbook.md`, this is a command/click runbook, not something executed by the assistant in this session — this environment has no link to any Supabase project and no credentials, and none should be placed in this repository or in chat. Everything here is run by you, locally, against the real UZURI Development Supabase project.

Contains no secrets. `.env.local` (holding your real project URL/key) stays on your machine and stays git-ignored.

## Prerequisites

- `.env.local` populated from `.env.example` with your real development project's `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
- `npm run dev` running locally.

## 1. Supabase dashboard configuration

In the **development** project only (see `docs/auth/ENG-002-authentication-and-sessions.md` for why only one redirect URL is needed):

- **Authentication → URL Configuration → Site URL:** `http://localhost:3000`
- **Authentication → URL Configuration → Redirect URLs:** add `http://localhost:3000/auth/callback`

## 2. Create a synthetic development test user

**Supabase Dashboard → Authentication → Users → Add user.** Use a synthetic email (e.g. `eng002-test@example.test`), a password only you know, and confirm the email immediately in the dialog (so you don't need a working email inbox for this first pass). Never use the Founder's real email here.

## 3. Verify the profile-creation trigger fired (DB-001)

In the SQL editor:

```sql
select id, full_name, platform_role, is_active, created_at
from public.profiles
where id = (select id from auth.users where email = 'eng002-test@example.test');
```

Expect exactly one row, with `platform_role` null and `is_active` true. This confirms DB-001's `handle_new_user` trigger created the profile — not something ENG-002 does itself. Record pass/fail; this is section 13 of the ticket.

## 4. A — Signed-out access

With no session (private/incognito window, or after clearing cookies):

- [ ] `http://localhost:3000/login` loads and shows the email/password form.
- [ ] `http://localhost:3000/dashboard` redirects to `/login?next=%2Fdashboard`.
- [ ] `http://localhost:3000/forgot-password` loads.
- [ ] `http://localhost:3000/signup` and `/register` both 404 (no public self-registration).

## 5. B — Valid login

- [ ] Sign in with the synthetic user's email/password at `/login`.
- [ ] You land on `/dashboard` and see your email and user id (no tokens).
- [ ] Open DevTools → Application → Cookies: a Supabase session cookie exists for `localhost`.
- [ ] Reload `/dashboard` — you're still signed in (session persists across reload).
- [ ] Navigate away and back (client-side nav) — still signed in (session persists across navigation).
- [ ] Re-run the query in step 3 — the profile row still matches this user.

## 6. C — Invalid login

- [ ] Sign in with the correct email and a wrong password: generic "Invalid email or password." — no indication of whether the email exists.
- [ ] Sign in with an email that doesn't exist at all: the **same** generic message, not a different one.

## 7. D — Sign-out

- [ ] Click "Sign out" on `/dashboard`. You land on `/login`.
- [ ] Visiting `/dashboard` directly afterward redirects to `/login` again (session actually cleared, not just UI hidden).

## 8. E — Password recovery

- [ ] Submit `/forgot-password` with the synthetic user's email: neutral confirmation message.
- [ ] Submit it again immediately with an email that doesn't exist: **same** neutral message.
- [ ] Open the emailed link (or, if email delivery isn't set up yet in dev, generate one via the dashboard's "Send recovery email" / by inspecting the magic link Supabase logs) — it should land on `/reset-password` with the form visible (not the "invalid/expired" state).
- [ ] Submit a new password (twice, matching) — redirected to `/dashboard`, signed in as that user.
- [ ] Visit `/reset-password` directly with no active recovery session (e.g. after signing out): shows the safe "invalid or expired" message, not the form, and not an error page/stack trace.

## 9. F — Direct-route protection

- [ ] With no session, request `/dashboard` directly (typed URL, not a client-side link) — confirms server-side redirect, not just a hidden nav item.

## 10. G — Open redirect protection

- [ ] Visit `/login?next=https://evil.example.com` and sign in: you should land on `/dashboard`, **not** the external URL.
- [ ] Visit `/login?next=//evil.example.com` (protocol-relative) and sign in: same — lands on `/dashboard`.

## 11. Record results

For each checkbox above, note pass/fail. That record — not a claim from the assistant's session — is what should replace "Not tested" in the ENG-002 completion report for sections 11–13 and the section-17 test matrix.
