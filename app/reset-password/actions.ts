"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/services/supabase/server";
import { MIN_PASSWORD_LENGTH } from "@/lib/auth-validation";

export type ResetPasswordState = {
  error: string;
} | null;

const MISMATCH_MESSAGE = "Passwords do not match.";
const TOO_SHORT_MESSAGE = `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`;
// Never surfaces the provider's own error text (which can include details
// like which validator rejected the password); expired/invalid recovery
// sessions and any other failure all collapse to the same safe message.
const GENERIC_FAILURE_MESSAGE =
  "Could not update your password. Your reset link may have expired -- request a new one.";

export async function updatePassword(
  _prevState: ResetPasswordState,
  formData: FormData,
): Promise<ResetPasswordState> {
  const passwordRaw = formData.get("password");
  const confirmRaw = formData.get("confirmPassword");

  if (typeof passwordRaw !== "string" || typeof confirmRaw !== "string") {
    return { error: GENERIC_FAILURE_MESSAGE };
  }

  if (passwordRaw.length < MIN_PASSWORD_LENGTH) {
    return { error: TOO_SHORT_MESSAGE };
  }

  if (passwordRaw !== confirmRaw) {
    return { error: MISMATCH_MESSAGE };
  }

  const supabase = await createClient();

  // Requires an active (recovery) session -- the page only renders this
  // form when one exists, but updateUser() itself is the actual
  // enforcement: without a valid session it fails rather than trusting the
  // page's own check.
  const { error } = await supabase.auth.updateUser({ password: passwordRaw });

  if (error) {
    return { error: GENERIC_FAILURE_MESSAGE };
  }

  redirect("/dashboard");
}
