import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import { managementModules, parseAccessContext } from "@/lib/access";
import { createClient } from "@/lib/supabase/server";
import { signOutStaff } from "./actions";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Management System — Adee's Food",
  description: "Secure restaurant operations for authorized Adee's Food staff.",
  robots: { index: false, follow: false },
};

export default async function ManagementPage() {
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const claims = claimsData?.claims;

  if (!claims) redirect("/staff/login?error=session-required");

  const [{ data: accessData }, { data: profile }, { data: assurance }] = await Promise.all([
    supabase.rpc("get_my_access_context"),
    supabase.from("profiles").select("display_name").eq("id", String(claims.sub)).maybeSingle(),
    supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
  ]);

  const access = parseAccessContext(accessData);
  if (access.assignments.length === 0) redirect("/staff/login?error=no-access");

  const primaryAssignment = access.assignments[0];
  const email = typeof claims.email === "string" ? claims.email : "Authorized staff";
  const profileName = typeof profile?.display_name === "string" ? profile.display_name : null;
  const displayName: string = profileName ?? email.split("@")[0];
  const firstName = displayName.split(" ")[0];
  const initials = displayName
    .split(" ")
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
  const assuranceLevel = assurance?.currentLevel === "aal2" ? "MFA verified" : "Password verified";

  return (
    <main className="management-page">
      <aside className="management-sidebar">
        <Link className="management-brand" href="/" aria-label="Adee's Food website">
          <Image src="/brand/adees-logo.webp" alt="" width={640} height={640} priority />
          <span>
            Adee&apos;s Food
            <small>Management</small>
          </span>
        </Link>

        <nav className="management-nav" aria-label="Management navigation">
          <a className="is-active" href="#overview">
            <span>01</span> Overview
          </a>
          <a href="#modules">
            <span>02</span> Operations
          </a>
          <a href="#access">
            <span>03</span> Access profile
          </a>
        </nav>

        <div className="sidebar-status">
          <span aria-hidden="true" />
          <div>
            <p>Backend connected</p>
            <small>Supabase · Live</small>
          </div>
        </div>
      </aside>

      <section className="management-workspace">
        <header className="management-topbar">
          <div>
            <p>{primaryAssignment.organization_name}</p>
            <span>{primaryAssignment.location_name ?? "All locations"}</span>
          </div>
          <div className="staff-identity">
            <span className="staff-avatar" aria-hidden="true">{initials}</span>
            <div>
              <strong>{displayName}</strong>
              <small>{primaryAssignment.role_name}</small>
            </div>
            <form action={signOutStaff}>
              <button type="submit">Sign out</button>
            </form>
          </div>
        </header>

        <div className="management-content">
          <section className="management-hero" id="overview">
            <div>
              <p className="management-eyebrow">Operations overview</p>
              <h1>Good to see you, {firstName}.</h1>
              <p>
                Your secure Adee&apos;s Food workspace is connected. Modules appear according to your live role permissions.
              </p>
            </div>
            <div className="management-date-card">
              <span>Access scope</span>
              <strong>{primaryAssignment.role_code}</strong>
              <small>{primaryAssignment.location_name ?? "Organization-wide"}</small>
            </div>
          </section>

          <section className="system-strip" aria-label="System status">
            <div>
              <span className="status-dot" aria-hidden="true" />
              <p><strong>Database</strong><small>Connected</small></p>
            </div>
            <div>
              <p><strong>{access.permissions.length}</strong><small>Granted permissions</small></p>
            </div>
            <div>
              <p><strong>{assuranceLevel}</strong><small>Session security</small></p>
            </div>
          </section>

          <section className="management-modules" id="modules" aria-labelledby="modules-title">
            <div className="section-heading">
              <div>
                <p className="management-eyebrow">Role-aware workspace</p>
                <h2 id="modules-title">Management modules</h2>
              </div>
              <span>{primaryAssignment.role_name} access</span>
            </div>

            <div className="module-grid">
              {managementModules.map((module) => {
                const hasAccess = access.permissions.some((permission) =>
                  permission.startsWith(module.permissionPrefix),
                );

                return (
                  <article className={`module-card${hasAccess ? "" : " is-locked"}`} key={module.name}>
                    <div className="module-card-top">
                      <span>{module.marker}</span>
                      <i aria-hidden="true">{hasAccess ? "↗" : "—"}</i>
                    </div>
                    <h3>{module.name}</h3>
                    <p>{module.description}</p>
                    <small>{hasAccess ? "Access approved · Module setup next" : "Not included in your role"}</small>
                  </article>
                );
              })}
            </div>
          </section>

          <section className="access-panel" id="access" aria-labelledby="access-title">
            <div>
              <p className="management-eyebrow">Authenticated identity</p>
              <h2 id="access-title">Your access profile</h2>
            </div>
            <dl>
              <div><dt>Email</dt><dd>{email}</dd></div>
              <div><dt>Business</dt><dd>{primaryAssignment.organization_name}</dd></div>
              <div><dt>Location</dt><dd>{primaryAssignment.location_name ?? "All locations"}</dd></div>
              <div><dt>Role</dt><dd>{primaryAssignment.role_name}</dd></div>
            </dl>
          </section>
        </div>
      </section>
    </main>
  );
}
