import { formatDateTime, formatMoney } from "@/lib/management";
import { getRiderSession } from "@/lib/rider";

export default async function RiderCashPage() {
  const { supabase, riderProfile } = await getRiderSession();

  const { data: settlements } = riderProfile
    ? await supabase
        .from("rider_settlements")
        .select("id, settled_at, expected_amount_minor, actual_amount_minor, variance_minor, currency_code, notes")
        .order("settled_at", { ascending: false })
        .limit(30)
    : { data: [] };

  return (
    <div>
      <h1 className="rider-section-title">Cash</h1>

      <div className="rider-cash-summary">
        <span>Cash held, awaiting settlement</span>
        <strong>{formatMoney(riderProfile?.cash_outstanding_minor ?? 0)}</strong>
      </div>

      {!settlements?.length ? (
        <p className="rider-empty">No settlements recorded yet. Hand cash to your manager to clear it here.</p>
      ) : (
        settlements.map((settlement) => (
          <div className="rider-settlement-row" key={settlement.id}>
            <span>{formatDateTime(settlement.settled_at)}</span>
            <span>
              {formatMoney(settlement.actual_amount_minor, settlement.currency_code)}
              {settlement.variance_minor !== 0 ? ` (${settlement.variance_minor > 0 ? "+" : ""}${formatMoney(settlement.variance_minor, settlement.currency_code)})` : ""}
            </span>
          </div>
        ))
      )}
    </div>
  );
}
