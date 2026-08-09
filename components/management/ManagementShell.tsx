"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { canAccessModule, managementModules } from "@/lib/access";
import { signOutStaff } from "@/app/management/actions";

type ManagementShellProps = {
  children: React.ReactNode;
  displayName: string;
  organizationName: string;
  locationName: string;
  roleName: string;
  permissions: string[];
};

export function ManagementShell({
  children,
  displayName,
  organizationName,
  locationName,
  roleName,
  permissions,
}: ManagementShellProps) {
  const pathname = usePathname();
  const [isOpen, setIsOpen] = useState(false);
  const initials = displayName
    .split(" ")
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");

  return (
    <main className="ops-app">
      <aside className={`ops-sidebar${isOpen ? " is-open" : ""}`}>
        <div className="ops-brand-row">
          <Link className="ops-brand" href="/management" onClick={() => setIsOpen(false)}>
            <Image src="/brand/adees-logo.webp" alt="" width={640} height={640} priority />
            <span>Adee&apos;s Food<small>Management system</small></span>
          </Link>
          <button className="ops-nav-close" type="button" onClick={() => setIsOpen(false)} aria-label="Close navigation">×</button>
        </div>

        <nav className="ops-nav" aria-label="Restaurant management">
          {managementModules.filter((module) => canAccessModule(permissions, module)).map((module) => {
            const href = module.slug ? `/management/${module.slug}` : "/management";
            const active = module.slug ? pathname.startsWith(href) : pathname === "/management";
            return (
              <Link
                className={active ? "is-active" : ""}
                href={href}
                key={module.name}
                onClick={() => setIsOpen(false)}
              >
                <span>{module.marker}</span>
                {module.shortName}
                {active ? <i aria-hidden="true" /> : null}
              </Link>
            );
          })}
        </nav>

        <div className="ops-sidebar-foot">
          <div className="ops-live"><i aria-hidden="true" /><span>Systems online<small>Supabase · Live</small></span></div>
          <Link href="/" className="ops-site-link">Public website <span>↗</span></Link>
        </div>
      </aside>

      {isOpen ? <button className="ops-nav-scrim" aria-label="Close navigation" onClick={() => setIsOpen(false)} /> : null}

      <section className="ops-workspace">
        <header className="ops-topbar">
          <button className="ops-menu-button" type="button" onClick={() => setIsOpen(true)} aria-label="Open navigation">☰</button>
          <div className="ops-location"><strong>{organizationName}</strong><span>{locationName}</span></div>
          <div className="ops-user">
            <span className="ops-avatar" aria-hidden="true">{initials}</span>
            <div><strong>{displayName}</strong><span>{roleName}</span></div>
            <form action={signOutStaff}><button type="submit">Sign out</button></form>
          </div>
        </header>
        <div className="ops-content" id="management-content">{children}</div>
      </section>
    </main>
  );
}
