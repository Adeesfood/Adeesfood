"use server";

import { createClient } from "@/lib/supabase/server";
import type { OnlineOrderState } from "@/lib/public-menu";

type SubmittedItem = {
  menu_item_id: string;
  menu_item_variant_id: string | null;
  modifier_option_ids: string[];
  quantity: number;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function field(formData: FormData, name: string) {
  return String(formData.get(name) ?? "").trim();
}

function cleanItems(value: string): SubmittedItem[] {
  if (!value || value.length > 100_000) throw new Error("Your cart could not be submitted.");
  const parsed: unknown = JSON.parse(value);
  if (!Array.isArray(parsed) || parsed.length === 0 || parsed.length > 50) {
    throw new Error("Add at least one menu item to your order.");
  }

  return parsed.map((raw) => {
    if (!raw || typeof raw !== "object") throw new Error("A cart item is invalid.");
    const item = raw as Partial<SubmittedItem>;
    const variantId = item.menu_item_variant_id ?? null;
    if (!item.menu_item_id || !uuidPattern.test(item.menu_item_id)) throw new Error("A cart item is invalid.");
    if (variantId && !uuidPattern.test(variantId)) throw new Error("A selected size is invalid.");
    if (!Array.isArray(item.modifier_option_ids) || item.modifier_option_ids.some((id) => typeof id !== "string" || !uuidPattern.test(id))) {
      throw new Error("A selected menu choice is invalid.");
    }
    if (!Number.isInteger(item.quantity) || Number(item.quantity) < 1 || Number(item.quantity) > 20) {
      throw new Error("Item quantities must be between 1 and 20.");
    }
    return {
      menu_item_id: item.menu_item_id,
      menu_item_variant_id: variantId,
      modifier_option_ids: item.modifier_option_ids,
      quantity: Number(item.quantity),
    };
  });
}

export async function submitOnlineOrder(
  _previousState: OnlineOrderState,
  formData: FormData,
): Promise<OnlineOrderState> {
  try {
    const locationId = field(formData, "location_id");
    const sourceReference = field(formData, "source_reference");
    const channel = field(formData, "channel").toUpperCase();
    const guestName = field(formData, "guest_name");
    const guestPhone = field(formData, "guest_phone");
    const guestEmail = field(formData, "guest_email");
    const deliveryAddress = field(formData, "delivery_address");
    const notes = field(formData, "notes");
    const items = cleanItems(field(formData, "items_json"));

    if (!uuidPattern.test(locationId) || !uuidPattern.test(sourceReference)) {
      throw new Error("Please refresh the menu and try again.");
    }
    if (!guestName || !guestPhone) throw new Error("Enter your name and phone number.");
    if (channel !== "TAKEAWAY" && channel !== "DELIVERY") throw new Error("Choose pickup or delivery.");
    if (channel === "DELIVERY" && !deliveryAddress) throw new Error("Enter the delivery address.");

    const supabase = await createClient();
    const { data, error } = await supabase.rpc("create_online_order_v2", {
      p_location_id: locationId,
      p_channel: channel,
      p_guest_name: guestName,
      p_guest_phone: guestPhone,
      p_items: items,
      p_source_reference: sourceReference,
      p_guest_email: guestEmail || null,
      p_delivery_address: deliveryAddress || null,
      p_notes: notes || null,
    });
    if (error) throw new Error(error.message);

    const result = data as {
      order_number?: string;
      total_minor?: number;
      currency_code?: string;
    } | null;
    if (!result?.order_number || !Number.isFinite(Number(result.total_minor))) {
      throw new Error("The restaurant did not return an order confirmation. Please contact Adee's Food.");
    }

    return {
      status: "success",
      message: "Your order has reached Adee's Food and is waiting for staff confirmation.",
      orderNumber: result.order_number,
      totalMinor: Number(result.total_minor),
      currencyCode: result.currency_code ?? "GHS",
    };
  } catch (error) {
    let message = error instanceof Error ? error.message : "Your order could not be submitted.";
    if (/JSON|syntax|invalid input syntax/i.test(message)) message = "Your cart could not be submitted. Please refresh and try again.";
    return { status: "error", message: message.slice(0, 220) };
  }
}
