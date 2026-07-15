"use server";

import { createClient } from "@/services/supabase/server";
import { isValidEmail, normalizeEmail } from "@/lib/auth-validation";

export type ForgotPasswordState = {
  message: string;
  tone: "neutral" | "error";
} | null;

const INVALID_EMAIL_MESSAGE = "Enter a valid email address.";
const RATE_LIMITED_MESSAGE =
  "Too many requests. Please wait a moment and try again.";
// Deliberately identical whether or not the account exists, and whether or
// not the send actually succeeded for reasons other than rate-limiting --
// this is the account-enumeration defense, not just documentation of one.
const NEUTRAL_MESSAGE =
  "If an account exists for that email, a password reset link has been sent.";

export async function requestPasswordReset(
  _prevState: ForgotPasswordState,
  formData: FormData,
): Promise<ForgotPasswordState> {
  const emailRaw = formData.get("email");

  if (typeof emailRaw !== "string") {
    return { message: INVALID_EMAIL_MESSAGE, tone: "error" };
  }

  const email = normalizeEmail(emailRaw);

  if (!isValidEmail(email)) {
    return { message: INVALID_EMAIL_MESSAGE, tone: "error" };
  }

  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";
  const supabase = await createClient();
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${appUrl}/auth/callback?next=/reset-password`,
  });

  if (error?.status === 429) {
    return { message: RATE_LIMITED_MESSAGE, tone: "error" };
  }

  // Any other error (including none) still surfaces the same neutral
  // message -- see NEUTRAL_MESSAGE comment.
  return { message: NEUTRAL_MESSAGE, tone: "neutral" };
}
