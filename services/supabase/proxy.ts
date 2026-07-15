import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

// Routes that require a signed-in user. Matches the path itself and any
// nested path beneath it.
const PROTECTED_PATHS = ["/dashboard"];

// Routes an already signed-in user shouldn't see -- they're redirected to
// the protected app instead. Deliberately excludes /reset-password: a
// recovery link signs the user in, and this ticket requires that flow to
// complete rather than be redirected away.
const GUEST_ONLY_PATHS = ["/login", "/forgot-password"];

function matchesPath(pathname: string, base: string): boolean {
  return pathname === base || pathname.startsWith(`${base}/`);
}

function redirectPreservingCookies(url: URL, base: NextResponse): NextResponse {
  const redirect = NextResponse.redirect(url);
  for (const cookie of base.cookies.getAll()) {
    redirect.cookies.set(cookie);
  }
  return redirect;
}

/**
 * Refreshes the Supabase session on every matched request and enforces the
 * two route-level redirects this ticket requires. This is the only place
 * those decisions are made -- Server Components and Server Actions still
 * independently verify identity themselves (see services/supabase/server.ts
 * callers), since proxy is a routing optimization, not the sole
 * authorization boundary (RBAC/authorization is explicitly out of scope for
 * this ticket).
 */
export async function updateSession(
  request: NextRequest,
): Promise<NextResponse> {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          for (const { name, value } of cookiesToSet) {
            request.cookies.set(name, value);
          }
          response = NextResponse.next({ request });
          for (const { name, value, options } of cookiesToSet) {
            response.cookies.set(name, value, options);
          }
        },
      },
    },
  );

  // getClaims() verifies the JWT itself (locally for asymmetric signing
  // keys, or against the Auth server otherwise) and transparently refreshes
  // an about-to-expire session first. getSession()/getUser() on their own
  // are not sufficient here: getSession() trusts the cookie's contents
  // without verification, which is exactly what this ticket says never to
  // rely on for an authorization decision.
  const { data } = await supabase.auth.getClaims();
  const isAuthenticated = data?.claims != null;

  const { pathname } = request.nextUrl;

  const isProtected = PROTECTED_PATHS.some((path) =>
    matchesPath(pathname, path),
  );
  if (isProtected && !isAuthenticated) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return redirectPreservingCookies(url, response);
  }

  const isGuestOnly = GUEST_ONLY_PATHS.some((path) =>
    matchesPath(pathname, path),
  );
  if (isGuestOnly && isAuthenticated) {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    url.search = "";
    return redirectPreservingCookies(url, response);
  }

  return response;
}
