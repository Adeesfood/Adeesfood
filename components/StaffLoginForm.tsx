"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { parseAccessContext } from "@/lib/access";
import { createClient } from "@/lib/supabase/client";

type StaffLoginFormProps = {
  initialMessage?: string;
};

export function StaffLoginForm({ initialMessage }: StaffLoginFormProps) {
  const router = useRouter();
  const [errorMessage, setErrorMessage] = useState(initialMessage ?? "");
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setErrorMessage("");
    setIsSubmitting(true);

    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") ?? "").trim().toLowerCase();
    const password = String(form.get("password") ?? "");
    const supabase = createClient();

    const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });

    if (signInError) {
      setErrorMessage("We could not sign you in. Check your email and password.");
      setIsSubmitting(false);
      return;
    }

    const { data, error: accessError } = await supabase.rpc("get_my_access_context");
    const access = parseAccessContext(data);

    if (accessError || access.assignments.length === 0) {
      await supabase.auth.signOut();
      setErrorMessage("This account does not have an active Adee's Food staff assignment.");
      setIsSubmitting(false);
      return;
    }

    router.replace("/management");
    router.refresh();
  }

  return (
    <form className="staff-login-form" onSubmit={handleSubmit}>
      <div className="field-group">
        <label htmlFor="staff-email">Email address</label>
        <input
          id="staff-email"
          name="email"
          type="email"
          autoComplete="username"
          inputMode="email"
          required
          disabled={isSubmitting}
          placeholder="name@example.com"
        />
      </div>

      <div className="field-group">
        <label htmlFor="staff-password">Password</label>
        <input
          id="staff-password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
          minLength={8}
          disabled={isSubmitting}
          placeholder="Enter your password"
        />
      </div>

      <p className="login-feedback" role="status" aria-live="polite">
        {errorMessage}
      </p>

      <button className="staff-submit" type="submit" disabled={isSubmitting}>
        <span>{isSubmitting ? "Verifying access…" : "Enter management system"}</span>
        <i aria-hidden="true">→</i>
      </button>
    </form>
  );
}
