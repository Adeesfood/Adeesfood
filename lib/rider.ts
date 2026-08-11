import { redirect } from "next/navigation";
import { parseAccessContext } from "@/lib/access";
import { createClient } from "@/lib/supabase/server";

export async function getRiderSession() {
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const claims = claimsData?.claims;
  if (!claims) redirect("/staff/login?error=session-required");

  const [{ data: accessData }, { data: profile }] = await Promise.all([
    supabase.rpc("get_my_access_context"),
    supabase.from("profiles").select("display_name").eq("id", String(claims.sub)).maybeSingle(),
  ]);
  const access = parseAccessContext(accessData);
  const assignment = access.assignments.find((candidate) => candidate.role_code === "DELIVERY_RIDER");

  // Anyone without an active DELIVERY_RIDER assignment does not belong here,
  // regardless of what other roles they hold.
  if (!assignment) redirect("/management");

  const email = typeof claims.email === "string" ? claims.email : "Rider";
  const displayName =
    (typeof profile?.display_name === "string" ? profile.display_name : null) ?? email.split("@")[0];

  const { data: riderProfile } = await supabase
    .from("rider_profiles")
    .select("id, status, cash_outstanding_minor")
    .eq("organization_id", assignment.organization_id)
    .eq("profile_id", String(claims.sub))
    .maybeSingle();

  return { supabase, claims, access, assignment, displayName, riderProfile };
}
