"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/services/supabase/server";

export async function signOut(): Promise<void> {
  const supabase = await createClient();
  // signOut() itself clears the Supabase session cookies via the server
  // client's cookie adapter; errors here don't leave a valid session behind
  // (Supabase's own default signOut scope always clears the local session),
  // so it's safe to redirect regardless.
  await supabase.auth.signOut();
  redirect("/login");
}
