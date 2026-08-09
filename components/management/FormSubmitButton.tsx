"use client";

import { useFormStatus } from "react-dom";

export function FormSubmitButton({ children, pendingText = "Saving…" }: { children: React.ReactNode; pendingText?: string }) {
  const { pending } = useFormStatus();
  return <button className="ops-primary-button" type="submit" disabled={pending}>{pending ? pendingText : children}</button>;
}
