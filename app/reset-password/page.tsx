import Link from "next/link";
import { createClient } from "@/services/supabase/server";
import { ResetPasswordForm } from "./reset-password-form";

export const dynamic = "force-dynamic";

export const metadata = {
  title: "Reset password — UZURI Intelligence Platform",
};

export default async function ResetPasswordPage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const hasRecoverySession = data?.claims != null;

  return (
    <main className="mx-auto max-w-sm p-8 font-sans">
      <h1 className="text-xl font-semibold">Reset password</h1>
      {hasRecoverySession ? (
        <>
          <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
            Choose a new password for your account.
          </p>
          <ResetPasswordForm />
        </>
      ) : (
        <>
          <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
            This password reset link is invalid or has expired.
          </p>
          <Link
            href="/forgot-password"
            className="mt-6 inline-block text-sm text-zinc-600 underline underline-offset-2 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-50"
          >
            Request a new reset link
          </Link>
        </>
      )}
    </main>
  );
}
