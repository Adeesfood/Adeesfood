# Adee's Food — Kitchen Workflow

**Status:** Phase 0 KDS proposal
**Goal:** Every confirmed prepared item reaches the correct station, is accountable, and cannot be lost when realtime or a screen fails

## 1. Core model

- The order is the commercial record.
- A kitchen ticket is a station-specific work projection created from committed order items.
- Each ticket item retains the order item ID, item/modifier/note snapshots, quantity and routing event.
- Ticket events are append-only. Realtime only announces durable database changes.
- Staff identity is required for `START`, `READY`, `CANCEL`, `RECALL` and reroute actions.

Kitchen identity is unresolved in the brief. The recommendation is a fourth, narrow `KITCHEN_OPERATOR` role assigned to named staff and station/location. Shared manager credentials are prohibited.

## 2. Routing configuration

Each sellable menu variant declares whether it requires preparation and its station assignment(s). Examples might include grill, hot kitchen, drinks and pass, but names must come from Adee's actual operation.

Validation before a menu item can become available:

- active location price;
- valid modifier selection rules;
- active station routing for prepared items;
- published recipe when inventory consumption is enabled;
- target preparation time and availability state.

Multi-station items create explicit routed ticket items. A pass/expediter view may aggregate station readiness without creating a second commercial item.

## 3. Ticket lifecycle

```text
ORDER CONFIRMED
      |
      v
NOT_SENT --send--> QUEUED --start--> PREPARING --ready--> READY
                           \                         /
                            +----cancel/recall------+  (permission + reason)
```

| State | Meaning | Required data |
|---|---|---|
| `QUEUED` | Durable ticket is waiting at an assigned station | `queued_at`, station, target seconds, priority |
| `PREPARING` | A named operator has accepted work | `started_at`, `started_by`; inventory consumption trigger |
| `READY` | Station completed its assigned quantity | `ready_at`, `ready_by` |
| `CANCELLED` | Authorized cancellation with explicit food/stock disposition | actor, reason, disposition, approval if required |

A ticket cannot return from `READY` to `PREPARING` by editing its status. A recall/re-fire command creates a linked event and, if new preparation is required, a new ticket quantity with an explicit wastage/consumption outcome.

## 4. End-to-end flow

### 4.1 Send from POS

`send_order_to_kitchen`:

1. locks the order and verifies `CONFIRMED`/eligible status;
2. finds only unsent prepared quantities;
3. validates active station routing;
4. creates one ticket per order-routing batch/station and its ticket items;
5. updates kitchen rollups to `QUEUED`;
6. records order/ticket events and outbox notifications in the same transaction.

The ticket number/order number, order type, table/pickup reference, elapsed time, item quantity, modifiers, notes, follow-up status and allergens (if trustworthy data exists) must be prominent. Color is supplementary; text/icon labels remain mandatory.

### 4.2 Queue and prioritization

Default queue order is committed `queued_at`, with controlled priority flags for legitimate operational cases. Staff cannot drag tickets into an unaudited arbitrary sequence.

Age bands derive from each ticket's snapshotted target:

- normal: below warning threshold;
- warning: target approaching;
- late: target exceeded;
- critical: configured escalation exceeded.

Priority changes require permission, actor and reason. The dashboard raises alerts for long-wait tickets but never changes status automatically.

### 4.3 Start preparation

`start_kitchen_ticket` or an item-level equivalent:

1. verifies operator assignment, station, current state and version;
2. locks the ticket/order items;
3. sets `PREPARING` and timestamps;
4. posts theoretical ingredient consumption for eligible order items exactly once;
5. writes stock movements, consumption record, audit and outbox event atomically.

Recommended inventory trigger: preparation start. It best represents ingredients being committed to production. If Adee's operating procedure requires send-to-kitchen or completion instead, the trigger may be configured per location before launch, but it must remain one idempotent event.

### 4.4 Mark ready

The command records ready quantities and actor. A ticket is `READY` only when all active ticket-item quantities are ready/cancelled. Order kitchen status becomes:

- `PARTIALLY_READY` when some required routed quantities are ready;
- `READY` when all required quantities are ready;
- `NOT_REQUIRED` when no line requires kitchen work.

The front-of-house order/table view is notified to serve, collect or dispatch. `READY` is not the same as `SERVED`, `COLLECTED` or `DELIVERED`.

### 4.5 Handoff

Front-of-house staff confirm the relevant fulfillment event. The KDS may show a read-only handoff indicator but does not directly mark a payment or commercial order complete.

## 5. Changes after send

| Change | Treatment |
|---|---|
| Add item | New order line/version and a clearly marked `FOLLOW_UP` ticket |
| Increase quantity | New delta ticket quantity; original ticket untouched |
| Remove queued item | Authorized cancellation event; no consumption if not started |
| Remove preparing/ready item | Manager approval as configured; prepared quantity becomes wastage or fulfilled-no-charge |
| Change modifier/note | Cancel/re-fire affected quantity unless station has not accepted and policy permits replacement; full event trail |
| Reroute station | Manager command cancels old routing and creates linked new routing |
| Re-fire | New ticket linked to original, reason required, additional consumption/wastage handled explicitly |

No client silently edits the text of an already accepted ticket.

## 6. Inventory coupling

For each order item, `order_item_consumptions` pins recipe version, servings, trigger and movement batch. The database's unique constraint prevents duplicate consumption.

Cancellation disposition rules:

- `NOT_STARTED`: no consumption, or reverse the unstarted posting if the configured trigger was earlier;
- `RETURNED_TO_STOCK`: only for a verifiably reusable, controlled ingredient/product; creates a linked positive movement;
- `WASTED`: keep consumption and record wastage/reason/cost;
- `FULFILLED_NO_CHARGE`: keep consumption, connect financial discount/void outcome.

Negative inventory policy must be explicit. Recommended launch behavior is to block consumption that would drive tracked stock negative, with a narrowly authorized manager override that creates an alert and requires correction/count.

## 7. Realtime and resilience

- Subscribe to private topics scoped by organization, location and station.
- Broadcast only event metadata; query authorized database rows for the actual queue.
- On initial load and reconnect, fetch every non-terminal ticket for the station and reconcile versions.
- Display `Live`, `Reconnecting`, or `Stale since <time>` visibly.
- Do not accept start/ready actions while the client cannot confirm a command response.
- A tablet sleep, browser refresh or missed message must not lose a ticket.
- A station may use an audible/visual new-ticket notification, but failure of that notification does not affect queue durability.

## 8. KDS views

| View | Purpose | Data boundary |
|---|---|---|
| Station queue | Work assigned to one station | Active tickets for authorized station/location |
| Expediter/pass | Combined order readiness across stations | Manager or proposed pass permission |
| Front-of-house status | Queued/preparing/ready summary | No recipe costs or sensitive stock data |
| Manager history | Search ticket events, delays, cancels and re-fires | Location-scoped, audited exports |

The KDS must support touch, keyboard fallback, large text, non-color status labels, confirmation for destructive actions and an obvious order/table/pickup identity.

## 9. Timing metrics

Store event timestamps; derive rather than type:

- queue wait = `started_at - queued_at`;
- preparation time = `ready_at - started_at`;
- total kitchen time = `ready_at - queued_at`;
- handoff delay = fulfillment handoff time minus final `ready_at`;
- recall/re-fire rate and cancelled-after-start rate.

Reports must exclude or separately identify cancelled tickets and explain clock/data gaps. Targets are snapshotted so later configuration changes do not rewrite historical performance.

## 10. Failure and exception handling

| Scenario | Required behavior |
|---|---|
| No active route | Order submission/send is blocked with actionable configuration error |
| Station offline | Ticket remains queued in Postgres; manager alert; alternate station reroute is audited |
| Two operators press Start | Row/version lock allows one transition; other receives current state |
| Start succeeds but broadcast fails | Transaction remains valid; polling/reconnect finds ticket |
| Consumption cannot post | Start transaction rolls back; manager sees blocking inventory alert |
| Wrong item marked ready | Recall/re-fire workflow; no history deletion |
| Order cancellation races with ready | Locked transaction resolves one valid transition; losing command refreshes |

## 11. Acceptance criteria

1. Every sent prepared item appears on exactly the required station ticket(s).
2. Repeated sends and reconnects cannot duplicate ticket quantity.
3. Ticket actions identify a real operator and station.
4. Start posts recipe consumption exactly once or does not transition at all.
5. Ready status rolls up correctly without implying service/payment completion.
6. Cancel, reroute and re-fire preserve linked history and stock disposition.
7. KDS recovers complete active state after losing all realtime messages.
8. Unauthorized stations/locations cannot query or mutate tickets through Supabase.

## 12. Decisions required

1. Approve named `KITCHEN_OPERATOR` users and whether one person may cover multiple stations.
2. Provide actual station names, routing, preparation targets and escalation thresholds.
3. Confirm the inventory deduction trigger.
4. Decide whether an expediter/pass role and screen are required at launch.
5. Define re-fire, complimentary item and after-start cancellation approval rules.
6. Confirm allergen data ownership; do not display unverified allergen claims as authoritative.
