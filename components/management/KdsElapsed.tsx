"use client";

import { useEffect, useState } from "react";

export function KdsElapsed({ queuedAt, targetSeconds }: { queuedAt: string; targetSeconds: number }) {
  const [elapsed, setElapsed] = useState<number | null>(null);

  useEffect(() => {
    const update = () => setElapsed(Math.max(0, Math.floor((Date.now() - new Date(queuedAt).getTime()) / 60_000)));
    update();
    const timer = window.setInterval(update, 30_000);
    return () => window.clearInterval(timer);
  }, [queuedAt]);

  const seconds = (elapsed ?? 0) * 60;
  const label = seconds > targetSeconds ? "Late" : seconds > targetSeconds * 0.7 ? "Attention" : "On time";
  return <strong className={`kds-elapsed is-${label.toLowerCase()}`}>{elapsed ?? "—"} min<small>{label}</small></strong>;
}
