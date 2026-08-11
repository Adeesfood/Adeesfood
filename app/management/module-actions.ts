"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getManagementSession } from "@/lib/management";
import { createAdminClient } from "@/lib/supabase/admin";

function value(formData: FormData, key: string) {
  return String(formData.get(key) ?? "").trim();
}

function optionalValue(formData: FormData, key: string) {
  return value(formData, key) || null;
}

function numberValue(formData: FormData, key: string, fallback = 0) {
  const parsed = Number(value(formData, key));
  return Number.isFinite(parsed) ? parsed : fallback;
}

function moneyValue(formData: FormData, key: string) {
  return Math.round(numberValue(formData, key) * 100);
}

function messageFrom(error: unknown) {
  const message = error instanceof Error ? error.message : "The request could not be completed.";
  return message.replace(/^.*message[=:]\s*/i, "").slice(0, 180);
}

function finish(module: string, kind: "success" | "error", message: string) {
  redirect(`/management/${module}?${kind}=${encodeURIComponent(message)}`);
}

async function context(permission: string) {
  const session = await getManagementSession();
  if (!session.access.permissions.includes(permission)) {
    throw new Error("Your role does not allow this action.");
  }
  return session;
}

async function perform(module: string, success: string, operation: () => Promise<void>) {
  let errorMessage: string | null = null;
  try {
    await operation();
  } catch (error) {
    errorMessage = messageFrom(error);
  }
  if (errorMessage) finish(module, "error", errorMessage);
  revalidatePath(`/management/${module}`);
  revalidatePath("/management");
  finish(module, "success", success);
}

export async function createMenuCategory(formData: FormData) {
  await perform("menu", "Menu category created.", async () => {
    const { supabase, assignment } = await context("menu.manage_catalog");
    const { error } = await supabase.from("menu_categories").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      name: value(formData, "name"),
      description: optionalValue(formData, "description"),
      sort_order: numberValue(formData, "sort_order"),
    });
    if (error) throw error;
  });
}

export async function createMenuItem(formData: FormData) {
  await perform("menu", "Menu item added and ready for ordering.", async () => {
    const { supabase, assignment } = await context("menu.manage_catalog");
    const categoryId = value(formData, "category_id");
    const { data: item, error } = await supabase.from("menu_items").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      category_id: categoryId,
      sku: value(formData, "sku").toUpperCase(),
      name: value(formData, "name"),
      description: optionalValue(formData, "description"),
      price_minor: moneyValue(formData, "price"),
      station: value(formData, "station") || "MAIN KITCHEN",
      is_available: true,
    }).select("id").single();
    if (error) throw error;
    const { error: categoryError } = await supabase.from("menu_item_categories").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      menu_item_id: item.id,
      category_id: categoryId,
      is_primary: true,
    });
    if (categoryError) throw categoryError;
  });
}

export async function createMenuVariant(formData: FormData) {
  await perform("menu", "Menu variant added.", async () => {
    const { supabase, assignment } = await context("menu.manage_catalog");
    const name = value(formData, "name");
    const code = name.toUpperCase().replace(/[^A-Z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 32);
    if (!code) throw new Error("Enter a valid variant name.");
    const menuItemId = value(formData, "menu_item_id");
    const { count, error: countError } = await supabase.from("menu_item_variants")
      .select("id", { count: "exact", head: true }).eq("menu_item_id", menuItemId).eq("is_active", true);
    if (countError) throw countError;
    const { error } = await supabase.from("menu_item_variants").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      menu_item_id: menuItemId,
      code,
      name,
      price_minor: moneyValue(formData, "price"),
      currency_code: "GHS",
      sort_order: numberValue(formData, "sort_order", (count ?? 0) * 10 + 10),
      is_default: (count ?? 0) === 0,
      is_available: true,
      is_active: true,
    });
    if (error) throw error;
  });
}

export async function updateMenuCategory(formData: FormData) {
  await perform("menu", "Menu category updated.", async () => {
    const { supabase } = await context("menu.manage_catalog");
    const { error } = await supabase.from("menu_categories").update({
      name: value(formData, "name"),
      description: optionalValue(formData, "description"),
      sort_order: numberValue(formData, "sort_order"),
    }).eq("id", value(formData, "category_id"));
    if (error) throw error;
  });
}

export async function updateMenuItem(formData: FormData) {
  await perform("menu", "Menu item updated.", async () => {
    const { supabase } = await context("menu.manage_catalog");
    const menuItemId = value(formData, "menu_item_id");
    const categoryId = value(formData, "category_id");
    const { error } = await supabase.from("menu_items").update({
      category_id: categoryId,
      name: value(formData, "name"),
      description: optionalValue(formData, "description"),
      price_minor: moneyValue(formData, "price"),
      station: value(formData, "station") || "MAIN KITCHEN",
    }).eq("id", menuItemId);
    if (error) throw error;
    const { error: categoryError } = await supabase.from("menu_item_categories")
      .update({ category_id: categoryId })
      .eq("menu_item_id", menuItemId)
      .eq("is_primary", true);
    if (categoryError) throw categoryError;
  });
}

export async function updateMenuVariant(formData: FormData) {
  await perform("menu", "Menu variant updated.", async () => {
    const { supabase } = await context("menu.manage_catalog");
    const { error } = await supabase.from("menu_item_variants").update({
      name: optionalValue(formData, "name"),
      price_minor: moneyValue(formData, "price"),
      is_available: value(formData, "is_available") === "true",
    }).eq("id", value(formData, "variant_id"));
    if (error) throw error;
  });
}

export async function toggleMenuAvailability(formData: FormData) {
  const available = value(formData, "available") === "true";
  await perform("menu", available ? "Menu item is available." : "Menu item marked sold out.", async () => {
    const { supabase } = await context("menu.toggle_availability");
    const { error } = await supabase.rpc("toggle_menu_item_availability", {
      p_menu_item_id: value(formData, "menu_item_id"),
      p_available: available,
    });
    if (error) throw error;
  });
}

export async function createCustomer(formData: FormData) {
  await perform("customers", "Customer profile created.", async () => {
    const { supabase, assignment } = await context("customers.create_update_basic");
    const email = optionalValue(formData, "email");
    const { error } = await supabase.from("customers").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      display_name: value(formData, "display_name"),
      phone: optionalValue(formData, "phone"),
      email: email?.toLowerCase() ?? null,
      notes: optionalValue(formData, "notes"),
      marketing_consent: formData.get("marketing_consent") === "on",
    });
    if (error) throw error;
  });
}

export async function createRestaurantTable(formData: FormData) {
  await perform("tables", "Restaurant table created.", async () => {
    const { supabase, assignment } = await context("settings.manage_location");
    const { error } = await supabase.from("restaurant_tables").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      code: value(formData, "code").toUpperCase(),
      section_name: value(formData, "section_name") || "Main Floor",
      capacity: numberValue(formData, "capacity", 2),
    });
    if (error) throw error;
  });
}

export async function changeRestaurantTableStatus(formData: FormData) {
  await perform("tables", "Table status updated.", async () => {
    const { supabase } = await context("tables.change_status");
    const { error } = await supabase.rpc("change_restaurant_table_status", {
      p_table_id: value(formData, "table_id"),
      p_status: value(formData, "status"),
    });
    if (error) throw error;
  });
}

export async function createReservation(formData: FormData) {
  await perform("reservations", "Reservation created.", async () => {
    const { supabase, assignment } = await context("reservations.create_update");
    const startsAt = new Date(value(formData, "starts_at"));
    const durationMinutes = Math.max(numberValue(formData, "duration", 120), 30);
    const endsAt = new Date(startsAt.getTime() + durationMinutes * 60_000);
    if (Number.isNaN(startsAt.getTime())) throw new Error("Choose a valid reservation date and time.");
    const { error } = await supabase.from("reservations").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      customer_id: optionalValue(formData, "customer_id"),
      restaurant_table_id: optionalValue(formData, "table_id"),
      guest_name: value(formData, "guest_name"),
      guest_phone: value(formData, "guest_phone"),
      starts_at: startsAt.toISOString(),
      ends_at: endsAt.toISOString(),
      party_size: numberValue(formData, "party_size", 2),
      occasion: optionalValue(formData, "occasion"),
      notes: optionalValue(formData, "notes"),
      source: value(formData, "source") || "PHONE",
      status: "CONFIRMED",
    });
    if (error) throw error;
  });
}

export async function updateReservationStatus(formData: FormData) {
  await perform("reservations", "Reservation status updated.", async () => {
    const { supabase } = await context("reservations.create_update");
    const { error } = await supabase.from("reservations").update({ status: value(formData, "status") })
      .eq("id", value(formData, "reservation_id"));
    if (error) throw error;
  });
}

export async function createOrder(formData: FormData) {
  await perform("orders", "Order created and sent to the kitchen.", async () => {
    const { supabase, assignment } = await context("orders.create");
    let items: unknown;
    try { items = JSON.parse(value(formData, "items_json")); } catch { throw new Error("Add at least one valid menu item."); }
    if (!Array.isArray(items) || items.length === 0) throw new Error("Add at least one menu item.");
    const { error } = await supabase.rpc("create_order", {
      p_organization_id: assignment.organization_id,
      p_location_id: assignment.location_id,
      p_channel: value(formData, "channel"),
      p_items: items,
      p_customer_id: optionalValue(formData, "customer_id"),
      p_table_id: optionalValue(formData, "table_id"),
      p_notes: optionalValue(formData, "notes"),
      p_send_to_kitchen: true,
      p_guest_name: optionalValue(formData, "guest_name"),
      p_guest_phone: optionalValue(formData, "guest_phone"),
      p_guest_email: optionalValue(formData, "guest_email"),
      p_delivery_address: optionalValue(formData, "delivery_address"),
    });
    if (error) throw error;
  });
}

export async function recordOrderPayment(formData: FormData) {
  await perform("orders", "Payment recorded.", async () => {
    const { supabase } = await context("payments.record");
    const { error } = await supabase.rpc("record_order_payment", {
      p_order_id: value(formData, "order_id"),
      p_payment_method: value(formData, "payment_method"),
      p_amount_minor: moneyValue(formData, "amount"),
      p_external_reference: optionalValue(formData, "external_reference"),
    });
    if (error) throw error;
  });
}

export async function advanceOrder(formData: FormData) {
  const action = value(formData, "action");
  const success = action === "SEND_KITCHEN" ? "Online order accepted and sent to the kitchen." : "Order workflow updated.";
  await perform("orders", success, async () => {
    const required = action === "CANCEL"
      ? "orders.cancel_unstarted"
      : action === "SEND_KITCHEN"
        ? "orders.send_kitchen"
        : "orders.update_draft";
    const { supabase } = await context(required);
    const { error } = await supabase.rpc("advance_order", {
      p_order_id: value(formData, "order_id"),
      p_action: action,
      p_reason: optionalValue(formData, "reason"),
    });
    if (error) throw error;
  });
}

export async function advanceOrderKitchen(formData: FormData) {
  const nextStatus = value(formData, "next_status");
  await perform("orders", nextStatus === "PREPARING" ? "Order marked as preparing." : "Order marked ready.", async () => {
    const permission = nextStatus === "PREPARING" ? "kitchen.start_ticket" : "kitchen.ready_ticket";
    const { supabase } = await context(permission);
    const { error } = await supabase.rpc("advance_order_kitchen", {
      p_order_id: value(formData, "order_id"),
      p_next_status: nextStatus,
    });
    if (error) throw error;
  });
}

export async function createInventoryCategory(formData: FormData) {
  await perform("inventory", "Inventory category created.", async () => {
    const { supabase, assignment } = await context("inventory.manage_items_units");
    const { error } = await supabase.from("inventory_categories").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      name: value(formData, "name"),
    });
    if (error) throw error;
  });
}

export async function createInventoryItem(formData: FormData) {
  await perform("inventory", "Inventory item created.", async () => {
    const { supabase, assignment } = await context("inventory.manage_items_units");
    const { error } = await supabase.from("inventory_items").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      category_id: optionalValue(formData, "category_id"),
      sku: value(formData, "sku").toUpperCase(),
      name: value(formData, "name"),
      item_type: value(formData, "item_type"),
      unit: value(formData, "unit"),
      reorder_level: numberValue(formData, "reorder_level"),
      target_stock: numberValue(formData, "target_stock"),
      storage_location: optionalValue(formData, "storage_location"),
    });
    if (error) throw error;
  });
}

export async function postStockMovement(formData: FormData) {
  await perform("inventory", "Stock movement posted.", async () => {
    const movementType = value(formData, "movement_type");
    const required = movementType === "WASTAGE" ? "inventory.record_wastage" : "inventory.adjust";
    const { supabase } = await context(required);
    const unitCost = optionalValue(formData, "unit_cost");
    const { error } = await supabase.rpc("post_stock_movement", {
      p_inventory_item_id: value(formData, "inventory_item_id"),
      p_movement_type: movementType,
      p_quantity: numberValue(formData, "quantity"),
      p_unit_cost_minor: unitCost ? Math.round(Number(unitCost) * 100) : null,
      p_reason: value(formData, "reason"),
      p_reference_type: null,
      p_reference_id: null,
    });
    if (error) throw error;
  });
}

export async function createRecipe(formData: FormData) {
  await perform("recipes", "Draft recipe created with its first ingredient.", async () => {
    const { supabase, assignment } = await context("recipes.create_draft");
    const { error } = await supabase.rpc("create_recipe", {
      p_organization_id: assignment.organization_id,
      p_location_id: assignment.location_id,
      p_menu_item_id: value(formData, "menu_item_id"),
      p_inventory_item_id: value(formData, "inventory_item_id"),
      p_name: value(formData, "name"),
      p_ingredient_quantity: numberValue(formData, "ingredient_quantity"),
      p_yield_quantity: numberValue(formData, "yield_quantity", 1),
    });
    if (error) throw error;
  });
}

export async function publishRecipe(formData: FormData) {
  await perform("recipes", "Recipe published.", async () => {
    const { supabase } = await context("recipes.publish_version");
    const { error } = await supabase.rpc("publish_recipe", { p_recipe_id: value(formData, "recipe_id") });
    if (error) throw error;
  });
}

export async function createSupplier(formData: FormData) {
  await perform("suppliers", "Supplier created.", async () => {
    const { supabase, assignment } = await context("suppliers.manage");
    const email = optionalValue(formData, "email");
    const { error } = await supabase.from("suppliers").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      code: value(formData, "code").toUpperCase(),
      name: value(formData, "name"),
      contact_person: optionalValue(formData, "contact_person"),
      phone: optionalValue(formData, "phone"),
      email: email?.toLowerCase() ?? null,
      payment_terms: optionalValue(formData, "payment_terms"),
      notes: optionalValue(formData, "notes"),
    });
    if (error) throw error;
  });
}

export async function createPurchaseOrder(formData: FormData) {
  await perform("purchasing", "Purchase order issued.", async () => {
    const { supabase, assignment } = await context("purchase_orders.create_issue");
    const { error } = await supabase.rpc("create_purchase_order", {
      p_organization_id: assignment.organization_id,
      p_location_id: assignment.location_id,
      p_supplier_id: value(formData, "supplier_id"),
      p_inventory_item_id: value(formData, "inventory_item_id"),
      p_quantity: numberValue(formData, "quantity"),
      p_unit_cost_minor: moneyValue(formData, "unit_cost"),
      p_expected_delivery: optionalValue(formData, "expected_delivery"),
      p_notes: optionalValue(formData, "notes"),
    });
    if (error) throw error;
  });
}

export async function receivePurchaseOrder(formData: FormData) {
  await perform("purchasing", "Goods received and stock increased.", async () => {
    const { supabase } = await context("goods_receipts.record");
    const { error } = await supabase.rpc("receive_purchase_order", {
      p_purchase_order_id: value(formData, "purchase_order_id"),
    });
    if (error) throw error;
  });
}

export async function createExpense(formData: FormData) {
  await perform("finance", "Expense recorded.", async () => {
    const { supabase, assignment } = await context("expenses.create");
    const { error } = await supabase.from("expenses").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      category: value(formData, "category"),
      amount_minor: moneyValue(formData, "amount"),
      payment_method: value(formData, "payment_method"),
      vendor: optionalValue(formData, "vendor"),
      incurred_on: value(formData, "incurred_on"),
      description: value(formData, "description"),
      status: "POSTED",
    });
    if (error) throw error;
  });
}

export async function prepareDailyClose(formData: FormData) {
  await perform("finance", "Daily close totals refreshed.", async () => {
    const { supabase, assignment } = await context("daily_close.prepare");
    const { error } = await supabase.rpc("prepare_daily_close", {
      p_organization_id: assignment.organization_id,
      p_location_id: assignment.location_id,
      p_business_date: value(formData, "business_date"),
    });
    if (error) throw error;
  });
}

export async function createStaffShift(formData: FormData) {
  await perform("staff", "Staff shift scheduled.", async () => {
    const { supabase, assignment } = await context("staff.manage_shifts_attendance");
    const startsAt = new Date(value(formData, "starts_at"));
    const endsAt = new Date(value(formData, "ends_at"));
    if (Number.isNaN(startsAt.getTime()) || Number.isNaN(endsAt.getTime())) throw new Error("Choose a valid shift period.");
    const { error } = await supabase.from("staff_shifts").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      employment_id: value(formData, "employment_id"),
      starts_at: startsAt.toISOString(),
      ends_at: endsAt.toISOString(),
      notes: optionalValue(formData, "notes"),
    });
    if (error) throw error;
  });
}

export async function changeStaffRole(formData: FormData) {
  await perform("staff", "Staff access role updated.", async () => {
    const { supabase, assignment } = await context("security.manage_users_roles");
    const { error } = await supabase.rpc("change_staff_role", {
      p_organization_id: assignment.organization_id,
      p_location_id: assignment.location_id,
      p_profile_id: value(formData, "profile_id"),
      p_role_code: value(formData, "role_code"),
    });
    if (error) throw error;
  });
}

export async function inviteStaffMember(formData: FormData) {
  await perform("staff", "Staff member added. Share their email and temporary password to sign in.", async () => {
    const { supabase, assignment } = await context("security.manage_users_roles");
    const email = value(formData, "email").toLowerCase();
    const password = value(formData, "password");
    const displayName = value(formData, "display_name");
    if (!email.includes("@")) throw new Error("Enter a valid email address.");
    if (password.length < 8) throw new Error("Temporary password must be at least 8 characters.");

    const admin = createAdminClient();
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name: displayName },
    });
    if (createError) throw createError;
    const profileId = created.user?.id;
    if (!profileId) throw new Error("The staff account could not be created.");

    const { error: onboardError } = await supabase.rpc("onboard_staff_member", {
      p_organization_id: assignment.organization_id,
      p_location_id: assignment.location_id,
      p_profile_id: profileId,
      p_display_name: displayName,
      p_phone: optionalValue(formData, "phone"),
      p_employee_number: value(formData, "employee_number"),
      p_role_code: value(formData, "role_code"),
    });
    if (onboardError) {
      await admin.auth.admin.deleteUser(profileId);
      throw onboardError;
    }
  });
}

export async function archiveStaffMember(formData: FormData) {
  await perform("staff", "Staff member archived.", async () => {
    const { supabase, assignment } = await context("security.manage_users_roles");
    const { error } = await supabase.rpc("archive_staff_member", {
      p_organization_id: assignment.organization_id,
      p_location_id: assignment.location_id,
      p_profile_id: value(formData, "profile_id"),
      p_reason: optionalValue(formData, "reason"),
    });
    if (error) throw error;
  });
}

export async function updateRestaurantProfile(formData: FormData) {
  await perform("settings", "Restaurant profile updated.", async () => {
    const { supabase, assignment } = await context("settings.manage_location");
    const { error } = await supabase.rpc("update_restaurant_profile", {
      p_organization_id: assignment.organization_id,
      p_location_id: assignment.location_id,
      p_trading_name: value(formData, "trading_name"),
      p_location_name: value(formData, "location_name"),
      p_currency_code: value(formData, "currency_code").toUpperCase(),
      p_timezone: value(formData, "timezone"),
      p_phone: optionalValue(formData, "phone"),
      p_email: optionalValue(formData, "email"),
      p_address: optionalValue(formData, "address"),
    });
    if (error) throw error;
  });
}

export async function saveOperationalSetting(formData: FormData) {
  await perform("settings", "Operational setting saved.", async () => {
    const { supabase, assignment, claims } = await context("settings.manage_financial_security");
    const settingKey = value(formData, "setting_key");
    const settingValue = value(formData, "setting_value");
    const { error } = await supabase.from("operational_settings").upsert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      setting_key: settingKey,
      setting_value: { value: settingValue },
      description: optionalValue(formData, "description"),
      updated_by: String(claims.sub),
    }, { onConflict: "location_id,setting_key" });
    if (error) throw error;
  });
}

export async function assignRider(formData: FormData) {
  await perform("deliveries", "Rider assigned.", async () => {
    const { supabase } = await context("deliveries.assign");
    const { error } = await supabase.rpc("assign_delivery_rider", {
      p_order_id: value(formData, "order_id"),
      p_rider_id: value(formData, "rider_id"),
      p_delivery_fee_minor: moneyValue(formData, "delivery_fee"),
      p_delivery_zone_id: optionalValue(formData, "delivery_zone_id"),
      p_reason: optionalValue(formData, "reason"),
    });
    if (error) throw error;
  });
}

export async function advanceDeliveryStatusAction(formData: FormData) {
  await perform("deliveries", "Delivery updated.", async () => {
    const { supabase } = await context("deliveries.assign");
    const { error } = await supabase.rpc("advance_delivery_status", {
      p_delivery_id: value(formData, "delivery_id"),
      p_action: value(formData, "delivery_action"),
      p_reason: optionalValue(formData, "reason"),
    });
    if (error) throw error;
  });
}

export async function recordSettlement(formData: FormData) {
  await perform("deliveries", "Settlement recorded.", async () => {
    const { supabase, assignment } = await context("deliveries.record_settlement");
    const deliveryIds = formData.getAll("delivery_ids").map(String).filter(Boolean);
    if (deliveryIds.length === 0) throw new Error("Select at least one delivery to settle.");
    const { error } = await supabase.rpc("record_rider_settlement", {
      p_organization_id: assignment.organization_id,
      p_location_id: assignment.location_id,
      p_rider_id: value(formData, "rider_id"),
      p_actual_amount_minor: moneyValue(formData, "actual_amount"),
      p_delivery_ids: deliveryIds,
      p_handover_reference: optionalValue(formData, "handover_reference"),
      p_notes: optionalValue(formData, "notes"),
    });
    if (error) throw error;
  });
}

export async function activateRiderProfile(formData: FormData) {
  await perform("deliveries", "Rider activated.", async () => {
    const { supabase, assignment } = await context("deliveries.manage_rider_status");
    const { error } = await supabase.from("rider_profiles").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      profile_id: value(formData, "profile_id"),
      status: "OFFLINE",
    });
    if (error) throw error;
  });
}

export async function createDeliveryZone(formData: FormData) {
  await perform("deliveries", "Delivery zone added.", async () => {
    const { supabase, assignment } = await context("deliveries.manage_zones");
    const { error } = await supabase.from("delivery_zones").insert({
      organization_id: assignment.organization_id,
      location_id: assignment.location_id,
      name: value(formData, "name"),
      description: optionalValue(formData, "description"),
      base_fee_minor: moneyValue(formData, "base_fee"),
    });
    if (error) throw error;
  });
}
