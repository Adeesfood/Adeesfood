import { formatDateTime, formatMoney } from "@/lib/management";
import { getRiderSession } from "@/lib/rider";

export default async function RiderHistoryPage() {
  const { supabase, assignment } = await getRiderSession();

  const { data: deliveries } = await supabase
    .from("deliveries")
    .select(
      "id, delivery_status, delivered_at, failed_at, failure_reason, amount_due_minor, currency_code, order:orders(order_number)",
    )
    .eq("organization_id", assignment.organization_id)
    .in("delivery_status", ["DELIVERED", "FAILED", "RETURNED", "CANCELLED"])
    .order("updated_at", { ascending: false })
    .limit(50);

  return (
    <div>
      <h1 className="rider-section-title">Delivery history</h1>

      {!deliveries?.length ? (
        <p className="rider-empty">Completed deliveries will show up here.</p>
      ) : (
        deliveries.map((delivery) => {
          const order = Array.isArray(delivery.order) ? delivery.order[0] : delivery.order;
          return (
            <article className="rider-card" key={delivery.id}>
              <div className="rider-card-head">
                <strong>#{order?.order_number ?? "—"}</strong>
                <span className="rider-card-status">{delivery.delivery_status.replace(/_/g, " ")}</span>
              </div>
              <p>{formatDateTime(delivery.delivered_at ?? delivery.failed_at)}</p>
              {delivery.failure_reason ? <p>Reason: {delivery.failure_reason}</p> : null}
              {delivery.amount_due_minor > 0 ? (
                <p>Collected {formatMoney(delivery.amount_due_minor, delivery.currency_code)}</p>
              ) : null}
            </article>
          );
        })
      )}
    </div>
  );
}
