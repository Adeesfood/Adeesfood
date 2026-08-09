import Link from "next/link";
import { LiveRefresh } from "@/components/management/LiveRefresh";
import { canAccessModule, managementModules } from "@/lib/access";
import { businessDate, formatDateTime, formatMoney, getManagementSession } from "@/lib/management";

type DashboardMetrics = {
  sales_minor: number;
  orders_today: number;
  active_orders: number;
  preparing_orders: number;
  ready_orders: number;
  reservations_today: number;
  occupied_tables: number;
  available_tables: number;
  low_stock_items: number;
  expenses_minor: number;
};

const emptyMetrics: DashboardMetrics = {
  sales_minor: 0,
  orders_today: 0,
  active_orders: 0,
  preparing_orders: 0,
  ready_orders: 0,
  reservations_today: 0,
  occupied_tables: 0,
  available_tables: 0,
  low_stock_items: 0,
  expenses_minor: 0,
};

export default async function DashboardPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { supabase, access, assignment, displayName } = await getManagementSession();
  const query = await searchParams;
  const today = businessDate();
  const [{ data: metricData }, { data: recentOrders }, { data: kitchenTickets }] = await Promise.all([
    supabase.rpc("get_dashboard_metrics", {
      p_organization_id: assignment.organization_id,
      p_location_id: assignment.location_id,
      p_business_date: today,
    }),
    supabase.from("orders").select("id, order_number, channel, total_minor, order_status, created_at")
      .eq("location_id", assignment.location_id).order("created_at", { ascending: false }).limit(5),
    supabase.from("kitchen_tickets").select("id, ticket_number, status, queued_at")
      .eq("location_id", assignment.location_id).in("status", ["QUEUED", "PREPARING", "READY"])
      .order("queued_at", { ascending: true }).limit(4),
  ]);
  const metrics = metricData && typeof metricData === "object" ? { ...emptyMetrics, ...(metricData as Partial<DashboardMetrics>) } : emptyMetrics;
  const firstName = displayName.split(" ")[0];
  const moduleLinks = managementModules.filter((module) => module.slug && canAccessModule(access.permissions, module));

  return (
    <>
      <LiveRefresh tables={["orders", "kitchen_tickets", "restaurant_tables", "inventory_items"]} />
      <section className="ops-page-head">
        <div><p className="ops-kicker">Dashboard · {today}</p><h1>Good to see you, {firstName}.</h1><p>Here is what is happening across today&apos;s service.</p></div>
        <Link className="ops-head-action" href="/management/orders">Create order <span>＋</span></Link>
      </section>
      {query.error ? <div className="ops-alert is-error">Your current role cannot open that module.</div> : null}

      <section className="ops-metric-grid" aria-label="Today at a glance">
        <article className="ops-metric is-featured"><span>Sales today</span><strong>{formatMoney(metrics.sales_minor)}</strong><small>Successful payments</small></article>
        <article className="ops-metric"><span>Orders today</span><strong>{metrics.orders_today}</strong><small>{metrics.active_orders} active now</small></article>
        <article className="ops-metric"><span>Kitchen</span><strong>{metrics.preparing_orders}</strong><small>{metrics.ready_orders} ready for handoff</small></article>
        <article className="ops-metric"><span>Reservations</span><strong>{metrics.reservations_today}</strong><small>Expected today</small></article>
        <article className="ops-metric"><span>Tables</span><strong>{metrics.occupied_tables}</strong><small>{metrics.available_tables} available</small></article>
        <article className={`ops-metric${metrics.low_stock_items > 0 ? " is-warning" : ""}`}><span>Stock alerts</span><strong>{metrics.low_stock_items}</strong><small>At or below reorder level</small></article>
      </section>

      <div className="ops-dashboard-columns">
        <section className="ops-panel">
          <div className="ops-panel-head"><div><p className="ops-kicker">Live service</p><h2>Recent orders</h2></div><Link href="/management/orders">View all</Link></div>
          <div className="ops-list">
            {(recentOrders ?? []).length ? (recentOrders ?? []).map((order) => (
              <Link className="ops-list-row" href="/management/orders" key={order.id}>
                <span className="ops-status-dot" /><div><strong>{order.order_number}</strong><small>{order.channel.replaceAll("_", " ")} · {formatDateTime(order.created_at)}</small></div>
                <b>{formatMoney(order.total_minor)}</b><em>{order.order_status.replaceAll("_", " ")}</em>
              </Link>
            )) : <div className="ops-empty"><strong>No orders yet today</strong><p>Create the first order when service begins.</p></div>}
          </div>
        </section>

        <section className="ops-panel">
          <div className="ops-panel-head"><div><p className="ops-kicker">Kitchen pulse</p><h2>Active tickets</h2></div><Link href="/management/kitchen">Open KDS</Link></div>
          <div className="ops-list">
            {(kitchenTickets ?? []).length ? (kitchenTickets ?? []).map((ticket) => (
              <Link className="ops-list-row is-compact" href="/management/kitchen" key={ticket.id}>
                <div><strong>{ticket.ticket_number}</strong><small>Queued {formatDateTime(ticket.queued_at)}</small></div><em>{ticket.status}</em>
              </Link>
            )) : <div className="ops-empty"><strong>Kitchen is clear</strong><p>New tickets will appear here automatically.</p></div>}
          </div>
        </section>
      </div>

      <section className="ops-module-launcher">
        <div className="ops-panel-head"><div><p className="ops-kicker">Your workspace</p><h2>Management modules</h2></div><span>{assignment.role_name} access</span></div>
        <div className="ops-launch-grid">
          {moduleLinks.map((module) => (
            <Link href={`/management/${module.slug}`} key={module.slug}><span>{module.marker}</span><h3>{module.name}</h3><p>{module.description}</p><i aria-hidden="true">↗</i></Link>
          ))}
        </div>
      </section>
    </>
  );
}
