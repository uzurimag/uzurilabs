import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/services/supabase/server";
import { getSafeRedirectPath } from "@/lib/safe-redirect";

// Handles the PKCE code exchange for both email-confirmation and
// password-recovery links (resetPasswordForEmail's redirectTo points here
// with next=/reset-password). Never logs the code or any token.
export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl;
  const code = searchParams.get("code");
  const next = getSafeRedirectPath(searchParams.get("next"), "/dashboard");

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
