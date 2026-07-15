import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/services/supabase/server";
import { getSafeRedirectPath } from "@/lib/safe-redirect";

// Used only when `next` is missing/invalid -- in practice this means a
// non-recovery (e.g. email-confirmation) exchange, since
// resetPasswordForEmail always sends next=/reset-password explicitly.
// Deliberately never "/": an unauthenticated visitor landing on the
// homepage after what looked like a successful auth action is exactly the
// confusing, silent-failure symptom ENG-002A fixed.
const DEFAULT_CALLBACK_REDIRECT = "/dashboard";

// Handles the PKCE code exchange for both email-confirmation and
// password-recovery links (resetPasswordForEmail's redirectTo points here
// with next=/reset-password). Never logs the code or any token.
export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl;
  const code = searchParams.get("code");
  const next = getSafeRedirectPath(
    searchParams.get("next"),
    DEFAULT_CALLBACK_REDIRECT,
  );

  if (!code) {
    return NextResponse.redirect(new URL("/auth/error", request.url));
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    return NextResponse.redirect(new URL("/auth/error", request.url));
  }

  return NextResponse.redirect(new URL(next, request.url));
}
