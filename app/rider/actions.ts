"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

function value(formData: FormData, key: string) {
  const raw = formData.get(key);
  return typeof raw === "string" ? raw.trim() : "";
}

function messageFrom(error: unknown) {
  const message = error instanceof Error ? error.message : "The request could not be completed.";
  return message.replace(/^.*message[=:]\s*/i, "").slice(0, 180);
}

function finish(path: string, kind: "success" | "error", message: string) {
  redirect(`${path}?${kind}=${encodeURIComponent(message)}`);
}

async function advance(path: string, deliveryId: string, action: string, reason: string | undefined, success: string) {
  const supabase = await createClient();
  try {
    const { error } = await supabase.rpc("advance_delivery_status", {
      p_delivery_id: deliveryId,
      p_action: action,
      p_reason: reason ?? null,
    });
    if (error) throw error;
  } catch (error) {
    finish(path, "error", messageFrom(error));
  }
  revalidatePath("/rider");
  revalidatePath("/rider/history");
  finish(path, "success", success);
}

export async function acceptDelivery(formData: FormData) {
  await advance("/rider", value(formData, "delivery_id"), "ACCEPT", undefined, "Delivery accepted.");
}

export async function markPickedUp(formData: FormData) {
  await advance("/rider", value(formData, "delivery_id"), "PICKED_UP", undefined, "Marked picked up.");
}

export async function markOnTheWay(formData: FormData) {
  await advance("/rider", value(formData, "delivery_id"), "ON_THE_WAY", undefined, "Delivery started.");
}

export async function markDelivered(formData: FormData) {
  await advance("/rider", value(formData, "delivery_id"), "DELIVERED", undefined, "Marked delivered.");
}

export async function reportDeliveryIssue(formData: FormData) {
  const action = value(formData, "issue_action") || "FAILED";
  const reason = value(formData, "reason");
  if (reason.length < 3) finish("/rider", "error", "Enter a short reason.");
  await advance("/rider", value(formData, "delivery_id"), action, reason, "Issue reported.");
}

export async function setOwnRiderStatus(formData: FormData) {
  const supabase = await createClient();
  try {
    const { error } = await supabase.rpc("set_rider_status", {
      p_rider_profile_id: value(formData, "rider_profile_id"),
      p_status: value(formData, "status"),
    });
    if (error) throw error;
  } catch (error) {
    finish("/rider/profile", "error", messageFrom(error));
  }
  revalidatePath("/rider");
  revalidatePath("/rider/profile");
  finish("/rider/profile", "success", "Status updated.");
}
