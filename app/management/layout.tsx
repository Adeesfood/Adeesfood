import type { Metadata } from "next";
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
  const { access, assignment, displayName } = await getManagementSession();
  return (
    <ManagementShell
      displayName={displayName}
      organizationName={assignment.organization_name}
      locationName={assignment.location_name ?? "Main Branch"}
      roleName={assignment.role_name}
      permissions={access.permissions}
    >
      {children}
    </ManagementShell>
  );
}
