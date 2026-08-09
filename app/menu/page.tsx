import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { randomUUID } from "node:crypto";
import { PublicOrderMenu } from "@/components/PublicOrderMenu";
import { isPublicMenu } from "@/lib/public-menu";
import { createClient } from "@/lib/supabase/server";
import "./menu.css";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Order Online — Adee's Food",
  description: "Browse the live Adee's Food menu and place an order for pickup or delivery.",
};

export default async function MenuPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_public_menu");
  const menu = isPublicMenu(data) ? data : null;

  return (
    <div className="menu-page-shell">
      <header className="online-header">
        <Link href="/" className="online-brand" aria-label="Adee's Food home">
          <Image src="/brand/adees-logo.webp" alt="" width={640} height={640} priority />
          <span>Adee&apos;s Food</span>
        </Link>
        <nav aria-label="Menu page navigation">
          <Link href="/">Home</Link>
          <a href="#menu-title">Menu</a>
          <a href="#your-order">Your order</a>
        </nav>
        <Link href="/staff/login" className="online-staff-link">Staff login</Link>
      </header>

      {menu && !error ? (
        <PublicOrderMenu menu={menu} sourceReference={randomUUID()} />
      ) : (
        <main className="menu-unavailable">
          <p className="menu-kicker">Adee&apos;s Food</p>
          <h1>The menu is taking a moment.</h1>
          <p>Online ordering is temporarily unavailable. Please try again shortly.</p>
          <Link href="/">Return home</Link>
        </main>
      )}

      <footer className="online-footer">
        <p>© 2026 Adee&apos;s Food</p>
        <span>Secure ordering · GHS · Africa/Accra</span>
        <Link href="/staff/login">Staff management</Link>
      </footer>
    </div>
  );
}
