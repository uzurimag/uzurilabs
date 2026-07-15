import Link from "next/link";

export const dynamic = "force-dynamic";

export const metadata = {
  title: "Authentication error — UZURI Intelligence Platform",
};

// Never displays tokens, raw callback parameters, stack traces, or
// internal Supabase error objects -- just this one safe message, regardless
// of what actually went wrong server-side.
export default function AuthErrorPage() {
  return (
    <main className="mx-auto max-w-sm p-8 font-sans">
      <h1 className="text-xl font-semibold">Authentication error</h1>
      <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
        We couldn&apos;t complete that authentication request. The link may have
        expired or already been used.
      </p>
      <div className="mt-6 flex flex-col gap-2">
        <Link
          href="/login"
          className="text-sm text-zinc-600 underline underline-offset-2 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-50"
        >
          Back to sign in
        </Link>
        <Link
          href="/forgot-password"
          className="text-sm text-zinc-600 underline underline-offset-2 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-50"
        >
          Request a new password reset link
        </Link>
      </div>
    </main>
  );
}
