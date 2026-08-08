# Adee's Food — Order Lifecycle

**Status:** Phase 0 workflow proposal
**Applies to:** Dine-in, takeaway and delivery orders

## 1. Order aggregate

The order is the commercial source of truth. It contains immutable line snapshots and independent status dimensions for commerce, kitchen, payment and fulfillment. Kitchen tickets, payments, refunds, table sessions, stock consumption and financial events reference the order; none replaces it.

Every command accepts `order_id`, `expected_version`, `idempotency_key`, actor/session context, and command-specific input. The database locks the order, checks the expected version and commits all related changes atomically.

## 2. Status dimensions

### Commercial `order_status`

```text
DRAFT -> CONFIRMED -> IN_PROGRESS -> FULFILLED -> COMPLETED
   |         |              |            |
   +------> CANCELLED <------+            +--> refund remains separate
             |
             +--> VOIDED only through a controlled posted-document action
```

| State | Meaning | Entry rule |
|---|---|---|
| `DRAFT` | Editable basket, not committed to preparation | Created by authorized staff |
| `CONFIRMED` | Prices/taxes snapshotted and commercial order number assigned | Sellability and totals validated |
| `IN_PROGRESS` | At least one operational action has begun | Kitchen queued/preparing or non-kitchen fulfillment begun |
| `FULFILLED` | Required items served/collected/dispatched/delivered under policy | Fulfillment rollup passes |
| `COMPLETED` | Commercial workflow closed | Required settlement and fulfillment pass |
| `CANCELLED` | Valid order stopped before completion | Reason, disposition, payment/stock handling |
| `VOIDED` | Posted order declared invalid under controlled policy | Manager/owner approval; no deletion |

### Kitchen `kitchen_status`

`NOT_REQUIRED -> NOT_SENT -> QUEUED -> PREPARING -> PARTIALLY_READY -> READY`, with `CANCELLED` only through an authorized order/ticket cancellation path.

### Settlement `payment_status`

`UNPAID -> PARTIALLY_PAID -> PAID -> PARTIALLY_REFUNDED -> REFUNDED`.

A failed or abandoned provider attempt is recorded as a payment attempt/status, but does not increase paid value.

### Fulfillment `fulfillment_status`

- Dine-in: `NOT_STARTED -> READY_FOR_HANDOFF -> SERVED`.
- Takeaway: `NOT_STARTED -> READY_FOR_HANDOFF -> COLLECTED`.
- Delivery: `NOT_STARTED -> READY_FOR_HANDOFF -> DISPATCHED -> DELIVERED`.

`DELIVERED` must mean a known delivery confirmation event; if no provider verification exists, label it as staff-reported.

## 3. Shared order flow

### Step 1 — Start order

1. Staff chooses order type and location; dine-in requires an open/selected table session.
2. The database creates `DRAFT` with the configured currency, business date, creator/server and idempotency record.
3. Optional customer lookup is limited and consent-aware; an order may remain a guest order.

### Step 2 — Build draft

1. Staff adds menu variants, quantities, modifiers and preparation notes.
2. Server reads current active price, tax, service charge, modifier and availability rules.
3. Each line stores references plus display/price/rate snapshots.
4. Database recomputes subtotal, tax, service charge, discount and total. Client calculations are estimates only.
5. Update checks `expected_version`; a stale terminal must refresh rather than overwrite another user's changes.

### Step 3 — Apply discount

1. Standard discount checks validity, applicable products/order type and combinability.
2. Manual discount requires `discounts.apply_manual`, reason and threshold policy.
3. Higher values create an approval request bound to the exact order version and proposed amount.
4. Any material order edit invalidates an unconsumed approval.

### Step 4 — Confirm

`submit_order` validates:

- at least one valid line;
- item/modifier availability and required selections;
- active location price/tax/routing/recipe configuration;
- customer/table/delivery fields required for the type;
- discount approval;
- database totals and non-negative balance.

It allocates an order number, sets `CONFIRMED`, freezes relevant snapshots, appends status/audit events and emits an outbox event.

### Step 5 — Route to kitchen

`send_order_to_kitchen` creates station tickets only for unsent quantities. Retry returns the same ticket result. Non-kitchen lines move through the fulfillment workflow without a ticket. See `KITCHEN_WORKFLOW.md`.

Adding items after send creates new order line(s), new version and a clearly marked follow-up ticket. Sent snapshots are not rewritten.

### Step 6 — Settle payment

1. Staff selects one or more configured methods.
2. Database verifies order balance and records a pending/successful/failed payment as appropriate.
3. Cash is successful when accepted under the open cash session policy. Electronic methods are successful only when the defined provider/reference verification passes.
4. Successful allocation updates the derived payment status.
5. Duplicate provider callbacks or terminal retries are absorbed by idempotency/unique reference constraints.

Whether payment occurs before or after preparation is an order-type setting, not a different data model.

### Step 7 — Fulfill

Authorized staff record service, collection, dispatch or delivery events. Item-level fulfillment rolls up to order fulfillment. The system records actor/time and prevents a delivery order from skipping required states unless a manager uses an audited override.

### Step 8 — Complete

`complete_order` requires:

- no active kitchen work unless explicitly not required/cancelled;
- fulfillment at the final required state;
- payment state accepted by location policy (normally `PAID`);
- no unresolved blocking exception;
- table/cash allocation consistency.

The command sets `COMPLETED`, writes final financial events, closes/updates the table session where appropriate, creates a receipt reference and emits completion events. A completed order is immutable except through approved refund/reversal/correction workflows.

## 4. Order-type differences

| Concern | Dine-in | Takeaway | Delivery |
|---|---|---|---|
| Required association | Open table session | Pickup name or number | Customer/contact and delivery destination |
| Service charge | Configurable dine-in rule | Configurable | Configurable plus delivery fee |
| Final fulfillment | `SERVED` | `COLLECTED` | `DELIVERED` |
| Table state | Occupied until session close/clear | None | None |
| Payment timing | Before or after meal by policy | Commonly before preparation/collection | Provider/policy dependent |
| Extra events | Table transfer/split/merge | Pickup handoff | Dispatch, courier/provider reference, delivery confirmation |

Delivery address/access must be restricted personal data. Do not store card details or unnecessary identity documents.

## 5. Cancellation, void and refund rules

These terms are not interchangeable:

| Action | When | Money treatment | Stock/food treatment | Authority |
|---|---|---|---|---|
| Remove draft line | Before confirmation/send | Recalculate only | None | Order editor |
| Cancel unstarted line/order | Confirmed but not prepared | Reverse authorization/payment if needed | No consumption, or reverse only an unstarted posting | Receptionist within policy; otherwise manager |
| Cancel after preparation begins | Prepared/in progress | Refund policy may apply | Do not silently restore ingredients; record wastage or valid return disposition | Manager/owner threshold |
| Void order | Posted document invalid under policy | Linked financial reversal | Explicit item disposition | Manager/owner; reason/approval |
| Refund | Successful payment exists | Linked partial/full refund | Independent from stock unless returned product is accepted | Manager/owner threshold |

The command asks for a disposition per affected item: `NOT_STARTED`, `RETURNED_TO_STOCK`, `WASTED`, or `FULFILLED_NO_CHARGE`. Only `NOT_STARTED` or a verified reusable return can reverse inventory; prepared food becomes wastage with cost.

## 6. Split, merge and table transfer

- **Split bill:** create payment allocations or child checks against explicit order items/quantities. Do not duplicate order lines or lose the original order trail.
- **Split order:** allowed only through a command that preserves source/child links, line quantities, discounts, tax and payments.
- **Merge orders:** only compatible open orders at the same location/currency/business date and before conflicting settlement; preserve source links.
- **Table transfer:** moves the open table-session association after locking both tables and verifying capacity/availability policy.
- Every operation records actor, reason, before/after mapping and idempotency key.

Detailed policy for split tax/service charge and mixed-tender refunds requires owner/accountant approval before implementation.

## 7. Receipts

A receipt is generated from committed database state and includes order/receipt number, business identity, timestamp/business date, item/modifier lines, tax/service/discount totals, payment methods, refund references and required legal text. The receipt stores its settings/template version. Reprinting does not generate a new sale; it creates an audit event.

## 8. Failure and recovery behavior

| Failure | Required behavior |
|---|---|
| Network drops after command | Retry with same idempotency key; query order before showing failure |
| Stale order version | Reject with current version and human-readable conflict |
| KDS realtime unavailable | Order remains committed; KDS re-queries queue on reconnect |
| Electronic provider timeout | Keep attempt pending/unknown; reconcile provider reference before retry |
| Printer unavailable | Order/payment remains committed; allow later reprint |
| Stock consumption fails | Transaction rolls back ticket start; alert rather than partial state |
| Client closes mid-draft | Restore local/server draft subject to expiry and version check |

## 9. Audit events

At minimum: order create/submit/edit-after-send, discount request/approval, kitchen send, table transfer, split/merge, payment attempt/success/failure, completion, cancellation, void, item disposition, refund, receipt print/send and any override/denial.

## 10. Acceptance criteria

1. Concurrent terminals cannot silently overwrite an order.
2. A retried send, payment, completion or cancellation cannot duplicate tickets, money, stock or receipts.
3. All displayed totals reproduce from immutable line/rate snapshots.
4. Order, kitchen, payment and fulfillment status can differ without contradiction.
5. Completed orders and successful payments cannot be edited/deleted.
6. Every cancellation/void/refund shows reason, actor, approval, disposition and linked reversal.
7. Cross-location access fails at RLS even when an API request is manually constructed.

## 11. Decisions required

1. Payment-before-preparation rules by order type.
2. Dine-in service charge and tax calculation/order of operations.
3. Split-bill tax, service charge and discount allocation rules.
4. Delivery provider, fee, proof and cancellation rules.
5. Receptionist cancellation/discount limits.
6. Order and receipt number format required for Ghana operations.
