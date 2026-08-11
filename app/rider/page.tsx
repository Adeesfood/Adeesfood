import { acceptDelivery, markDelivered, markOnTheWay, markPickedUp, reportDeliveryIssue } from "@/app/rider/actions";
import { formatMoney } from "@/lib/management";
import { getRiderSession } from "@/lib/rider";

const NEXT_ACTION: Record<string, { action: typeof acceptDelivery; label: string } | undefined> = {
  ASSIGNED: { action: acceptDelivery, label: "Accept delivery" },
  ACCEPTED: { action: markPickedUp, label: "Picked up" },
  PICKED_UP: { action: markOnTheWay, label: "Start delivery" },
  ON_THE_WAY: { action: markDelivered, label: "Mark delivered" },
};

export default async function RiderDeliveriesPage({
  searchParams,
}: {
  searchParams: Promise<{ success?: string; error?: string }>;
}) {
  const { supabase, assignment } = await getRiderSession();
  const query = await searchParams;

  const { data: deliveries } = await supabase
    .from("deliveries")
    .select(
      "id, delivery_status, address_line, area, landmark, delivery_notes, package_count, payment_method, amount_due_minor, currency_code, order:orders(order_number, guest_name, guest_phone), customer:customers(display_name, phone)",
    )
    .eq("organization_id", assignment.organization_id)
    .in("delivery_status", ["ASSIGNED", "ACCEPTED", "PICKED_UP", "ON_THE_WAY"])
    .order("assigned_at", { ascending: true });

  return (
    <div>
      <h1 className="rider-section-title">My deliveries</h1>
      {query.error ? <div className="rider-alert is-error">{query.error}</div> : null}
      {query.success ? <div className="rider-alert is-success">{query.success}</div> : null}

      {!deliveries?.length ? (
        <p className="rider-empty">No active deliveries right now. New assignments will appear here.</p>
      ) : (
        deliveries.map((delivery) => {
          const next = NEXT_ACTION[delivery.delivery_status];
          const fullAddress = [delivery.address_line, delivery.area, delivery.landmark].filter(Boolean).join(", ");
          const order = Array.isArray(delivery.order) ? delivery.order[0] : delivery.order;
          const customer = Array.isArray(delivery.customer) ? delivery.customer[0] : delivery.customer;
          const customerName = customer?.display_name ?? order?.guest_name ?? "Customer";
          const customerPhone = customer?.phone ?? order?.guest_phone ?? null;

          return (
            <article className="rider-card" key={delivery.id}>
              <div className="rider-card-head">
                <strong>#{order?.order_number ?? "—"}</strong>
                <span className="rider-card-status">{delivery.delivery_status.replace(/_/g, " ")}</span>
              </div>

              <p className="rider-customer">{customerName}</p>
              <p>{fullAddress || "Address on file"}</p>
              {delivery.delivery_notes ? <p>Note: {delivery.delivery_notes}</p> : null}
              <p>{delivery.package_count} package{delivery.package_count === 1 ? "" : "s"}</p>

              {delivery.payment_method === "CASH_ON_DELIVERY" && delivery.amount_due_minor > 0 ? (
                <p className="rider-collect">
                  Collect {formatMoney(delivery.amount_due_minor, delivery.currency_code)}
                </p>
              ) : null}

              <div className="rider-utility-row">
                {customerPhone ? <a href={`tel:${customerPhone}`}>Call</a> : null}
                <a href={`https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(fullAddress)}`} target="_blank" rel="noreferrer">
                  Directions
                </a>
              </div>

              {next ? (
                <form action={next.action}>
                  <input type="hidden" name="delivery_id" value={delivery.id} />
                  <button type="submit" className="rider-primary-action">{next.label}</button>
                </form>
              ) : null}

              <details className="rider-issue-details">
                <summary>Report an issue</summary>
                <form action={reportDeliveryIssue} className="rider-issue-form">
                  <input type="hidden" name="delivery_id" value={delivery.id} />
                  <select name="issue_action" defaultValue="FAILED">
                    <option value="FAILED">Customer unreachable / delivery failed</option>
                    <option value="RETURNED">Returning order</option>
                  </select>
                  <textarea name="reason" placeholder="What happened?" rows={2} required />
                  <button type="submit">Submit</button>
                </form>
              </details>
            </article>
          );
        })
      )}
    </div>
  );
}
