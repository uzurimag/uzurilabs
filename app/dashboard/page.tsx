import { redirect } from "next/navigation";
import { createClient } from "@/services/supabase/server";
import { signOut } from "./actions";

export const dynamic = "force-dynamic";

export const metadata = {
  title: "Dashboard — UZURI Intelligence Platform",
};

// Minimal authenticated placeholder for ENG-002 -- the real dashboard is a
// later ticket. proxy.ts already redirects unauthenticated requests before
// they reach this page; the check below is a second, independent
// server-side enforcement point (not just hidden navigation), consistent
// with this ticket's backend-enforcement requirement.
export default async function DashboardPage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  if (!claims) {
    redirect("/login");
  }

  return (
    <main className="mx-auto max-w-sm p-8 font-sans">
      <h1 className="text-xl font-semibold">Dashboard</h1>
      <dl className="mt-6 space-y-3 text-sm">
        <div>
          <dt className="text-zinc-600 dark:text-zinc-400">Status</dt>
          <dd>Signed in</dd>
        </div>
        <div>
          <dt className="text-zinc-600 dark:text-zinc-400">Email</dt>
          <dd>{claims.email}</dd>
        </div>
        <div>
          <dt className="text-zinc-600 dark:text-zinc-400">User ID</dt>
          <dd className="break-all">{claims.sub}</dd>
        </div>
      </dl>
      <form action={signOut} className="mt-8">
        <button
          type="submit"
          className="bg-foreground text-background rounded-full px-5 py-2 text-sm font-medium transition-colors hover:bg-[#383838] dark:hover:bg-[#ccc]"
        >
          Sign out
        </button>
      </form>
    </main>
  );
}
