import type { Metadata } from "next";
import Link from "next/link";
import { signOutStaff } from "@/app/management/actions";
import { getRiderSession } from "@/lib/rider";
import "./rider.css";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: { default: "My Deliveries — Adee's Food", template: "%s — Adee's Food Rider" },
  description: "Rider delivery workspace for authorized Adee's Food riders.",
  robots: { index: false, follow: false },
};

const STATUS_LABEL: Record<string, string> = {
  AVAILABLE: "Available",
  ON_DELIVERY: "On delivery",
  OFFLINE: "Offline",
  UNAVAILABLE: "Unavailable",
};

export default async function RiderLayout({ children }: { children: React.ReactNode }) {
  const { displayName, riderProfile } = await getRiderSession();
  const status = riderProfile?.status ?? "OFFLINE";

  return (
    <div className="rider-app">
      <header className="rider-topbar">
        <div>
          <strong>{displayName}</strong>
          <span>Adee&apos;s Food · Rider</span>
        </div>
        <div className="rider-topbar-actions">
          <span className={`rider-status-pill is-${status.toLowerCase().replace(/_/g, "-")}`}>
            <i aria-hidden="true" />
            {STATUS_LABEL[status] ?? status}
          </span>
          <form action={signOutStaff}>
            <button type="submit">Sign out</button>
          </form>
        </div>
      </header>

      <main className="rider-main">{children}</main>

      <nav className="rider-bottom-nav" aria-label="Rider navigation">
        <Link href="/rider">My Deliveries</Link>
        <Link href="/rider/history">History</Link>
        <Link href="/rider/cash">Cash</Link>
        <Link href="/rider/profile">Profile</Link>
      </nav>
    </div>
  );
}
