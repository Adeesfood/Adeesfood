import { setOwnRiderStatus } from "@/app/rider/actions";
import { getRiderSession } from "@/lib/rider";

const STATUSES = ["AVAILABLE", "OFFLINE", "UNAVAILABLE"] as const;

export default async function RiderProfilePage({
  searchParams,
}: {
  searchParams: Promise<{ success?: string; error?: string }>;
}) {
  const { displayName, assignment, riderProfile } = await getRiderSession();
  const query = await searchParams;

  if (!riderProfile) {
    return (
      <div>
        <h1 className="rider-section-title">Profile</h1>
        <p className="rider-empty">
          Your rider profile hasn&apos;t been activated yet. Ask a manager to set you up in Deliveries → Riders.
        </p>
      </div>
    );
  }

  return (
    <div>
      <h1 className="rider-section-title">Profile</h1>
      {query.error ? <div className="rider-alert is-error">{query.error}</div> : null}
      {query.success ? <div className="rider-alert is-success">{query.success}</div> : null}

      <article className="rider-card">
        <p className="rider-customer">{displayName}</p>
        <p>{assignment.organization_name}</p>
        <p>{assignment.location_name ?? "Main branch"}</p>
      </article>

      <article className="rider-card">
        <p className="rider-customer">Availability</p>
        <p>Set this to Offline when you finish your shift so you stop receiving new deliveries.</p>
        <form action={setOwnRiderStatus} className="rider-issue-form">
          <input type="hidden" name="rider_profile_id" value={riderProfile.id} />
          <select name="status" defaultValue={riderProfile.status}>
            {STATUSES.map((status) => (
              <option key={status} value={status}>
                {status.replace(/_/g, " ")}
              </option>
            ))}
          </select>
          <button type="submit">Update status</button>
        </form>
      </article>
    </div>
  );
}
