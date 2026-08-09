"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { createClient } from "@/lib/supabase/client";

export function LiveRefresh({ tables }: { tables: string[] }) {
  const router = useRouter();

  useEffect(() => {
    const supabase = createClient();
    const channel = supabase.channel(`ops-live-${tables.join("-")}`);
    for (const table of tables) {
      channel.on("postgres_changes", { event: "*", schema: "public", table }, () => router.refresh());
    }
    channel.subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [router, tables]);

  return null;
}
