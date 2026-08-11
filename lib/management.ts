import { redirect } from "next/navigation";
import { parseAccessContext } from "@/lib/access";
import { createClient } from "@/lib/supabase/server";

export async function getManagementSession() {
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const claims = claimsData?.claims;
  if (!claims) redirect("/staff/login?error=session-required");

  const [{ data: accessData }, { data: profile }] = await Promise.all([
    supabase.rpc("get_my_access_context"),
    supabase.from("profiles").select("display_name").eq("id", String(claims.sub)).maybeSingle(),
  ]);
  const access = parseAccessContext(accessData);
  const baseAssignment =
    access.assignments.find((candidate) => candidate.location_id) ?? access.assignments[0];
  if (!baseAssignment) redirect("/staff/login?error=no-access");

  let assignment = baseAssignment;
  if (!assignment.location_id) {
    const { data: location } = await supabase
      .from("locations")
      .select("id, name")
      .eq("organization_id", assignment.organization_id)
      .eq("is_active", true)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();

    if (!location) redirect("/staff/login?error=no-access");
    assignment = {
      ...assignment,
      location_id: location.id,
      location_name: location.name,
    };
  }

  const email = typeof claims.email === "string" ? claims.email : "Authorized staff";
  const displayName =
    (typeof profile?.display_name === "string" ? profile.display_name : null) ?? email.split("@")[0];

  const { data: dineInSetting } = await supabase
    .from("operational_settings")
    .select("setting_value")
    .eq("location_id", assignment.location_id)
    .eq("setting_key", "operations.dine_in_enabled")
    .maybeSingle();
  // Adee's Food operates pickup + delivery only, so the absence of this
  // setting means dine-in stays hidden rather than defaulting to shown.
  // Setting values are always saved as strings through the generic
  // operational-settings form, matching every other setting key.
  const dineInEnabled = dineInSetting?.setting_value?.value === "true";

  return { supabase, claims, access, assignment, email, displayName, dineInEnabled };
}

export function hasPermission(permissions: string[], permission: string) {
  return permissions.includes(permission);
}

export function formatMoney(minor: number | string | null | undefined, currency = "GHS") {
  const value = typeof minor === "string" ? Number(minor) : (minor ?? 0);
  return new Intl.NumberFormat("en-GH", {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
  }).format(value / 100);
}

export function formatDateTime(value: string | null | undefined) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("en-GH", {
    timeZone: "Africa/Accra",
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export function businessDate(value = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Accra",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(value);
}
