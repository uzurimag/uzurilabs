import { notFound } from "next/navigation";
import { createClient } from "@/services/supabase/server";
import { BrowserCheck } from "./browser-check";
import { checkSupabaseConnection } from "./check-connection";

export const metadata = {
  title: "Supabase connection check",
};

const ERROR_CATEGORY_LABELS = {
  configuration: "configuration",
  network: "network",
  timeout: "timeout",
  unknown: "unknown",
};

export default async function SupabaseCheckPage() {
  if (process.env.NODE_ENV === "production") {
    notFound();
  }

  const urlConfigured = Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const publishableKeyConfigured = Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );

  let serverClientOk = false;
  try {
    await createClient();
    serverClientOk = true;
  } catch {
    serverClientOk = false;
  }

  const connection = serverClientOk
    ? await checkSupabaseConnection().catch(
        () => ({ status: "failed", category: "unknown" }) as const,
      )
    : ({ status: "failed", category: "configuration" } as const);

  return (
    <main className="mx-auto max-w-xl p-8 font-sans">
      <h1 className="text-xl font-semibold">Supabase connection check</h1>
      <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
        Development-only diagnostic. Not linked from the app and returns 404 in
        production. Remove once the Supabase integration is complete.
      </p>
      <ul className="mt-6 space-y-2 text-sm">
        <li>
          {urlConfigured ? "✅" : "❌"} NEXT_PUBLIC_SUPABASE_URL configured
        </li>
        <li>
          {publishableKeyConfigured ? "✅" : "❌"}{" "}
          NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY configured
        </li>
        <li>{serverClientOk ? "✅" : "❌"} Server client initializes</li>
        <BrowserCheck />
        <li>
          {connection.status === "success" ? "✅" : "❌"} Connection{" "}
          {connection.status === "success" ? "successful" : "failed"}
          {connection.status === "failed" &&
            ` (reason: ${ERROR_CATEGORY_LABELS[connection.category]})`}
        </li>
      </ul>
    </main>
  );
}
