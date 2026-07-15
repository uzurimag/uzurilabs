"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/services/supabase/server";
import { getSafeRedirectPath } from "@/lib/safe-redirect";
import { isValidEmail, normalizeEmail } from "@/lib/auth-validation";

export type SignInState = {
  error?: string;
} | null;

// Never returns Supabase's own error text: signInWithPassword's error
// message doesn't distinguish "wrong password" from "no such account"
// itself, but future providers/changes might -- collapsing every failure to
// one generic message here is the actual enforcement point, not an
// assumption about what the provider happens to return today.
const INVALID_CREDENTIALS_MESSAGE = "Invalid email or password.";

export async function signIn(
  _prevState: SignInState,
  formData: FormData,
): Promise<SignInState> {
  const emailRaw = formData.get("email");
  const passwordRaw = formData.get("password");
  const nextRaw = formData.get("next");

  if (typeof emailRaw !== "string" || typeof passwordRaw !== "string") {
    return { error: INVALID_CREDENTIALS_MESSAGE };
  }

  const email = normalizeEmail(emailRaw);
  const password = passwordRaw;

  if (!isValidEmail(email) || password.length === 0) {
    return { error: INVALID_CREDENTIALS_MESSAGE };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    return { error: INVALID_CREDENTIALS_MESSAGE };
  }

  const next = getSafeRedirectPath(
    typeof nextRaw === "string" ? nextRaw : null,
    "/dashboard",
  );
  redirect(next);
}
