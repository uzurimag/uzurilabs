"use client";

import { useSyncExternalStore } from "react";
import { createClient } from "@/services/supabase/client";

type Status = "checking" | "ok" | "error";

function subscribe() {
  return () => {};
}

function getSnapshot(): Status {
  try {
    createClient();
    return "ok";
  } catch {
    return "error";
  }
}

function getServerSnapshot(): Status {
  return "checking";
}

export function BrowserCheck() {
  const status = useSyncExternalStore(
    subscribe,
    getSnapshot,
    getServerSnapshot,
  );

  const symbol = status === "checking" ? "…" : status === "ok" ? "✅" : "❌";
  return <li>{symbol} Browser client initializes</li>;
}
