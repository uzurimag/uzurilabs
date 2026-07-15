"use client";

import { useActionState } from "react";
import Link from "next/link";
import { requestPasswordReset, type ForgotPasswordState } from "./actions";

export function ForgotPasswordForm() {
  const [state, action, pending] = useActionState<
    ForgotPasswordState,
    FormData
  >(requestPasswordReset, null);

  return (
    <form action={action} className="mt-8 flex flex-col gap-4" noValidate>
      <div className="flex flex-col gap-1.5">
        <label htmlFor="email" className="text-sm font-medium">
          Email
        </label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
          className="rounded-md border border-black/[.08] bg-white px-3 py-2 text-sm outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-black dark:focus:border-white/40"
        />
      </div>

      <div aria-live="polite">
        {state && (
          <p
            className={
              state.tone === "error"
                ? "text-sm text-red-600 dark:text-red-400"
                : "text-sm text-zinc-600 dark:text-zinc-400"
            }
          >
            {state.message}
          </p>
        )}
      </div>

      <button
        type="submit"
        disabled={pending}
        className="bg-foreground text-background mt-2 rounded-full px-5 py-2 text-sm font-medium transition-colors hover:bg-[#383838] disabled:opacity-50 dark:hover:bg-[#ccc]"
      >
        {pending ? "Sending…" : "Send reset link"}
      </button>

      <Link
        href="/login"
        className="text-sm text-zinc-600 underline underline-offset-2 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-50"
      >
        Back to sign in
      </Link>
    </form>
  );
}
