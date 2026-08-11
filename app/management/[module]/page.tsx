import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { FormSubmitButton } from "@/components/management/FormSubmitButton";
import { LiveRefresh } from "@/components/management/LiveRefresh";
import { OrderComposer } from "@/components/management/OrderComposer";
import { canAccessModule, managementModules } from "@/lib/access";
import { businessDate, formatDateTime, formatMoney, getManagementSession, hasPermission } from "@/lib/management";
import {
  activateRiderProfile,
  archiveStaffMember,
  advanceOrder,
  advanceOrderKitchen,
  assignRider,
  changeRestaurantTableStatus,
  changeStaffRole,
  createCustomer,
  createDeliveryZone,
  createExpense,
  createInventoryCategory,
  createInventoryItem,
  createMenuCategory,
  createMenuItem,
  createMenuVariant,
  createPurchaseOrder,
  createRecipe,
  createReservation,
  createRestaurantTable,
  createStaffShift,
  createSupplier,
  inviteStaffMember,
  postStockMovement,
  prepareDailyClose,
  publishRecipe,
  receivePurchaseOrder,
  recordOrderPayment,
  recordSettlement,
  saveOperationalSetting,
  toggleMenuAvailability,
  updateMenuCategory,
  updateMenuItem,
  updateMenuVariant,
  updateReservationStatus,
  updateRestaurantProfile,
  updateStaffMember,
} from "../module-actions";

type PageProps = {
  params: Promise<{ module: string }>;
  searchParams: Promise<{ success?: string; error?: string; from?: string; to?: string; view?: string; mode?: string }>;
};

type Session = Awaited<ReturnType<typeof getManagementSession>>;
type Query = Awaited<PageProps["searchParams"]>;
type RecipeIngredient = {
  quantity: number | string;
  unit: string;
  inventory_items: { name: string; average_cost_minor: number | string } | Array<{ name: string; average_cost_minor: number | string }> | null;
};
type PurchaseLine = { item_name: string; quantity: number | string; unit: string };
type CustomerOrder = { total_minor: number | string; created_at: string };
type NamedRelation = { name: string } | Array<{ name: string }> | null;
type MenuCategoryLink = { menu_categories: NamedRelation };
type MenuVariantRow = {
  id: string;
  name: string | null;
  price_minor: number;
  currency_code: string;
  is_default: boolean;
  is_available: boolean;
  is_active: boolean;
  sort_order: number;
};
type MenuModifierLink = { modifier_groups: NamedRelation };

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { module: slug } = await params;
  const moduleConfig = managementModules.find((item) => item.slug === slug);
  return { title: moduleConfig?.name ?? "Management" };
}

function Notice({ query }: { query: Query }) {
  if (query.success) return <div className="ops-alert is-success">{query.success}</div>;
  if (query.error) return <div className="ops-alert is-error">{query.error}</div>;
  return null;
}

function PageHead({ eyebrow, title, description, action }: { eyebrow: string; title: string; description: string; action?: React.ReactNode }) {
  return <section className="ops-page-head"><div><p className="ops-kicker">{eyebrow}</p><h1>{title}</h1><p>{description}</p></div>{action}</section>;
}

function Empty({ title, body }: { title: string; body: string }) {
  return <div className="ops-empty is-wide"><strong>{title}</strong><p>{body}</p></div>;
}

export default async function ModulePage({ params, searchParams }: PageProps) {
  const [{ module: slug }, query, session] = await Promise.all([params, searchParams, getManagementSession()]);
  const moduleConfig = managementModules.find((item) => item.slug === slug);
  if (!moduleConfig) redirect("/management");
  if (!canAccessModule(session.access.permissions, moduleConfig, session.dineInEnabled)) redirect("/management?error=access");

  let content: React.ReactNode;
  switch (slug) {
    case "orders": content = await OrdersModule(session, query); break;
    case "deliveries": content = await DeliveriesModule(session); break;
    case "tables": content = await TablesModule(session); break;
    case "menu": content = await MenuModule(session); break;
    case "inventory": content = await InventoryModule(session); break;
    case "recipes": content = await RecipesModule(session); break;
    case "purchasing": content = await PurchasingModule(session); break;
    case "suppliers": content = await SuppliersModule(session); break;
    case "customers": content = await CustomersModule(session); break;
    case "reservations": content = await ReservationsModule(session); break;
    case "staff": content = await StaffModule(session); break;
    case "finance": content = await FinanceModule(session); break;
    case "reports": content = await ReportsModule(session, query); break;
    case "settings": content = await SettingsModule(session); break;
    default: redirect("/management");
  }

  return <><Notice query={query} />{content}</>;
}

async function OrdersModule(session: Session, query: Query) {
  const { supabase, assignment, access, dineInEnabled } = session;
  const CLOSED_ORDER_STATUSES = ["COMPLETED", "CANCELLED", "VOIDED", "REFUNDED"];
  const view = query.view === "completed" ? "completed" : query.view === "all" ? "all" : "active";
  const canCreate = hasPermission(access.permissions, "orders.create");
  const composing = canCreate && query.mode === "new";

  if (composing) {
    const [menuResult, customersResult, tablesResult] = await Promise.all([
      supabase.from("menu_items").select("id, name, description, price_minor, station, is_available, is_price_from, menu_categories(name), menu_item_categories(menu_categories(name)), menu_item_variants(id, name, price_minor, is_default, is_available, is_active, sort_order), menu_item_modifier_groups(sort_order, modifier_groups(id, name, selection_type, min_selections, max_selections, is_required, modifier_options(id, name, price_delta_minor, is_available, is_active, sort_order)))")
        .eq("location_id", assignment.location_id).eq("is_active", true).order("name"),
      supabase.from("customers").select("id, display_name, phone").eq("location_id", assignment.location_id).eq("is_active", true).order("display_name").limit(100),
      supabase.from("restaurant_tables").select("id, code, capacity, status").eq("location_id", assignment.location_id).eq("is_active", true).in("status", ["AVAILABLE", "OCCUPIED"]).order("code"),
    ]);
    const menuItems = (menuResult.data ?? []).map((item) => ({
      ...item,
      categories: Array.from(new Set([
        ...(item.menu_item_categories ?? []).flatMap((link) => {
          const relation = Array.isArray(link.menu_categories) ? link.menu_categories[0] : link.menu_categories;
          return relation?.name ? [relation.name] : [];
        }),
        ...(() => {
          const primary = Array.isArray(item.menu_categories) ? item.menu_categories[0] : item.menu_categories;
          return primary?.name ? [primary.name] : [];
        })(),
      ])),
      variants: (item.menu_item_variants ?? []).sort((a, b) => a.sort_order - b.sort_order),
      modifier_groups: (item.menu_item_modifier_groups ?? []).flatMap((link) => {
        const group = Array.isArray(link.modifier_groups) ? link.modifier_groups[0] : link.modifier_groups;
        if (!group) return [];
        return [{
          ...group,
          options: (group.modifier_options ?? []).sort((a, b) => a.sort_order - b.sort_order),
        }];
      }),
    }));
    const customers = (customersResult.data ?? []).map((customer) => ({ id: customer.id, label: `${customer.display_name}${customer.phone ? ` · ${customer.phone}` : ""}` }));
    const tables = (tablesResult.data ?? []).map((table) => ({ id: table.id, label: `${table.code} · ${table.capacity} seats · ${table.status}` }));

    return <>
      <PageHead eyebrow="Front of house" title="New order" description="Build the order, then send it straight to the kitchen." action={<Link className="ops-head-action" href="/management/orders">Back to orders</Link>} />
      {menuItems.length ? <OrderComposer menuItems={menuItems} customers={customers} tables={tables} dineInEnabled={dineInEnabled} /> :
        <section className="ops-panel"><Empty title="Add the menu before taking orders" body="Create at least one category and available menu item in Menu, then return to the POS." /><Link className="ops-inline-action" href="/management/menu">Open menu management</Link></section>}
    </>;
  }

  const { data: ordersData } = await supabase.from("orders").select("id, order_number, channel, order_source, order_status, kitchen_status, payment_status, fulfillment_status, total_minor, amount_paid_minor, currency_code, notes, guest_name, guest_phone, guest_email, delivery_address, created_at, customers(display_name), restaurant_tables(code), order_items(item_name, variant_name, quantity, order_item_modifiers(option_name))")
    .eq("location_id", assignment.location_id).order("created_at", { ascending: false }).limit(50);
  const allOrders = ordersData ?? [];
  const visibleOrders = view === "all" ? allOrders
    : view === "completed" ? allOrders.filter((order) => CLOSED_ORDER_STATUSES.includes(order.order_status))
    : allOrders.filter((order) => !CLOSED_ORDER_STATUSES.includes(order.order_status));
  const activeCount = allOrders.filter((order) => !CLOSED_ORDER_STATUSES.includes(order.order_status)).length;

  return <>
    <LiveRefresh tables={["orders", "kitchen_tickets"]} />
    <PageHead eyebrow="Front of house" title="Orders" description="Every order in one place — active orders stay visible here, including the ones you've already sent to the kitchen." action={canCreate ? <Link className="ops-head-action" href="/management/orders?mode=new">New order <span>＋</span></Link> : null} />

    <section className="ops-panel">
      <div className="ops-panel-head"><div><p className="ops-kicker">Order history</p><h2>{activeCount} active order{activeCount === 1 ? "" : "s"}</h2></div><span>{visibleOrders.length} shown</span></div>
      <div className="ops-tabs" role="group" aria-label="Filter orders">
        <Link className={view === "active" ? "is-active" : ""} href="/management/orders?view=active">Active</Link>
        <Link className={view === "completed" ? "is-active" : ""} href="/management/orders?view=completed">Completed</Link>
        <Link className={view === "all" ? "is-active" : ""} href="/management/orders?view=all">All</Link>
      </div>
      <div className="ops-table-wrap"><table className="ops-table"><thead><tr><th>Order</th><th>Guest / channel</th><th>Items</th><th>Kitchen</th><th>Payment</th><th>Total</th><th>Actions</th></tr></thead><tbody>
        {visibleOrders.map((order) => {
          const customer = Array.isArray(order.customers) ? order.customers[0] : order.customers;
          const table = Array.isArray(order.restaurant_tables) ? order.restaurant_tables[0] : order.restaurant_tables;
          const balance = Number(order.total_minor) - Number(order.amount_paid_minor);
          const guestName = customer?.display_name ?? order.guest_name ?? "Walk-in guest";
          const contact = [order.guest_phone, order.guest_email].filter(Boolean).join(" · ");
          return <tr key={order.id}><td><strong>{order.order_number}</strong><small>{formatDateTime(order.created_at)}</small>{order.order_source === "WEBSITE" ? <span className="ops-source-label">Website order</span> : null}</td><td>{guestName}<small><span className={`ops-pill is-${order.channel.toLowerCase()}`}>{order.channel.replaceAll("_", " ")}</span>{table?.code ? ` · Table ${table.code}` : ""}</small>{contact ? <small>{contact}</small> : null}{order.delivery_address ? <small className="ops-address">Deliver to: {order.delivery_address}</small> : null}</td><td>{(order.order_items ?? []).map((item) => { const modifiers = (item.order_item_modifiers ?? []).map((modifier) => modifier.option_name).join(" + "); return `${item.quantity}× ${item.item_name}${item.variant_name ? ` (${item.variant_name})` : ""}${modifiers ? ` · ${modifiers}` : ""}`; }).join(", ")}</td><td><span className={`ops-pill is-${order.kitchen_status.toLowerCase()}`}>{order.kitchen_status.replaceAll("_", " ")}</span>
            {order.kitchen_status === "QUEUED" && hasPermission(access.permissions, "kitchen.start_ticket") ? <form action={advanceOrderKitchen} className="ops-inline-form"><input type="hidden" name="order_id" value={order.id} /><input type="hidden" name="next_status" value="PREPARING" /><button type="submit">Start prep</button></form> : null}
            {order.kitchen_status === "PREPARING" && hasPermission(access.permissions, "kitchen.ready_ticket") ? <form action={advanceOrderKitchen} className="ops-inline-form"><input type="hidden" name="order_id" value={order.id} /><input type="hidden" name="next_status" value="READY" /><button type="submit">Mark ready</button></form> : null}
          </td><td><span className={`ops-pill is-${order.payment_status.toLowerCase()}`}>{order.payment_status.replaceAll("_", " ")}</span></td><td><strong>{formatMoney(order.total_minor, order.currency_code)}</strong><small>{balance > 0 ? `${formatMoney(balance)} due` : "Settled"}</small></td><td><div className="ops-row-actions">
            {order.order_status === "CONFIRMED" && order.kitchen_status === "NOT_SENT" && hasPermission(access.permissions, "orders.send_kitchen") ? <form action={advanceOrder}><input type="hidden" name="order_id" value={order.id} /><input type="hidden" name="action" value="SEND_KITCHEN" /><button className="is-primary" type="submit">Accept &amp; send</button></form> : null}
            {balance > 0 && hasPermission(access.permissions, "payments.record") ? <form action={recordOrderPayment} className="ops-inline-form"><input type="hidden" name="order_id" value={order.id} /><input name="amount" type="number" min="0.01" step="0.01" defaultValue={(balance / 100).toFixed(2)} aria-label="Payment amount" /><select name="payment_method" aria-label="Payment method"><option>CASH</option><option>MOMO</option><option>CARD</option><option>ONLINE</option></select><button type="submit">Pay</button></form> : null}
            {order.payment_status === "PAID" && order.order_status !== "COMPLETED" ? <form action={advanceOrder}><input type="hidden" name="order_id" value={order.id} /><input type="hidden" name="action" value="COMPLETE" /><button type="submit">Complete</button></form> : null}
            {!CLOSED_ORDER_STATUSES.includes(order.order_status) && hasPermission(access.permissions, "orders.cancel_unstarted") ? <form action={advanceOrder}><input type="hidden" name="order_id" value={order.id} /><input type="hidden" name="action" value="CANCEL" /><input type="hidden" name="reason" value="Cancelled by authorized staff" /><button className="is-danger" type="submit">Cancel</button></form> : null}
          </div></td></tr>;
        })}
      </tbody></table>{visibleOrders.length ? null : <Empty title={view === "active" ? "No active orders" : "No orders recorded"} body="Orders from the website and staff POS will appear here automatically." />}</div>
    </section>
  </>;
}

async function DeliveriesModule(session: Session) {
  const { supabase, assignment, access } = session;

  const CLOSED_ORDER_STATUSES = ["COMPLETED", "CANCELLED", "VOIDED", "REFUNDED"];
  const CLOSED_DELIVERY_STATUSES = ["DELIVERED", "CANCELLED", "RETURNED"];

  const [ordersResult, deliveriesResult, ridersResult, zonesResult] = await Promise.all([
    supabase.from("orders").select("id, order_number, order_status, guest_name, guest_phone, delivery_address, total_minor, payment_status")
      .eq("location_id", assignment.location_id).eq("channel", "DELIVERY")
      .order("created_at", { ascending: false }).limit(100),
    supabase.from("deliveries").select("id, order_id, delivery_status, address_line, delivery_fee_minor, currency_code, amount_due_minor, settlement_status, payment_method, rider_id, orders(order_number), profiles(display_name)")
      .eq("location_id", assignment.location_id)
      .order("assigned_at", { ascending: true }).limit(100),
    supabase.from("user_role_assignments").select("profile_id, profiles(display_name), roles!inner(code)")
      .eq("organization_id", assignment.organization_id).is("revoked_at", null).eq("roles.code", "DELIVERY_RIDER"),
    supabase.from("delivery_zones").select("id, name, base_fee_minor, currency_code, is_active").eq("location_id", assignment.location_id).order("name"),
  ]);

  const riderProfileIds = new Set((ridersResult.data ?? []).map((row) => row.profile_id));
  const { data: riderProfiles } = riderProfileIds.size
    ? await supabase.from("rider_profiles").select("id, profile_id, status, cash_outstanding_minor").eq("organization_id", assignment.organization_id)
    : { data: [] };
  const activeDeliveries = (deliveriesResult.data ?? []).filter((delivery) => !CLOSED_DELIVERY_STATUSES.includes(delivery.delivery_status));
  const activeDeliveryOrderIds = new Set(activeDeliveries.map((delivery) => delivery.order_id));
  const awaitingRider = (ordersResult.data ?? []).filter(
    (order) => !CLOSED_ORDER_STATUSES.includes(order.order_status) && !activeDeliveryOrderIds.has(order.id),
  );
  const codDeliveries = activeDeliveries.filter((delivery) => delivery.settlement_status === "COLLECTED_BY_RIDER");

  return <>
    <LiveRefresh tables={["orders", "deliveries", "rider_profiles"]} />
    <PageHead eyebrow="Fulfillment" title="Deliveries" description="Assign riders, track dispatch through delivery, and settle cash collected on the way." />

    <section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Needs a rider</p><h2>Awaiting dispatch</h2></div><span>{awaitingRider.length} orders</span></div>
      <div className="ops-list">{awaitingRider.map((order) => (
        <div className="ops-list-row" key={order.id}>
          <div><strong>{order.order_number}</strong><small>{order.guest_name} · {order.delivery_address ?? "No address on file"}</small></div>
          <b>{formatMoney(order.total_minor)}</b>
          {hasPermission(access.permissions, "deliveries.assign") ? (
            <form action={assignRider} className="ops-inline-form">
              <input type="hidden" name="order_id" value={order.id} />
              <select name="rider_id" required defaultValue="">
                <option value="" disabled>Choose rider</option>
                {(ridersResult.data ?? []).map((rider) => {
                  const profile = Array.isArray(rider.profiles) ? rider.profiles[0] : rider.profiles;
                  return <option value={rider.profile_id} key={rider.profile_id}>{profile?.display_name}</option>;
                })}
              </select>
              <select name="delivery_zone_id" defaultValue="">
                <option value="">No zone</option>
                {(zonesResult.data ?? []).filter((zone) => zone.is_active).map((zone) => <option value={zone.id} key={zone.id}>{zone.name}</option>)}
              </select>
              <input name="delivery_fee" type="number" min="0" step="0.01" placeholder="Fee (GHS)" />
              <button type="submit">Assign</button>
            </form>
          ) : null}
        </div>
      ))}{awaitingRider.length ? null : <Empty title="Nothing waiting" body="Confirmed delivery orders that still need a rider will appear here." />}</div>
    </section>

    <section className="ops-panel ops-section-gap"><div className="ops-panel-head"><div><p className="ops-kicker">In progress</p><h2>Dispatch queue</h2></div><span>{activeDeliveries.length} active</span></div>
      <div className="ops-list">{activeDeliveries.map((delivery) => {
        const order = Array.isArray(delivery.orders) ? delivery.orders[0] : delivery.orders;
        const rider = Array.isArray(delivery.profiles) ? delivery.profiles[0] : delivery.profiles;
        return (
          <div className="ops-list-row" key={delivery.id}>
            <div><strong>{order?.order_number}</strong><small>{rider?.display_name ?? "Unassigned"} · {delivery.address_line}</small></div>
            <em>{delivery.delivery_status.replace(/_/g, " ")}</em>
            {delivery.payment_method === "CASH_ON_DELIVERY" ? <b>{formatMoney(delivery.amount_due_minor, delivery.currency_code)} COD</b> : null}
          </div>
        );
      })}{activeDeliveries.length ? null : <Empty title="No active deliveries" body="Assigned deliveries move through accepted, picked up, on the way, and delivered here." />}</div>
    </section>

    <div className="ops-split-layout ops-section-gap">
      <section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Riders</p><h2>Roster & status</h2></div></div>
        <div className="ops-list">{(ridersResult.data ?? []).map((rider) => {
          const profile = Array.isArray(rider.profiles) ? rider.profiles[0] : rider.profiles;
          const riderProfile = (riderProfiles ?? []).find((row) => row.profile_id === rider.profile_id);
          return (
            <div className="ops-list-row" key={rider.profile_id}>
              <div><strong>{profile?.display_name}</strong><small>{riderProfile ? `Cash held: ${formatMoney(riderProfile.cash_outstanding_minor)}` : "Not yet activated"}</small></div>
              {riderProfile ? <em>{riderProfile.status.replace(/_/g, " ")}</em> : (
                hasPermission(access.permissions, "deliveries.manage_rider_status") ? (
                  <form action={activateRiderProfile}><input type="hidden" name="profile_id" value={rider.profile_id} /><button type="submit">Activate</button></form>
                ) : null
              )}
            </div>
          );
        })}{ridersResult.data?.length ? null : <Empty title="No riders yet" body="Assign the Delivery Rider role to a staff member in Staff, then activate them here." />}</div>
      </section>

      {hasPermission(access.permissions, "deliveries.record_settlement") ? (
        <section className="ops-form-card"><p className="ops-kicker">Cash on delivery</p><h2>Record rider settlement</h2>
          <form action={recordSettlement} className="ops-form">
            <label>Rider<select name="rider_id" required defaultValue="">
              <option value="" disabled>Choose rider</option>
              {(ridersResult.data ?? []).map((rider) => {
                const profile = Array.isArray(rider.profiles) ? rider.profiles[0] : rider.profiles;
                return <option value={rider.profile_id} key={rider.profile_id}>{profile?.display_name}</option>;
              })}
            </select></label>
            <label>Deliveries to settle<select name="delivery_ids" multiple required size={Math.min(6, Math.max(3, codDeliveries.length))}>
              {codDeliveries.map((delivery) => {
                const order = Array.isArray(delivery.orders) ? delivery.orders[0] : delivery.orders;
                return <option value={delivery.id} key={delivery.id}>{order?.order_number} · {formatMoney(delivery.amount_due_minor, delivery.currency_code)}</option>;
              })}
            </select></label>
            <label>Actual amount received (GHS)<input name="actual_amount" type="number" min="0" step="0.01" required /></label>
            <label>Handover reference<input name="handover_reference" /></label>
            <label>Notes (required if amount differs)<textarea name="notes" rows={2} /></label>
            <FormSubmitButton>Record settlement</FormSubmitButton>
          </form>
        </section>
      ) : null}
    </div>

    {hasPermission(access.permissions, "deliveries.manage_zones") ? (
      <section className="ops-panel ops-section-gap"><div className="ops-panel-head"><div><p className="ops-kicker">Coverage</p><h2>Delivery zones</h2></div></div>
        <div className="ops-list">{(zonesResult.data ?? []).map((zone) => (
          <div className="ops-list-row" key={zone.id}><div><strong>{zone.name}</strong></div><b>{formatMoney(zone.base_fee_minor, zone.currency_code)}</b></div>
        ))}{zonesResult.data?.length ? null : <Empty title="No zones configured" body="Zones are optional — you can keep setting the delivery fee manually per order." />}</div>
        <form action={createDeliveryZone} className="ops-form">
          <label>Zone name<input name="name" required placeholder="Zone A" /></label>
          <label>Base fee (GHS)<input name="base_fee" type="number" min="0" step="0.01" required /></label>
          <FormSubmitButton>Add zone</FormSubmitButton>
        </form>
      </section>
    ) : null}
  </>;
}

async function TablesModule(session: Session) {
  const { supabase, assignment, access } = session;
  const { data: tables } = await supabase.from("restaurant_tables").select("*").eq("location_id", assignment.location_id).eq("is_active", true).order("section_name").order("code");
  return <>
    <LiveRefresh tables={["restaurant_tables"]} />
    <PageHead eyebrow="Floor service" title="Tables" description="See capacity and readiness at a glance, then move each table through service and cleaning." />
    <div className="ops-split-layout"><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Floor plan</p><h2>Table status</h2></div><span>{tables?.length ?? 0} tables</span></div><div className="table-grid">{(tables ?? []).map((table) => <article className={`table-card is-${table.status.toLowerCase()}`} key={table.id}><div><span>{table.section_name}</span><h3>{table.code}</h3><p>{table.capacity} seats</p></div><strong>{table.status}</strong><form action={changeRestaurantTableStatus}><input type="hidden" name="table_id" value={table.id} /><select name="status" defaultValue={table.status}><option>AVAILABLE</option><option>OCCUPIED</option><option>RESERVED</option><option>CLEANING</option><option>UNAVAILABLE</option></select><button type="submit">Update</button></form></article>)}{tables?.length ? null : <Empty title="No tables configured" body="Add the first restaurant table to begin dine-in orders and reservations." />}</div></section>
      {hasPermission(access.permissions, "settings.manage_location") ? <section className="ops-form-card"><p className="ops-kicker">Floor setup</p><h2>Add a table</h2><form action={createRestaurantTable} className="ops-form"><label>Table code<input name="code" required placeholder="T01" /></label><label>Section<input name="section_name" required defaultValue="Main Floor" /></label><label>Capacity<input name="capacity" type="number" min="1" max="50" defaultValue="2" required /></label><FormSubmitButton>Add table</FormSubmitButton></form></section> : null}</div>
  </>;
}

async function MenuModule(session: Session) {
  const { supabase, assignment, access } = session;
  const [{ data: categories }, { data: items }] = await Promise.all([
    supabase.from("menu_categories").select("*").eq("location_id", assignment.location_id).order("sort_order").order("name"),
    supabase.from("menu_items").select("*, menu_categories(name), menu_item_categories(menu_categories(name)), menu_item_variants(id, name, price_minor, currency_code, is_default, is_available, is_active, sort_order), menu_item_modifier_groups(modifier_groups(name))").eq("location_id", assignment.location_id).order("name"),
  ]);
  const canEditCatalog = hasPermission(access.permissions, "menu.manage_catalog");
  return <>
    <LiveRefresh tables={["menu_items"]} />
    <PageHead eyebrow="Single source of truth" title="Menu" description="The same live catalog powers POS availability, kitchen routing, recipes, and future website ordering." />
    <div className="ops-split-layout is-wide-main">
      <section className="ops-panel">
        <div className="ops-panel-head"><div><p className="ops-kicker">Catalog</p><h2>Menu items</h2></div><span>{items?.filter((item) => item.is_available).length ?? 0} available</span></div>
        <div className="ops-card-list">
          {(items ?? []).map((item) => {
            const categoryNames = Array.from(new Set((item.menu_item_categories ?? []).flatMap((link: MenuCategoryLink) => { const relation = Array.isArray(link.menu_categories) ? link.menu_categories[0] : link.menu_categories; return relation?.name ? [relation.name] : []; })));
            const variants = (item.menu_item_variants ?? []).filter((variant: MenuVariantRow) => variant.is_active).sort((a: MenuVariantRow, b: MenuVariantRow) => a.sort_order - b.sort_order);
            const modifierNames = (item.menu_item_modifier_groups ?? []).flatMap((link: MenuModifierLink) => { const relation = Array.isArray(link.modifier_groups) ? link.modifier_groups[0] : link.modifier_groups; return relation?.name ? [relation.name] : []; });
            return (
              <article className="catalog-row" key={item.id}>
                <div>
                  <span>{categoryNames.join(" + ") || item.menu_categories?.name || "Uncategorized"} · {item.station}</span>
                  <h3>{item.name}</h3>
                  <p>{item.description || item.sku}</p>
                  {variants.length ? <div className="catalog-variants">{variants.map((variant: MenuVariantRow) => <em key={variant.id}>{variant.name ?? "Unlabeled option"} · {formatMoney(variant.price_minor, variant.currency_code)}{variant.is_available ? "" : " · sold out"}</em>)}</div> : null}
                  {modifierNames.length ? <small className="catalog-modifiers">Choices: {modifierNames.join(" · ")}</small> : null}
                  {item.source_notes ? <small className="catalog-source-note">Review: {item.source_notes}</small> : null}
                  {canEditCatalog ? (
                    <details className="catalog-edit">
                      <summary>Edit item</summary>
                      <form action={updateMenuItem} className="ops-form">
                        <input type="hidden" name="menu_item_id" value={item.id} />
                        <label>Category<select name="category_id" required defaultValue={item.category_id}>{(categories ?? []).map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}</select></label>
                        <label>Item name<input name="name" required defaultValue={item.name} /></label>
                        <div className="ops-form-row">
                          <label>Price (GHS)<input name="price" type="number" min="0" step="0.01" required defaultValue={(item.price_minor / 100).toFixed(2)} /></label>
                          <label>Kitchen station<select name="station" defaultValue={item.station}><option>MAIN KITCHEN</option><option>GRILL</option><option>PIZZA</option><option>DRINKS</option><option>PASTRY</option></select></label>
                        </div>
                        <label>Description<textarea name="description" rows={2} defaultValue={item.description ?? ""} /></label>
                        <FormSubmitButton>Save changes</FormSubmitButton>
                      </form>
                      {variants.length ? (
                        <div className="catalog-variant-edit-list">
                          {variants.map((variant: MenuVariantRow) => (
                            <form action={updateMenuVariant} className="ops-inline-form" key={variant.id}>
                              <input type="hidden" name="variant_id" value={variant.id} />
                              <input name="name" defaultValue={variant.name ?? ""} placeholder="Variant name" />
                              <input name="price" type="number" min="0" step="0.01" required defaultValue={(variant.price_minor / 100).toFixed(2)} />
                              <select name="is_available" defaultValue={String(variant.is_available)}><option value="true">Available</option><option value="false">Sold out</option></select>
                              <FormSubmitButton>Save</FormSubmitButton>
                            </form>
                          ))}
                        </div>
                      ) : null}
                    </details>
                  ) : null}
                </div>
                <strong>{item.is_price_from || variants.length ? "From " : ""}{formatMoney(item.price_minor, item.currency_code)}</strong>
                <form action={toggleMenuAvailability}>
                  <input type="hidden" name="menu_item_id" value={item.id} />
                  <input type="hidden" name="available" value={String(!item.is_available)} />
                  <button className={item.is_available ? "is-danger" : ""} type="submit">{item.is_available ? "Mark sold out" : "Make available"}</button>
                </form>
              </article>
            );
          })}
          {items?.length ? null : <Empty title="Your menu is ready to be built" body="Create a category, then add the first priced menu item without inventing duplicate variants." />}
        </div>
      </section>
      {canEditCatalog ? (
        <div className="ops-form-stack">
          <section className="ops-form-card">
            <p className="ops-kicker">Structure</p><h2>Categories</h2>
            {(categories ?? []).length ? (
              <div className="ops-list">
                {(categories ?? []).map((category) => (
                  <details className="catalog-edit" key={category.id}>
                    <summary>{category.name}</summary>
                    <form action={updateMenuCategory} className="ops-form">
                      <input type="hidden" name="category_id" value={category.id} />
                      <label>Name<input name="name" required defaultValue={category.name} /></label>
                      <label>Description<textarea name="description" rows={2} defaultValue={category.description ?? ""} /></label>
                      <label>Sort order<input name="sort_order" type="number" defaultValue={category.sort_order} /></label>
                      <FormSubmitButton>Save changes</FormSubmitButton>
                    </form>
                  </details>
                ))}
              </div>
            ) : null}
            <form action={createMenuCategory} className="ops-form"><label>Name<input name="name" required placeholder="Rice & meals" /></label><label>Description<textarea name="description" rows={2} /></label><label>Sort order<input name="sort_order" type="number" defaultValue="0" /></label><FormSubmitButton>Add category</FormSubmitButton></form>
          </section>
          <section className="ops-form-card"><p className="ops-kicker">Sellable item</p><h2>New menu item</h2><form action={createMenuItem} className="ops-form"><label>Category<select name="category_id" required defaultValue=""><option value="" disabled>Choose category</option>{(categories ?? []).map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}</select></label><label>Item name<input name="name" required /></label><div className="ops-form-row"><label>SKU<input name="sku" required /></label><label>Price (GHS)<input name="price" type="number" min="0" step="0.01" required /></label></div><label>Kitchen station<select name="station"><option>MAIN KITCHEN</option><option>GRILL</option><option>PIZZA</option><option>DRINKS</option><option>PASTRY</option></select></label><label>Description<textarea name="description" rows={2} /></label><FormSubmitButton>Add menu item</FormSubmitButton></form></section>
          <section className="ops-form-card"><p className="ops-kicker">Portions & sizes</p><h2>Add priced variant</h2><form action={createMenuVariant} className="ops-form"><label>Menu item<select name="menu_item_id" required defaultValue=""><option value="" disabled>Choose item</option>{(items ?? []).filter((item) => item.is_active).map((item) => <option value={item.id} key={item.id}>{item.name}</option>)}</select></label><label>Variant name<input name="name" required placeholder="Large" /></label><div className="ops-form-row"><label>Price (GHS)<input name="price" type="number" min="0" step="0.01" required /></label><label>Sort order<input name="sort_order" type="number" min="0" step="10" /></label></div><FormSubmitButton>Add variant</FormSubmitButton></form></section>
        </div>
      ) : null}
    </div>
  </>;
}

async function InventoryModule(session: Session) {
  const { supabase, assignment, access } = session;
  const [{ data: categories }, { data: items }, { data: movements }] = await Promise.all([
    supabase.from("inventory_categories").select("*").eq("location_id", assignment.location_id).order("name"),
    supabase.from("inventory_items").select("*, inventory_categories(name)").eq("location_id", assignment.location_id).order("name"),
    supabase.from("stock_movements").select("*, inventory_items(name)").eq("location_id", assignment.location_id).order("posted_at", { ascending: false }).limit(20),
  ]);
  return <>
    <LiveRefresh tables={["inventory_items"]} />
    <PageHead eyebrow="Stock control" title="Inventory" description="Every balance change comes from an immutable movement with a reason—never a silent quantity edit." />
    <section className="ops-metric-grid is-compact"><article className="ops-metric"><span>Active items</span><strong>{items?.filter((item) => item.is_active).length ?? 0}</strong><small>Tracked at this location</small></article><article className="ops-metric"><span>Low stock</span><strong>{items?.filter((item) => Number(item.current_stock) <= Number(item.reorder_level)).length ?? 0}</strong><small>At or below reorder</small></article><article className="ops-metric"><span>Inventory value</span><strong>{formatMoney((items ?? []).reduce((sum, item) => sum + Number(item.current_stock) * Number(item.average_cost_minor), 0))}</strong><small>Estimated average cost</small></article></section>
    <div className="ops-split-layout is-wide-main"><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">On hand</p><h2>Inventory items</h2></div><span>{items?.length ?? 0} items</span></div><div className="ops-table-wrap"><table className="ops-table"><thead><tr><th>Item</th><th>Type</th><th>On hand</th><th>Reorder</th><th>Avg. cost</th><th>Storage</th></tr></thead><tbody>{(items ?? []).map((item) => <tr className={Number(item.current_stock) <= Number(item.reorder_level) ? "is-alert-row" : ""} key={item.id}><td><strong>{item.name}</strong><small>{item.sku} · {item.inventory_categories?.name ?? "Uncategorized"}</small></td><td>{item.item_type.replaceAll("_", " ")}</td><td><strong>{item.current_stock} {item.unit}</strong></td><td>{item.reorder_level} {item.unit}</td><td>{formatMoney(item.average_cost_minor)}</td><td>{item.storage_location ?? "—"}</td></tr>)}</tbody></table>{items?.length ? null : <Empty title="No inventory items yet" body="Create the item master first, then post an opening adjustment or purchase receipt." />}</div><div className="ops-panel-head ops-subhead"><div><p className="ops-kicker">Ledger</p><h2>Recent movements</h2></div></div><div className="ops-list">{(movements ?? []).map((movement) => <div className="ops-list-row" key={movement.id}><div><strong>{movement.inventory_items?.name}</strong><small>{movement.movement_type.replaceAll("_", " ")} · {formatDateTime(movement.posted_at)}</small></div><b className={Number(movement.quantity_delta) < 0 ? "is-negative" : "is-positive"}>{Number(movement.quantity_delta) > 0 ? "+" : ""}{movement.quantity_delta} {movement.unit}</b><em>{movement.reason}</em></div>)}{movements?.length ? null : <Empty title="No stock movements" body="Opening stock, purchases, wastage, and adjustments will be preserved here." />}</div></section>
      <div className="ops-form-stack">{hasPermission(access.permissions, "inventory.manage_items_units") ? <><section className="ops-form-card"><p className="ops-kicker">Item master</p><h2>New inventory item</h2><form action={createInventoryItem} className="ops-form"><label>Category<select name="category_id"><option value="">Uncategorized</option>{(categories ?? []).map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}</select></label><label>Item name<input name="name" required /></label><div className="ops-form-row"><label>SKU<input name="sku" required /></label><label>Unit<select name="unit"><option>kg</option><option>g</option><option>litre</option><option>ml</option><option>piece</option><option>bottle</option><option>carton</option><option>bag</option><option>pack</option></select></label></div><label>Type<select name="item_type"><option>RAW_INGREDIENT</option><option>PACKAGED_PRODUCT</option><option>BEVERAGE</option><option>CONSUMABLE</option><option>CLEANING_SUPPLY</option><option>PACKAGING</option><option>OTHER</option></select></label><div className="ops-form-row"><label>Reorder level<input name="reorder_level" type="number" min="0" step="0.001" defaultValue="0" /></label><label>Target stock<input name="target_stock" type="number" min="0" step="0.001" defaultValue="0" /></label></div><label>Storage location<input name="storage_location" placeholder="Dry store" /></label><FormSubmitButton>Add item</FormSubmitButton></form></section><section className="ops-form-card"><p className="ops-kicker">Classification</p><h2>New category</h2><form action={createInventoryCategory} className="ops-form"><label>Name<input name="name" required /></label><FormSubmitButton>Add category</FormSubmitButton></form></section></> : null}
        {(hasPermission(access.permissions, "inventory.adjust") || hasPermission(access.permissions, "inventory.record_wastage")) ? <section className="ops-form-card"><p className="ops-kicker">Controlled ledger</p><h2>Post stock movement</h2><form action={postStockMovement} className="ops-form"><label>Inventory item<select name="inventory_item_id" required defaultValue=""><option value="" disabled>Choose item</option>{(items ?? []).map((item) => <option value={item.id} key={item.id}>{item.name} · {item.current_stock} {item.unit}</option>)}</select></label><label>Movement type<select name="movement_type"><option>ADJUSTMENT_IN</option><option>ADJUSTMENT_OUT</option><option>WASTAGE</option><option>STAFF_MEAL</option><option>COMPLIMENTARY</option><option>RETURN_TO_SUPPLIER</option></select></label><div className="ops-form-row"><label>Quantity<input name="quantity" type="number" min="0.001" step="0.001" required /></label><label>Unit cost (GHS)<input name="unit_cost" type="number" min="0" step="0.01" /></label></div><label>Reason<textarea name="reason" required minLength={3} rows={2} /></label><FormSubmitButton pendingText="Posting…">Post movement</FormSubmitButton></form></section> : null}</div></div>
  </>;
}

async function RecipesModule(session: Session) {
  const { supabase, assignment, access } = session;
  const [recipesResult, menuResult, inventoryResult] = await Promise.all([
    supabase.from("recipes").select("*, menu_items(name, price_minor), recipe_ingredients(quantity, unit, waste_percentage, inventory_items(name, average_cost_minor))").eq("location_id", assignment.location_id).order("created_at", { ascending: false }),
    supabase.from("menu_items").select("id, name").eq("location_id", assignment.location_id).eq("is_active", true).order("name"),
    supabase.from("inventory_items").select("id, name, unit, average_cost_minor").eq("location_id", assignment.location_id).eq("is_active", true).order("name"),
  ]);
  return <>
    <PageHead eyebrow="Recipe control" title="Recipes & costing" description="Define exact ingredient usage without guessed quantities. Cost follows the live inventory average cost." />
    <div className="ops-split-layout is-wide-main"><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Recipe book</p><h2>Dish recipes</h2></div><span>{recipesResult.data?.length ?? 0} versions</span></div><div className="recipe-list">{(recipesResult.data ?? []).map((recipe) => { const menuItem = Array.isArray(recipe.menu_items) ? recipe.menu_items[0] : recipe.menu_items; const ingredients = (recipe.recipe_ingredients ?? []) as RecipeIngredient[]; const cost = ingredients.reduce((sum: number, ingredient: RecipeIngredient) => { const stock = Array.isArray(ingredient.inventory_items) ? ingredient.inventory_items[0] : ingredient.inventory_items; return sum + Number(ingredient.quantity) * Number(stock?.average_cost_minor ?? 0); }, 0) / Number(recipe.yield_quantity); const price = Number(menuItem?.price_minor ?? 0); return <article key={recipe.id}><header><div><span>Version {recipe.version_number}</span><h3>{recipe.name}</h3><p>{menuItem?.name}</p></div><span className={`ops-pill is-${recipe.status.toLowerCase()}`}>{recipe.status}</span></header><ul>{ingredients.map((ingredient: RecipeIngredient, index: number) => { const stock = Array.isArray(ingredient.inventory_items) ? ingredient.inventory_items[0] : ingredient.inventory_items; return <li key={index}><span>{stock?.name}</span><strong>{ingredient.quantity} {ingredient.unit}</strong></li>; })}</ul><footer><div><span>Estimated portion cost</span><strong>{formatMoney(cost)}</strong></div><div><span>Food cost</span><strong>{price > 0 ? `${((cost / price) * 100).toFixed(1)}%` : "—"}</strong></div>{recipe.status === "DRAFT" && hasPermission(access.permissions, "recipes.publish_version") ? <form action={publishRecipe}><input type="hidden" name="recipe_id" value={recipe.id} /><button type="submit">Publish</button></form> : null}</footer></article>; })}{recipesResult.data?.length ? null : <Empty title="No recipes recorded" body="Choose a menu item and enter its real first ingredient quantity. More ingredients can be versioned as the recipe is finalized." />}</div></section>
      {hasPermission(access.permissions, "recipes.create_draft") ? <section className="ops-form-card"><p className="ops-kicker">Draft formulation</p><h2>Create recipe</h2><form action={createRecipe} className="ops-form"><label>Menu item<select name="menu_item_id" required defaultValue=""><option value="" disabled>Choose dish</option>{(menuResult.data ?? []).map((item) => <option value={item.id} key={item.id}>{item.name}</option>)}</select></label><label>Recipe name<input name="name" required /></label><label>First ingredient<select name="inventory_item_id" required defaultValue=""><option value="" disabled>Choose inventory item</option>{(inventoryResult.data ?? []).map((item) => <option value={item.id} key={item.id}>{item.name} · {item.unit}</option>)}</select></label><div className="ops-form-row"><label>Ingredient quantity<input name="ingredient_quantity" type="number" min="0.001" step="0.001" required /></label><label>Recipe yield<input name="yield_quantity" type="number" min="0.001" step="0.001" defaultValue="1" required /></label></div><p className="ops-form-note">Enter only the approved kitchen quantity. The system does not invent recipe values.</p><FormSubmitButton>Create draft</FormSubmitButton></form></section> : null}</div>
  </>;
}

async function PurchasingModule(session: Session) {
  const { supabase, assignment, access } = session;
  const [ordersResult, suppliersResult, itemsResult] = await Promise.all([
    supabase.from("purchase_orders").select("*, suppliers(name), purchase_order_lines(item_name, quantity, unit, unit_cost_minor, received_quantity)").eq("location_id", assignment.location_id).order("created_at", { ascending: false }).limit(50),
    supabase.from("suppliers").select("id, name").eq("location_id", assignment.location_id).eq("is_active", true).order("name"),
    supabase.from("inventory_items").select("id, name, unit").eq("location_id", assignment.location_id).eq("is_active", true).order("name"),
  ]);
  return <>
    <PageHead eyebrow="Procure to stock" title="Purchasing" description="Issue accountable purchase orders and receive accepted goods as immutable stock movements." />
    <div className="ops-split-layout is-wide-main"><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Purchase history</p><h2>Purchase orders</h2></div><span>{ordersResult.data?.length ?? 0} orders</span></div><div className="ops-card-list">{(ordersResult.data ?? []).map((order) => { const supplier = Array.isArray(order.suppliers) ? order.suppliers[0] : order.suppliers; const lines = (order.purchase_order_lines ?? []) as PurchaseLine[]; return <article className="purchase-row" key={order.id}><div><span>{order.po_number} · {formatDateTime(order.created_at)}</span><h3>{supplier?.name}</h3><p>{lines.map((line: PurchaseLine) => `${line.quantity} ${line.unit} ${line.item_name}`).join(", ")}</p></div><strong>{formatMoney(order.total_minor, order.currency_code)}</strong><span className={`ops-pill is-${order.status.toLowerCase()}`}>{order.status}</span>{order.status === "ORDERED" && hasPermission(access.permissions, "goods_receipts.record") ? <form action={receivePurchaseOrder}><input type="hidden" name="purchase_order_id" value={order.id} /><button type="submit">Receive goods</button></form> : null}</article>; })}{ordersResult.data?.length ? null : <Empty title="No purchase orders" body="Create the first order after inventory items and a supplier are available." />}</div></section>
      {hasPermission(access.permissions, "purchase_orders.create_issue") ? <section className="ops-form-card"><p className="ops-kicker">New commitment</p><h2>Issue purchase order</h2><form action={createPurchaseOrder} className="ops-form"><label>Supplier<select name="supplier_id" required defaultValue=""><option value="" disabled>Choose supplier</option>{(suppliersResult.data ?? []).map((supplier) => <option value={supplier.id} key={supplier.id}>{supplier.name}</option>)}</select></label><label>Inventory item<select name="inventory_item_id" required defaultValue=""><option value="" disabled>Choose item</option>{(itemsResult.data ?? []).map((item) => <option value={item.id} key={item.id}>{item.name} · {item.unit}</option>)}</select></label><div className="ops-form-row"><label>Quantity<input name="quantity" type="number" min="0.001" step="0.001" required /></label><label>Unit cost (GHS)<input name="unit_cost" type="number" min="0" step="0.01" required /></label></div><label>Expected delivery<input name="expected_delivery" type="date" /></label><label>Notes<textarea name="notes" rows={2} /></label><FormSubmitButton pendingText="Issuing…">Issue purchase order</FormSubmitButton></form></section> : null}</div>
  </>;
}

async function SuppliersModule(session: Session) {
  const { supabase, assignment, access } = session;
  const { data: suppliers } = await supabase.from("suppliers").select("*").eq("location_id", assignment.location_id).order("name");
  return <>
    <PageHead eyebrow="Supply network" title="Suppliers" description="Keep commercial contacts and terms attached to the purchasing history they support." />
    <div className="ops-split-layout is-wide-main"><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Supplier directory</p><h2>Active suppliers</h2></div><span>{suppliers?.filter((supplier) => supplier.is_active).length ?? 0} active</span></div><div className="supplier-grid">{(suppliers ?? []).map((supplier) => <article key={supplier.id}><span>{supplier.code}</span><h3>{supplier.name}</h3><p>{supplier.contact_person || "No contact person"}</p><dl><div><dt>Phone</dt><dd>{supplier.phone || "—"}</dd></div><div><dt>Email</dt><dd>{supplier.email || "—"}</dd></div><div><dt>Terms</dt><dd>{supplier.payment_terms || "—"}</dd></div></dl></article>)}{suppliers?.length ? null : <Empty title="No suppliers recorded" body="Add the first approved supplier before creating a purchase order." />}</div></section>
      {hasPermission(access.permissions, "suppliers.manage") ? <section className="ops-form-card"><p className="ops-kicker">Supplier master</p><h2>Add supplier</h2><form action={createSupplier} className="ops-form"><div className="ops-form-row"><label>Code<input name="code" required /></label><label>Supplier name<input name="name" required /></label></div><label>Contact person<input name="contact_person" /></label><div className="ops-form-row"><label>Phone<input name="phone" type="tel" /></label><label>Email<input name="email" type="email" /></label></div><label>Payment terms<input name="payment_terms" placeholder="e.g. 30 days" /></label><label>Notes<textarea name="notes" rows={3} /></label><FormSubmitButton>Add supplier</FormSubmitButton></form></section> : null}</div>
  </>;
}

async function CustomersModule(session: Session) {
  const { supabase, assignment, access } = session;
  const { data: customers } = await supabase.from("customers").select("*, orders(id, total_minor, created_at)").eq("location_id", assignment.location_id).order("created_at", { ascending: false }).limit(100);
  return <>
    <PageHead eyebrow="Guest relationships" title="Customers" description="Useful guest details, consent, and genuine order history—without unnecessary personal data." />
    <div className="ops-split-layout is-wide-main"><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Customer directory</p><h2>Guest profiles</h2></div><span>{customers?.length ?? 0} customers</span></div><div className="ops-table-wrap"><table className="ops-table"><thead><tr><th>Customer</th><th>Contact</th><th>Orders</th><th>Total spend</th><th>Last order</th><th>Consent</th></tr></thead><tbody>{(customers ?? []).map((customer) => { const orders = (customer.orders ?? []) as CustomerOrder[]; const mostRecentOrder = orders.toSorted((a: CustomerOrder, b: CustomerOrder) => b.created_at.localeCompare(a.created_at))[0]; return <tr key={customer.id}><td><strong>{customer.display_name}</strong><small>{customer.notes || "No notes"}</small></td><td>{customer.phone || "—"}<small>{customer.email || ""}</small></td><td>{orders.length}</td><td>{formatMoney(orders.reduce((sum: number, order: CustomerOrder) => sum + Number(order.total_minor), 0))}</td><td>{mostRecentOrder ? formatDateTime(mostRecentOrder.created_at) : "—"}</td><td>{customer.marketing_consent ? "Granted" : "Not granted"}</td></tr>; })}</tbody></table>{customers?.length ? null : <Empty title="No customer profiles" body="Create a profile from a phone, WhatsApp, reservation, or returning guest interaction." />}</div></section>
      {hasPermission(access.permissions, "customers.create_update_basic") ? <section className="ops-form-card"><p className="ops-kicker">New guest</p><h2>Create customer</h2><form action={createCustomer} className="ops-form"><label>Display name<input name="display_name" required /></label><div className="ops-form-row"><label>Phone<input name="phone" type="tel" /></label><label>Email<input name="email" type="email" /></label></div><label>Notes<textarea name="notes" rows={3} /></label><label className="ops-check"><input name="marketing_consent" type="checkbox" /> Customer explicitly agreed to marketing</label><FormSubmitButton>Create customer</FormSubmitButton></form></section> : null}</div>
  </>;
}

async function ReservationsModule(session: Session) {
  const { supabase, assignment, access } = session;
  const [reservationsResult, tablesResult, customersResult] = await Promise.all([
    supabase.from("reservations").select("*, restaurant_tables(code)").eq("location_id", assignment.location_id).order("starts_at").limit(100),
    supabase.from("restaurant_tables").select("id, code, capacity, status").eq("location_id", assignment.location_id).eq("is_active", true).order("code"),
    supabase.from("customers").select("id, display_name").eq("location_id", assignment.location_id).eq("is_active", true).order("display_name"),
  ]);
  return <>
    <LiveRefresh tables={["restaurant_tables"]} />
    <PageHead eyebrow="Bookings" title="Reservations" description="Confirm bookings, assign tables without double-booking, and follow every guest through arrival or no-show." />
    <div className="ops-split-layout is-wide-main"><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Reservation book</p><h2>Upcoming & recent</h2></div><span>{reservationsResult.data?.length ?? 0} bookings</span></div><div className="reservation-list">{(reservationsResult.data ?? []).map((reservation) => <article key={reservation.id}><div className="reservation-time"><strong>{new Intl.DateTimeFormat("en-GH", { timeZone: "Africa/Accra", month: "short", day: "2-digit" }).format(new Date(reservation.starts_at))}</strong><span>{new Intl.DateTimeFormat("en-GH", { timeZone: "Africa/Accra", hour: "2-digit", minute: "2-digit" }).format(new Date(reservation.starts_at))}</span></div><div><h3>{reservation.guest_name}</h3><p>{reservation.party_size} guests · {reservation.restaurant_tables?.code ? `Table ${reservation.restaurant_tables.code}` : "Table unassigned"} · {reservation.guest_phone}</p></div><span className={`ops-pill is-${reservation.status.toLowerCase()}`}>{reservation.status}</span>{hasPermission(access.permissions, "reservations.create_update") ? <form action={updateReservationStatus}><input type="hidden" name="reservation_id" value={reservation.id} /><select name="status" defaultValue={reservation.status}><option>REQUESTED</option><option>CONFIRMED</option><option>SEATED</option><option>COMPLETED</option><option>CANCELLED</option><option>NO_SHOW</option></select><button type="submit">Update</button></form> : null}</article>)}{reservationsResult.data?.length ? null : <Empty title="No reservations" body="Bookings created here will be protected against overlapping use of the same table." />}</div></section>
      {hasPermission(access.permissions, "reservations.create_update") ? <section className="ops-form-card"><p className="ops-kicker">New booking</p><h2>Create reservation</h2><form action={createReservation} className="ops-form"><label>Guest name<input name="guest_name" required /></label><label>Phone<input name="guest_phone" type="tel" required /></label><label>Existing customer<select name="customer_id"><option value="">No linked profile</option>{(customersResult.data ?? []).map((customer) => <option value={customer.id} key={customer.id}>{customer.display_name}</option>)}</select></label><div className="ops-form-row"><label>Date & time<input name="starts_at" type="datetime-local" required /></label><label>Duration (minutes)<input name="duration" type="number" min="30" step="30" defaultValue="120" /></label></div><div className="ops-form-row"><label>Party size<input name="party_size" type="number" min="1" max="50" defaultValue="2" required /></label><label>Table<select name="table_id"><option value="">Assign later</option>{(tablesResult.data ?? []).map((table) => <option value={table.id} key={table.id}>{table.code} · {table.capacity} seats</option>)}</select></label></div><label>Source<select name="source"><option>PHONE</option><option>WHATSAPP</option><option>WEBSITE</option><option>WALK_IN</option><option>STAFF</option></select></label><label>Occasion<input name="occasion" /></label><label>Notes<textarea name="notes" rows={2} /></label><FormSubmitButton>Create reservation</FormSubmitButton></form></section> : null}</div>
  </>;
}

async function StaffModule(session: Session) {
  const { supabase, assignment, access } = session;
  const [employmentResult, assignmentsResult, shiftsResult] = await Promise.all([
    supabase.from("staff_employments").select("id, profile_id, employee_number, start_date, end_date, is_active, profiles(display_name, phone, email)").eq("organization_id", assignment.organization_id).order("created_at"),
    supabase.from("user_role_assignments").select("profile_id, revoked_at, roles(code, name)").eq("organization_id", assignment.organization_id).is("revoked_at", null),
    supabase.from("staff_shifts").select("*, staff_employments(employee_number, profiles(display_name))").eq("location_id", assignment.location_id).order("starts_at", { ascending: false }).limit(50),
  ]);
  return <>
    <PageHead eyebrow="People & access" title="Staff" description="Operational employment, role assignments, and shifts. Payroll is intentionally outside this system." />
    <div className="ops-split-layout is-wide-main">
      <section className="ops-panel">
        <div className="ops-panel-head"><div><p className="ops-kicker">Team directory</p><h2>Staff access</h2></div><span>{employmentResult.data?.filter((row) => row.is_active).length ?? 0} active</span></div>
        <div className="staff-grid">
          {(employmentResult.data ?? []).map((employment) => {
            const profile = Array.isArray(employment.profiles) ? employment.profiles[0] : employment.profiles;
            const roleAssignment = (assignmentsResult.data ?? []).find((row) => row.profile_id === employment.profile_id);
            const role = Array.isArray(roleAssignment?.roles) ? roleAssignment.roles[0] : roleAssignment?.roles;
            const canManage = hasPermission(access.permissions, "security.manage_users_roles");
            return (
              <details className={`staff-card${employment.is_active ? "" : " is-archived"}`} key={employment.id}>
                <summary>
                  <span className="ops-avatar">{profile?.display_name?.split(" ").map((part: string) => part[0]).slice(0,2).join("")}</span>
                  <span className="staff-card-name"><h3>{profile?.display_name}</h3><strong>{employment.is_active ? (role?.name ?? "No active role") : "Archived"}</strong></span>
                </summary>
                <div className="staff-card-body">
                  {employment.is_active && canManage ? null : <p>{profile?.email || "No email on file"}</p>}
                  <p>{employment.employee_number} · Started {employment.start_date}{employment.is_active ? "" : ` · Archived ${employment.end_date}`}</p>
                  {employment.is_active && canManage ? (
                    <form action={updateStaffMember} className="ops-form">
                      <input type="hidden" name="profile_id" value={employment.profile_id} />
                      <label>Full name<input name="display_name" defaultValue={profile?.display_name ?? ""} required /></label>
                      <label>Email<input name="email" type="email" defaultValue={profile?.email ?? ""} required /></label>
                      <div className="ops-form-row">
                        <label>Phone<input name="phone" defaultValue={profile?.phone ?? ""} /></label>
                        <label>Employee number<input name="employee_number" defaultValue={employment.employee_number} required /></label>
                      </div>
                      <FormSubmitButton>Save changes</FormSubmitButton>
                    </form>
                  ) : (
                    <p className="ops-form-note">{profile?.phone ? `Phone: ${profile.phone}` : "No phone on file"}</p>
                  )}
                  {employment.is_active && canManage ? (
                    <div className="staff-actions">
                      <form action={changeStaffRole}><input type="hidden" name="profile_id" value={employment.profile_id} /><select name="role_code" defaultValue={role?.code ?? "RECEPTIONIST"}><option>RECEPTIONIST</option><option>MANAGER</option><option>OWNER</option><option>DELIVERY_RIDER</option></select><button type="submit">Change role</button></form>
                      <form action={archiveStaffMember}><input type="hidden" name="profile_id" value={employment.profile_id} /><input type="hidden" name="reason" value="Archived from Staff page" /><button className="is-danger" type="submit">Archive</button></form>
                    </div>
                  ) : null}
                </div>
              </details>
            );
          })}
          {employmentResult.data?.length ? null : <Empty title="No staff yet" body="Add the first team member using the form." />}
        </div>
      </section>
      {hasPermission(access.permissions, "security.manage_users_roles") ? <section className="ops-form-card"><p className="ops-kicker">Onboarding</p><h2>Add staff member</h2><form action={inviteStaffMember} className="ops-form"><label>Full name<input name="display_name" required /></label><div className="ops-form-row"><label>Email<input name="email" type="email" required /></label><label>Phone<input name="phone" /></label></div><div className="ops-form-row"><label>Employee number<input name="employee_number" required /></label><label>Role<select name="role_code" defaultValue="RECEPTIONIST"><option>RECEPTIONIST</option><option>MANAGER</option><option>OWNER</option><option>DELIVERY_RIDER</option></select></label></div><label>Temporary password<input name="password" type="text" minLength={8} required placeholder="At least 8 characters" /></label><p className="ops-form-note">Share this email and temporary password with the new staff member so they can sign in.</p><FormSubmitButton>Add staff member</FormSubmitButton></form></section> : null}
    </div>
    <div className="ops-split-layout ops-section-gap"><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Schedule</p><h2>Recent shifts</h2></div></div><div className="ops-list">{(shiftsResult.data ?? []).map((shift) => { const employment = Array.isArray(shift.staff_employments) ? shift.staff_employments[0] : shift.staff_employments; const profile = Array.isArray(employment?.profiles) ? employment.profiles[0] : employment?.profiles; return <div className="ops-list-row" key={shift.id}><div><strong>{profile?.display_name}</strong><small>{formatDateTime(shift.starts_at)} → {formatDateTime(shift.ends_at)}</small></div><em>{shift.status}</em></div>; })}{shiftsResult.data?.length ? null : <Empty title="No shifts scheduled" body="Schedule the first operational shift for an active staff member." />}</div></section>
      {hasPermission(access.permissions, "staff.manage_shifts_attendance") ? <section className="ops-form-card"><p className="ops-kicker">Schedule</p><h2>Add shift</h2><form action={createStaffShift} className="ops-form"><label>Staff member<select name="employment_id" required>{(employmentResult.data ?? []).filter((employment) => employment.is_active).map((employment) => { const profile = Array.isArray(employment.profiles) ? employment.profiles[0] : employment.profiles; return <option value={employment.id} key={employment.id}>{profile?.display_name} · {employment.employee_number}</option>; })}</select></label><label>Starts<input name="starts_at" type="datetime-local" required /></label><label>Ends<input name="ends_at" type="datetime-local" required /></label><label>Notes<textarea name="notes" rows={2} /></label><FormSubmitButton>Schedule shift</FormSubmitButton></form></section> : null}</div>
  </>;
}

async function FinanceModule(session: Session) {
  const { supabase, assignment, access } = session;
  const today = businessDate();
  const [paymentsResult, expensesResult, closesResult] = await Promise.all([
    supabase.from("payments").select("*, orders(order_number)").eq("location_id", assignment.location_id).order("received_at", { ascending: false }).limit(50),
    supabase.from("expenses").select("*").eq("location_id", assignment.location_id).order("incurred_on", { ascending: false }).limit(50),
    supabase.from("daily_closes").select("*").eq("location_id", assignment.location_id).order("business_date", { ascending: false }).limit(30),
  ]);
  const paymentsToday = (paymentsResult.data ?? []).filter((payment) => new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Accra" }).format(new Date(payment.received_at)) === today);
  const totalToday = paymentsToday.reduce((sum, payment) => sum + Number(payment.amount_minor), 0);
  const expensesToday = (expensesResult.data ?? []).filter((expense) => expense.incurred_on === today).reduce((sum, expense) => sum + Number(expense.amount_minor), 0);
  return <>
    <PageHead eyebrow="Transaction-driven finance" title="Finance" description="Revenue comes from successful payments; expenses and daily close reconcile against those source transactions." />
    <section className="ops-metric-grid is-compact"><article className="ops-metric is-featured"><span>Collected today</span><strong>{formatMoney(totalToday)}</strong><small>{paymentsToday.length} payments</small></article><article className="ops-metric"><span>Expenses today</span><strong>{formatMoney(expensesToday)}</strong><small>Posted operating costs</small></article><article className="ops-metric"><span>Net cashflow signal</span><strong>{formatMoney(totalToday - expensesToday)}</strong><small>Before inventory liabilities</small></article></section>
    <div className="ops-dashboard-columns"><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Settlements</p><h2>Recent payments</h2></div></div><div className="ops-list">{(paymentsResult.data ?? []).map((payment) => { const order = Array.isArray(payment.orders) ? payment.orders[0] : payment.orders; return <div className="ops-list-row" key={payment.id}><div><strong>{order?.order_number}</strong><small>{payment.payment_method} · {formatDateTime(payment.received_at)}</small></div><b>{formatMoney(payment.amount_minor, payment.currency_code)}</b><em>{payment.status}</em></div>; })}{paymentsResult.data?.length ? null : <Empty title="No payments recorded" body="Successful order payments will appear here automatically." />}</div></section><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Operating costs</p><h2>Recent expenses</h2></div></div><div className="ops-list">{(expensesResult.data ?? []).map((expense) => <div className="ops-list-row" key={expense.id}><div><strong>{expense.category}</strong><small>{expense.vendor || "No vendor"} · {expense.incurred_on}</small></div><b>{formatMoney(expense.amount_minor, expense.currency_code)}</b><em>{expense.status}</em></div>)}{expensesResult.data?.length ? null : <Empty title="No expenses recorded" body="Posted operating expenses will remain visible here." />}</div></section></div>
    <div className="ops-split-layout ops-section-gap">{hasPermission(access.permissions, "expenses.create") ? <section className="ops-form-card"><p className="ops-kicker">Operational expense</p><h2>Record expense</h2><form action={createExpense} className="ops-form"><div className="ops-form-row"><label>Category<input name="category" required placeholder="Utilities" /></label><label>Amount (GHS)<input name="amount" type="number" min="0.01" step="0.01" required /></label></div><div className="ops-form-row"><label>Payment method<select name="payment_method"><option>CASH</option><option>MOMO</option><option>CARD</option><option>ONLINE</option></select></label><label>Date<input name="incurred_on" type="date" defaultValue={today} required /></label></div><label>Vendor<input name="vendor" /></label><label>Description<textarea name="description" rows={2} required /></label><FormSubmitButton>Record expense</FormSubmitButton></form></section> : null}<section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Reconciliation</p><h2>Daily close</h2></div>{hasPermission(access.permissions, "daily_close.prepare") ? <form action={prepareDailyClose} className="ops-inline-form"><input name="business_date" type="date" defaultValue={today} /><button type="submit">Refresh close</button></form> : null}</div><div className="ops-list">{(closesResult.data ?? []).map((close) => <div className="ops-list-row" key={close.id}><div><strong>{close.business_date}</strong><small>{close.orders_count} orders · {formatMoney(close.expenses_minor)} expenses</small></div><b>{formatMoney(close.net_sales_minor)}</b><em>{close.status}</em></div>)}{closesResult.data?.length ? null : <Empty title="No daily close prepared" body="Refresh today’s close to derive payment and expense totals from source transactions." />}</div></section></div>
  </>;
}

async function ReportsModule(session: Session, query: Query) {
  const { supabase, assignment } = session;
  const to = query.to && /^\d{4}-\d{2}-\d{2}$/.test(query.to) ? query.to : businessDate();
  const defaultFrom = new Date(`${to}T00:00:00Z`); defaultFrom.setUTCDate(defaultFrom.getUTCDate() - 29);
  const from = query.from && /^\d{4}-\d{2}-\d{2}$/.test(query.from) ? query.from : businessDate(defaultFrom);
  const { data } = await supabase.rpc("get_report_summary", { p_organization_id: assignment.organization_id, p_location_id: assignment.location_id, p_from_date: from, p_to_date: to });
  const report = (data && typeof data === "object" ? data : {}) as { orders?: number; gross_sales_minor?: number; payments_minor?: number; expenses_minor?: number; sales_by_channel?: Array<{ channel: string; orders: number; sales_minor: number }>; payments_by_method?: Array<{ method: string; amount_minor: number }>; top_items?: Array<{ name: string; quantity: number; sales_minor: number }> };
  return <>
    <PageHead eyebrow="Live operational facts" title="Reports" description="Every number is calculated from restaurant transactions in the selected date range—no fake analytics." action={<form className="ops-date-filter" method="get"><label>From<input name="from" type="date" defaultValue={from} /></label><label>To<input name="to" type="date" defaultValue={to} /></label><button type="submit">Run report</button></form>} />
    <section className="ops-metric-grid is-compact"><article className="ops-metric"><span>Orders</span><strong>{report.orders ?? 0}</strong><small>{from} to {to}</small></article><article className="ops-metric"><span>Gross sales</span><strong>{formatMoney(report.gross_sales_minor)}</strong><small>Excludes cancelled and voided</small></article><article className="ops-metric is-featured"><span>Successful payments</span><strong>{formatMoney(report.payments_minor)}</strong><small>Collected revenue</small></article><article className="ops-metric"><span>Posted expenses</span><strong>{formatMoney(report.expenses_minor)}</strong><small>Operational costs</small></article></section>
    <div className="ops-report-grid"><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Sales mix</p><h2>By channel</h2></div></div><div className="report-bars">{(report.sales_by_channel ?? []).map((row) => <div key={row.channel}><span>{row.channel.replaceAll("_", " ")}<small>{row.orders} orders</small></span><strong>{formatMoney(row.sales_minor)}</strong></div>)}{report.sales_by_channel?.length ? null : <Empty title="No channel data" body="Sales by channel will populate when orders exist in this period." />}</div></section><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Settlement mix</p><h2>By payment method</h2></div></div><div className="report-bars">{(report.payments_by_method ?? []).map((row) => <div key={row.method}><span>{row.method}</span><strong>{formatMoney(row.amount_minor)}</strong></div>)}{report.payments_by_method?.length ? null : <Empty title="No payment data" body="Successful payments will populate this report." />}</div></section><section className="ops-panel"><div className="ops-panel-head"><div><p className="ops-kicker">Menu performance</p><h2>Top items</h2></div></div><div className="report-bars">{(report.top_items ?? []).map((row, index) => <div key={row.name}><span><b>{String(index + 1).padStart(2, "0")}</b>{row.name}<small>{row.quantity} sold</small></span><strong>{formatMoney(row.sales_minor)}</strong></div>)}{report.top_items?.length ? null : <Empty title="No item sales" body="Top items will appear once orders are recorded in this period." />}</div></section></div>
  </>;
}

async function SettingsModule(session: Session) {
  const { supabase, assignment, access } = session;
  const [organizationResult, locationResult, settingsResult, auditResult] = await Promise.all([
    supabase.from("organizations").select("*").eq("id", assignment.organization_id).single(),
    supabase.from("locations").select("*").eq("id", assignment.location_id).single(),
    supabase.from("operational_settings").select("*").eq("location_id", assignment.location_id).order("setting_key"),
    supabase.from("audit_events").select("id, action, entity_type, entity_id, actor_role_codes, reason, occurred_at").eq("location_id", assignment.location_id).order("occurred_at", { ascending: false }).limit(50),
  ]);
  const organization = organizationResult.data;
  const location = locationResult.data;
  return <>
    <PageHead eyebrow="Restaurant administration" title="Settings" description="Control the live restaurant profile and preserve an accountable record of sensitive changes." />
    <div className="ops-split-layout">{hasPermission(access.permissions, "settings.manage_location") ? <section className="ops-form-card"><p className="ops-kicker">Restaurant profile</p><h2>Business & location</h2><form action={updateRestaurantProfile} className="ops-form"><label>Business name<input name="trading_name" defaultValue={organization?.trading_name ?? "Adee's Food"} required /></label><label>Location name<input name="location_name" defaultValue={location?.name ?? "Main Branch"} required /></label><div className="ops-form-row"><label>Currency<input name="currency_code" defaultValue={organization?.default_currency_code ?? "GHS"} maxLength={3} required /></label><label>Timezone<input name="timezone" defaultValue={location?.timezone ?? "Africa/Accra"} required /></label></div><div className="ops-form-row"><label>Phone<input name="phone" defaultValue={location?.phone ?? ""} /></label><label>Email<input name="email" type="email" defaultValue={location?.email ?? ""} /></label></div><label>Address<input name="address" defaultValue={location?.address_line_1 ?? ""} /></label><FormSubmitButton>Save restaurant profile</FormSubmitButton></form></section> : null}{hasPermission(access.permissions, "settings.manage_financial_security") ? <section className="ops-form-card"><p className="ops-kicker">Controlled preferences</p><h2>Operational setting</h2><form action={saveOperationalSetting} className="ops-form"><label>Setting key<select name="setting_key"><option value="orders.discount_limit_percent">Discount limit (%)</option><option value="inventory.low_stock_alerts">Low-stock alerts</option><option value="finance.service_charge_percent">Service charge (%)</option><option value="reservations.default_duration_minutes">Reservation duration (minutes)</option><option value="operations.dine_in_enabled">Dine-in enabled (true/false)</option><option value="kitchen.target_minutes">Kitchen target (minutes)</option></select></label><label>Value<input name="setting_value" required /></label><label>Description<textarea name="description" rows={2} /></label><FormSubmitButton>Save setting</FormSubmitButton></form><div className="setting-list">{(settingsResult.data ?? []).map((setting) => <div key={setting.id}><strong>{setting.setting_key}</strong><span>{String(setting.setting_value?.value ?? "")}</span></div>)}</div></section> : null}</div>
    <section className="ops-panel ops-section-gap"><div className="ops-panel-head"><div><p className="ops-kicker">Security evidence</p><h2>Audit log</h2></div><span>{auditResult.data?.length ?? 0} recent events</span></div>{hasPermission(access.permissions, "audit.view_location") || hasPermission(access.permissions, "audit.view_all") ? <div className="ops-table-wrap"><table className="ops-table"><thead><tr><th>When</th><th>Action</th><th>Entity</th><th>Role</th><th>Reason</th></tr></thead><tbody>{(auditResult.data ?? []).map((event) => <tr key={event.id}><td>{formatDateTime(event.occurred_at)}</td><td><strong>{event.action}</strong></td><td>{event.entity_type}<small>{event.entity_id}</small></td><td>{event.actor_role_codes?.join(", ") || "System"}</td><td>{event.reason || "—"}</td></tr>)}</tbody></table>{auditResult.data?.length ? null : <Empty title="No audit events visible" body="Sensitive changes will be recorded here with actor, entity, and timestamp." />}</div> : <Empty title="Audit log restricted" body="Your role can manage permitted location settings but cannot inspect audit evidence." />}</section>
  </>;
}
