"use client";

export default function ManagementError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <section className="ops-panel"><div className="ops-empty is-wide"><strong>This module could not be loaded</strong><p>The operation was stopped safely. Try again; if it continues, review the Supabase service status.</p><button className="ops-primary-button" type="button" onClick={reset}>Try again</button></div></section>;
}
