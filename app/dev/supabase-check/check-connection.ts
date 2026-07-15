import { createClient } from "@/services/supabase/server";

export type ErrorCategory = "configuration" | "network" | "timeout" | "unknown";

export type ConnectionCheckResult =
  { status: "success" } | { status: "failed"; category: ErrorCategory };

const HEALTH_CHECK_TIMEOUT_MS = 5000;

/**
 * Proves the configured Supabase project is actually reachable.
 *
 * supabase.auth.getUser() only makes a network call when a session exists —
 * with no session (no auth implemented yet) it fails locally without ever
 * reaching Supabase. In that case we fall back to an unauthenticated request
 * against the Auth server's public health endpoint so the check still
 * exercises a real round trip.
 */
export async function checkSupabaseConnection(): Promise<ConnectionCheckResult> {
  const supabase = await createClient();
  const { error } = await supabase.auth.getUser();

  if (!error || error.name !== "AuthSessionMissingError") {
    // Either a user was found, or Supabase returned an auth-related error —
    // both mean the request reached the service and it responded.
    return { status: "success" };
  }

  return probeSupabaseHealth();
}

async function probeSupabaseHealth(): Promise<ConnectionCheckResult> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) {
    return { status: "failed", category: "configuration" };
  }

  let healthUrl: string;
  try {
    healthUrl = new URL("/auth/v1/health", url).toString();
  } catch {
    return { status: "failed", category: "configuration" };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), HEALTH_CHECK_TIMEOUT_MS);

  try {
    const response = await fetch(healthUrl, { signal: controller.signal });
    return response.ok
      ? { status: "success" }
      : { status: "failed", category: "unknown" };
  } catch (err) {
    const isTimeout = err instanceof Error && err.name === "AbortError";
    return {
      status: "failed",
      category: isTimeout ? "timeout" : "network",
    };
  } finally {
    clearTimeout(timeout);
  }
}
