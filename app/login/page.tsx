import { LoginForm } from "./login-form";
import { getSafeRedirectPath } from "@/lib/safe-redirect";

export const dynamic = "force-dynamic";

export const metadata = {
  title: "Sign in — UZURI Intelligence Platform",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next: nextParam } = await searchParams;
  const next = getSafeRedirectPath(nextParam, "/dashboard");

  return (
    <main className="mx-auto max-w-sm p-8 font-sans">
      <h1 className="text-xl font-semibold">Sign in</h1>
      <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
        UZURI Intelligence Platform is invitation-only. Sign in with the
        credentials you were given.
      </p>
      <LoginForm next={next} />
    </main>
  );
}
