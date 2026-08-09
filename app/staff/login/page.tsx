import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import { StaffLoginForm } from "@/components/StaffLoginForm";
import { parseAccessContext } from "@/lib/access";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Staff Login — Adee's Food",
  description: "Secure staff access to the Adee's Food management system.",
};

type LoginPageProps = {
  searchParams: Promise<{ error?: string }>;
};

const loginMessages: Record<string, string> = {
  "session-required": "Sign in with an authorized staff account to continue.",
  "no-access": "Your account is signed in but does not have an active staff assignment.",
};

export default async function StaffLoginPage({ searchParams }: LoginPageProps) {
  const supabase = await createClient();
  const [{ error }, { data: claimsData }] = await Promise.all([
    searchParams,
    supabase.auth.getClaims(),
  ]);

  if (claimsData?.claims) {
    const { data } = await supabase.rpc("get_my_access_context");
    if (parseAccessContext(data).assignments.length > 0) redirect("/management");
  }

  return (
    <main className="staff-login-page">
      <section className="login-brand-panel" aria-label="Adee's Food staff access">
        <div className="login-brand-glow" aria-hidden="true" />
        <Image
          src="/images/menu/grilled-chicken-reveal.webp"
          alt=""
          fill
          priority
          sizes="(max-width: 900px) 100vw, 52vw"
          className="login-brand-image"
        />
        <div className="login-brand-overlay" aria-hidden="true" />
        <Link className="login-wordmark" href="/" aria-label="Return to Adee's Food home">
          <Image src="/brand/adees-logo.webp" alt="" width={640} height={640} />
        </Link>
        <div className="login-brand-copy">
          <p>Private staff portal</p>
          <h1>
            Service starts
            <br />
            <em>behind the scenes.</em>
          </h1>
        </div>
      </section>

      <section className="login-form-panel" aria-labelledby="login-title">
        <Link className="login-back-link" href="/">
          <span aria-hidden="true">←</span> Back to website
        </Link>
        <div className="login-form-wrap">
          <p className="login-section-label">Adee&apos;s management system</p>
          <h2 id="login-title">Welcome back.</h2>
          <p className="login-form-intro">
            Sign in with the email and password assigned to your staff account.
          </p>
          <StaffLoginForm initialMessage={error ? loginMessages[error] : undefined} />
          <p className="login-security-note">
            Access is monitored and restricted by role. Contact an Owner if your account is inactive.
          </p>
        </div>
      </section>
    </main>
  );
}
