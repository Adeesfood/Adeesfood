# Adee's Food — Role and Permission Matrix

**Status:** Phase 0 access-control proposal
**Primary roles from the brief:** `RECEPTIONIST`, `MANAGER`, `OWNER`

## 1. Access-control principles

1. Permissions grant named business capabilities; role names alone are not authorization checks.
2. Access is scoped to an organization and, normally, one or more locations.
3. The least-privileged role is the default. No role receives generic table update or delete rights.
4. Hiding a button is user experience, not security. The same rule is enforced in route/layout checks, server commands, and Supabase RLS/database functions.
5. A user may not approve their own action when a configured dual-approval rule applies.
6. High-risk actions require a reason, an audit event, and possibly MFA (`aal2`) or a second approver.
7. Completed commercial, stock and financial records are corrected by linked reversal—not editing or deletion.
8. Role/permission changes take effect from live database assignments. Staff deactivation immediately blocks application access.

## 2. Role intent

| Role | Operational intent | Default scope |
|---|---|---|
| Receptionist | Run front-of-house orders, payments, tables, reservations and customer service | Assigned location(s); own shift where applicable |
| Manager | Supervise restaurant operations, approve bounded exceptions, manage inventory/purchasing/staff operations and close the day | Assigned location(s) |
| Owner | Organization-wide governance, finance, settings, security, audit and high-value approvals | All assigned organization locations |

`OWNER` does not mean unrestricted database credentials. Owners still use authenticated, audited commands subject to RLS and MFA.

## 3. Permission legend

- **Yes** — granted by default within assigned scope.
- **Own** — only records owned by or assigned to the current user/shift.
- **Limited** — permitted within configured thresholds or record states.
- **Approve** — may approve another user's request within policy.
- **No** — not granted.
- **AAL2** — owner permission additionally requires a current MFA-assured session.

## 4. Detailed matrix

### 4.1 Dashboard, orders and POS

| Permission code / capability | Receptionist | Manager | Owner | Control notes |
|---|---:|---:|---:|---|
| `dashboard.view_operational` | Yes | Yes | Yes | Location-scoped; no unrestricted finance |
| `orders.view` | Yes | Yes | Yes | Only assigned location/history window by policy |
| `orders.create` | Yes | Yes | Yes | Price and tax calculated by command |
| `orders.update_draft` | Yes | Yes | Yes | Expected-version check |
| `orders.submit` | Yes | Yes | Yes | Creates durable commercial order |
| `orders.send_kitchen` | Yes | Yes | Yes | Idempotent; only eligible lines |
| `orders.add_after_send` | Limited | Yes | Yes | New lines become new kitchen routing event |
| `orders.cancel_unstarted` | Limited | Yes | Yes | Receptionist only before preparation/payment and with reason |
| `orders.void_posted` | No | Approve | Yes (AAL2 over threshold) | Never deletes original |
| `orders.reopen_completed` | No | No | Yes (AAL2) | Exceptional; prefer adjustment/refund |
| `orders.transfer_table` | Limited | Yes | Yes | Destination must be available; audit |
| `orders.merge_split` | Limited | Yes | Yes | Final rules require approval; no settled allocation loss |
| `discounts.apply_standard` | Limited | Yes | Yes | Active configured discounts only |
| `discounts.apply_manual` | No | Limited | Yes | Reason and amount/percentage thresholds |
| `discounts.approve` | No | Approve | Approve | Cannot approve own dual-approval request |
| `receipts.print_or_send` | Yes | Yes | Yes | Redact according to channel |

### 4.2 Payments, refunds and cash

| Permission code / capability | Receptionist | Manager | Owner | Control notes |
|---|---:|---:|---:|---|
| `payments.view_order` | Yes | Yes | Yes | Only payment detail required for service |
| `payments.record` | Yes | Yes | Yes | Configured methods; provider/reference checks |
| `payments.split_tender` | Yes | Yes | Yes | Total allocation invariant enforced |
| `payments.correct_unsettled` | Limited | Yes | Yes | Only before successful settlement; audit |
| `refunds.request` | Yes | Yes | Yes | Reason and refundable amount required |
| `refunds.approve` | No | Limited | Yes (AAL2 over threshold) | Separate requester/approver when policy requires |
| `refunds.process` | No | Limited | Yes | Provider result and idempotency recorded |
| `cash_sessions.open_own` | Yes | Yes | Yes | Opening float recorded |
| `cash_sessions.declare_close_own` | Own | Yes | Yes | Expected total hidden until declaration if policy chosen |
| `cash_movements.record` | Limited | Yes | Yes | Receptionist: configured minor paid-in/out only |
| `cash_variance.approve` | No | Limited | Yes | Threshold-based |

### 4.3 Kitchen, tables and reservations

| Permission code / capability | Receptionist | Manager | Owner | Control notes |
|---|---:|---:|---:|---|
| `kitchen.view_status` | Yes | Yes | Yes | Front-of-house status view, not necessarily station queue |
| `kitchen.start_ticket` | No* | Yes | Yes | `*` pending kitchen operator identity decision |
| `kitchen.ready_ticket` | No* | Yes | Yes | Named actor/station required |
| `kitchen.recall_ticket` | No | Limited | Yes | Reason; cannot hide fulfilled history |
| `kitchen.reroute_ticket` | No | Yes | Yes | Audit and station notification |
| `tables.view` | Yes | Yes | Yes | Location-scoped |
| `tables.open_session` | Yes | Yes | Yes | One active session per table |
| `tables.change_status` | Limited | Yes | Yes | Out-of-service requires manager |
| `tables.close_session` | Limited | Yes | Yes | Settlement/fulfillment rules apply |
| `reservations.view` | Yes | Yes | Yes | Personal data minimized |
| `reservations.create_update` | Yes | Yes | Yes | Conflict check |
| `reservations.cancel_no_show` | Yes | Yes | Yes | Reason/status event |
| `reservations.override_conflict` | No | Limited | Yes | Explicit warning and reason |

Kitchen staff must not share a manager account. Before KDS implementation, approve either named kitchen users with a narrow `KITCHEN_OPERATOR` role (recommended) or another accountable identity design. That role would receive only ticket view/start/ready and station-scoped access.

### 4.4 Customers and menu

| Permission code / capability | Receptionist | Manager | Owner | Control notes |
|---|---:|---:|---:|---|
| `customers.lookup` | Yes | Yes | Yes | Exact/limited search; masked fields where possible |
| `customers.create_update_basic` | Yes | Yes | Yes | No hidden sensitive notes |
| `customers.export` | No | No | Yes (AAL2) | Purpose, time-limited export, audit |
| `customers.merge` | No | Limited | Yes | Preserves source IDs/history |
| `customers.delete_or_anonymize` | No | No | Yes (AAL2) | Subject to legal/retention policy |
| `menu.view_internal` | Yes | Yes | Yes | Includes current availability, not supplier cost for Receptionist |
| `menu.toggle_availability` | Limited | Yes | Yes | Receptionist may mark temporary sold-out if approved policy |
| `menu.manage_catalog` | No | Yes | Yes | Changes versioned and audited |
| `menu.manage_prices_tax` | No | Limited | Yes (AAL2 for tax/settings) | Effective-dated; approval threshold |
| `menu.manage_modifiers_routing` | No | Yes | Yes | Validate recipes/stations before activation |

### 4.5 Inventory and recipes

| Permission code / capability | Receptionist | Manager | Owner | Control notes |
|---|---:|---:|---:|---|
| `inventory.view_on_hand` | No | Yes | Yes | Receptionist sees only availability, not balances/cost |
| `inventory.view_cost` | No | Limited | Yes | Sensitive margin data |
| `inventory.count_enter` | No | Yes | Yes | Counter cannot silently change expected quantity |
| `inventory.count_approve_post` | No | Limited | Yes | Segregation/threshold policy |
| `inventory.adjust` | No | Limited | Yes | Movement, reason and approval—not balance edit |
| `inventory.record_wastage` | No | Yes | Yes | Threshold may require owner approval |
| `inventory.transfer` | No | Yes | Yes | Paired shipment/receipt workflow |
| `inventory.manage_items_units` | No | Yes | Yes | Unit changes blocked after use; version conversion |
| `recipes.view` | No | Yes | Yes | Receptionist does not see cost/composition by default |
| `recipes.create_draft` | No | Yes | Yes | Draft only |
| `recipes.publish_version` | No | Limited | Yes | Unit/yield validation; immutable after publish |
| `recipes.view_margin` | No | Limited | Yes | Manager scope can be configured |

### 4.6 Suppliers and purchasing

| Permission code / capability | Receptionist | Manager | Owner | Control notes |
|---|---:|---:|---:|---|
| `suppliers.view` | No | Yes | Yes | Bank/payment details further restricted |
| `suppliers.manage` | No | Limited | Yes | Bank-detail changes require re-verification/audit |
| `purchase_requests.create` | No | Yes | Yes | Request does not alter stock/liability |
| `purchase_requests.approve` | No | Limited | Yes | Threshold and self-approval rules |
| `purchase_orders.create_issue` | No | Limited | Yes | Frozen terms after issue |
| `goods_receipts.record` | No | Yes | Yes | Accepted/rejected quantity and receiver identity |
| `goods_receipts.post_override` | No | Limited | Yes | Over-receipt/tolerance reason |
| `supplier_invoices.record` | No | Yes | Yes | Duplicate and match controls |
| `supplier_invoices.approve` | No | Limited | Yes | Threshold/three-way exception policy |
| `supplier_payments.request` | No | Yes | Yes | Does not itself settle payment |
| `supplier_payments.approve_process` | No | No by default | Yes (AAL2) | Manager access only if owner configures limits |

### 4.7 Staff, finance, reporting and administration

| Permission code / capability | Receptionist | Manager | Owner | Control notes |
|---|---:|---:|---:|---|
| `staff.view_schedule` | Own | Yes | Yes | Personal fields minimized |
| `staff.manage_shifts_attendance` | No | Yes | Yes | Corrections are linked events |
| `staff.manage_employment` | No | Limited | Yes | No payroll in initial scope |
| `expenses.create` | No | Yes | Yes | Receipt and category policy |
| `expenses.approve_post` | No | Limited | Yes | Threshold and self-approval controls |
| `daily_close.prepare` | No | Yes | Yes | Expected values system-derived |
| `daily_close.post` | No | Limited | Yes | Exceptions resolved/acknowledged |
| `daily_close.reopen` | No | No | Yes (AAL2) | New version; original preserved |
| `reports.view_own_shift` | Own | Yes | Yes | Receptionist: own sales/receipts only |
| `reports.view_operational` | No | Yes | Yes | Assigned locations |
| `reports.view_financial` | No | Limited | Yes | Manager detail configurable |
| `reports.export` | No | Limited | Yes (AAL2 for sensitive exports) | Audit, expiry, row cap |
| `audit.view` | No | Limited | Yes (AAL2) | Manager sees own location operational audit only |
| `security.manage_users_roles` | No | No | Yes (AAL2) | Cannot grant outside owner's organization |
| `settings.manage_location` | No | Limited | Yes | Low-risk operational settings only for manager |
| `settings.manage_financial_security` | No | No | Yes (AAL2) | Tax, payment, permission, approval, sequence settings |
| `periods.lock_reopen` | No | No | Yes (AAL2) | Reason and audit required |

## 5. Enforcement map

| Layer | Required implementation |
|---|---|
| Navigation/UI | Permission-aware module list; disabled actions explain why; never expose sensitive values unnecessarily |
| Next.js route/layout | Verify Supabase user/session on server; verify active organization/location assignment; redirect to sign-in/MFA/access-denied |
| Server command | Check permission code, scope, record state, amount threshold, MFA and approval; do not trust client role/price/total |
| Postgres function | Recheck actor and permission in the transaction; fixed `search_path`; allow-listed transitions; audit and idempotency |
| RLS | Default deny; select/mutation policies constrained by assignment, scope and permission; direct ledger mutations denied |
| Storage RLS | Private bucket path and permission rules mirror organization/location and document class |
| Audit/alerts | Record all high-risk attempts, approvals, denials and successful transitions; alert on suspicious patterns |

## 6. Approval policy baseline

Exact Ghana cedi thresholds must be set by the owner before pilot. The architecture supports:

- manager approval up to a configured amount or percentage;
- owner approval above that threshold;
- dual approval for supplier bank-detail changes, large supplier payments, daily-close reopening and high-value refunds;
- no self-approval when dual approval applies;
- approval expiry and binding to the exact payload hash;
- a fresh `aal2` owner session for high-risk commands.

## 7. Access-control acceptance tests

For every permission, automated tests must prove:

1. the intended role can act inside its assigned location;
2. the same role cannot act in another organization or unassigned location;
3. the lower role cannot call the Server Action directly or invoke the database command;
4. a stale/removed role assignment fails immediately at the database;
5. forbidden state transitions fail even with an otherwise sufficient role;
6. threshold, self-approval and MFA rules fail closed;
7. protected tables cannot be changed through generic Data API mutation;
8. successful and denied sensitive actions create the intended audit evidence without leaking secrets.

## 8. Decisions required

1. Approve the proposed `KITCHEN_OPERATOR` role or define another individually accountable KDS identity.
2. Provide manager and owner monetary/percentage approval thresholds.
3. Decide whether managers may view ingredient costs, menu margin and full financial statements.
4. Decide whether a receptionist may temporarily mark an item sold out.
5. Decide retention and export rules for customer and staff personal data.
6. Confirm whether supplier payment processing is owner-only at launch.
