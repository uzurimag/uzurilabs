// The deployed production origin, used to build absolute redirect URLs
// (e.g. Supabase's resetPasswordForEmail `redirectTo`) that must resolve
// correctly regardless of whether NEXT_PUBLIC_APP_URL happens to be
// configured in the deployment environment.
//
// This exists because of a real incident (ENG-002A): NEXT_PUBLIC_APP_URL
// was never set in Vercel's production environment, so the password-reset
// email's redirectTo fell back to "http://localhost:3000" -- a URL that is
// both unreachable for a real user and not present in the Supabase
// project's Redirect URLs allow-list, so Supabase silently fell back to
// the project's Site URL (the production homepage) instead. Hardcoding the
// known-correct production origin here removes that failure mode entirely:
// production no longer depends on an env var being configured correctly to
// send a working link.
const PRODUCTION_APP_URL = "https://uzurilabs-platform-zeta.vercel.app";
const DEFAULT_DEV_APP_URL = "http://localhost:3000";

/**
 * Production always uses the known-correct deployed origin. Non-production
 * (local dev) derives the origin from NEXT_PUBLIC_APP_URL, falling back to
 * localhost if it isn't set.
 */
export function getAppUrl(): string {
  if (process.env.NODE_ENV === "production") {
    return PRODUCTION_APP_URL;
  }

  return process.env.NEXT_PUBLIC_APP_URL ?? DEFAULT_DEV_APP_URL;
}
