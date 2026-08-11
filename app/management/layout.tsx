import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { ManagementShell } from "@/components/management/ManagementShell";
import { getManagementSession } from "@/lib/management";
import "./management.css";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: { default: "Dashboard — Adee's Food", template: "%s — Adee's Food" },
  description: "Secure restaurant operations for authorized Adee's Food staff.",
  robots: { index: false, follow: false },
};

export default async function ManagementLayout({ children }: { children: React.ReactNode }) {
  const { access, assignment, displayName, dineInEnabled } = await getManagementSession();

  // Delivery riders get a completely separate, minimal mobile interface —
  // never the full management sidebar (revenue, customers, menu, etc.).
  if (assignment.role_code === "DELIVERY_RIDER") {
    redirect("/rider");
  }

  return (
    <ManagementShell
      displayName={displayName}
      organizationName={assignment.organization_name}
      locationName={assignment.location_name ?? "Main Branch"}
      roleName={assignment.role_name}
      permissions={access.permissions}
      dineInEnabled={dineInEnabled}
    >
      {children}
    </ManagementShell>
  );
}
