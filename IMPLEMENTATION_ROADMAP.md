# Adee's Food Restaurant Management System — Implementation Roadmap

**Status:** Phase 0 sequencing proposal
**Rule:** No implementation phase begins until the Phase 0 documents and its decision gates are reviewed and accepted

## 1. Delivery principles

- Build vertical, auditable workflows rather than disconnected screens.
- Establish identity, RLS, transactions, idempotency and audit before sensitive features.
- Treat Supabase migrations and tests as product code.
- Pilot with one location and representative devices, but preserve location scope in the schema.
- Do not claim finance/inventory accuracy until recipes, opening counts, payment reconciliation and close controls are operationally accepted.
- Every phase has an entry decision, data/configuration requirement, security tests and an exit demonstration.

## 2. Phase 0 — Architecture and decisions (current phase)

### Deliverables

The twelve required architecture documents in the repository root.

### Review gates

- approve repository/deployment boundary (`web` versus `ops`);
- confirm Supabase environments/project ownership and billing/backup tier;
- approve roles including KDS identity;
- approve order/payment/stock-consumption/daily-close policies;
- obtain owner/accountant decisions listed in finance/schema documents;
- define actual location, devices, network, printers, stations and workflows;
- classify Phase 1 launch scope versus later modules.

### Exit criteria

Written decision register signed off by owner and operational representatives. No feature code is part of Phase 0.

## 3. Phase 1A — Platform, tenancy and security foundation

### Scope

- approved monorepo/separate-repository structure and independent `ops` deployment;
- development, staging and production Supabase projects;
- migration/seed/type-generation pipeline;
- organization/location/profile/employment/roles/permissions/assignments;
- Supabase SSR authentication, session handling and MFA enrollment/challenge;
- RLS, private permission helpers, audit, idempotency and outbox foundations;
- secure headers, logging, error handling, environment secrets and CI checks;
- base authenticated shell designed for tablets/accessibility.

### Exit criteria

- role/scope/RLS test suite proves allow and deny cases;
- staff deactivation and role changes take effect safely;
- owner MFA protects selected test command;
- no service credential exists in client bundles;
- audit and idempotency demonstrations pass;
- staging backup/restore and incident procedure documented.

## 4. Phase 1B — Menu, POS and order core

### Scope

- menu categories/items/variants/modifiers, effective pricing/tax/service rules and availability;
- restaurant tables/sessions needed for dine-in;
- draft/confirm orders for dine-in, takeaway and approved delivery scope;
- trusted pricing, four status dimensions, version conflicts and snapshots;
- discounts/approvals within agreed launch rules;
- configured payments, allocations and receipts;
- cancellation/void/refund paths required for pilot;
- customer basic lookup with minimum data.

### Exit criteria

- end-to-end order totals reproduce in database tests;
- concurrent terminal and retry tests pass;
- completed order/payment ledgers are immutable;
- all role and location boundaries pass;
- receipts match stored transaction snapshots;
- pilot users accept touch/keyboard/error/recovery flows.

## 5. Phase 1C — KDS, fulfillment, tables and operational dashboard

### Scope

- kitchen stations/routing/tickets/events and named operator identity;
- durable queue plus private realtime notification/reconnect resync;
- start/ready/cancel/re-fire/reroute controls;
- dine-in table status and fulfillment handoff;
- takeaway collection and approved delivery states;
- operational dashboard and alerts;
- connection/stale-data indicators.

### Exit criteria

- no ticket loss/duplication under reconnect/retry/concurrency tests;
- every action identifies operator and station;
- order/kitchen/fulfillment rollups pass scenarios;
- station and cross-location RLS tests pass;
- real restaurant devices/network complete a controlled service simulation.

If reliable recipe data is not ready, inventory consumption remains disabled and clearly labelled; it must not post guessed ingredient values.

## 6. Phase 2 — Inventory, recipes and costing

### Scope

- units/conversions, items/storage locations and opening-count migration;
- immutable movements and balance reconciliation;
- goods-receipt stock posting prerequisites;
- recipes/versioning/yield/cost snapshots and menu margin;
- order consumption at approved trigger;
- wastage, counts, adjustments, transfers, reorder/expiry alerts;
- actual-versus-theoretical reporting.

### Entry data

Approved item master, canonical units/conversions, storage areas, opening physical count, recipe formulations/yields, valuation method and cost source.

### Exit criteria

- movement-to-balance reconciliation passes;
- recipe consumption is idempotent and dimensionally valid;
- count concurrency and cancellation dispositions pass;
- owner accepts cost/margin caveats and data-completeness indicators;
- at least one full count-to-variance cycle is piloted.

## 7. Phase 3 — Suppliers and procure-to-pay

### Scope

- supplier master and private documents;
- purchase requests, approvals, POs/amendments;
- partial goods receipts, rejection, lots/expiry and stock posting;
- supplier invoices/credits, three-way match and exceptions;
- supplier payments/allocations and reporting.

### Exit criteria

- request-to-payment audit chain demonstrated;
- duplicate invoice/payment and receipt retry controls pass;
- stock, liability and cash reconcile while remaining separate;
- thresholds, self-approval and changed-destination controls pass.

## 8. Phase 4 — Cash, expenses, daily close and finance reporting

### Scope

- registers/cash sessions/declarations/variance;
- expenses and approvals;
- operational financial events and reconciliation jobs;
- location daily close, exception handling, locks and versioned reopen;
- sales/payment/cash/expense/supplier/food-cost reports;
- external accounting export if approved.

### Exit criteria

- a full business day closes from source transactions without typed revenue;
- provider/cash/order/stock/liability reconciliation checks pass;
- close concurrency/retry/reopen tests pass;
- accountant accepts tax/service/revenue/export definitions;
- owner approves role visibility and thresholds.

## 9. Phase 5 — Reservations, customers and staff operations

### Scope

- reservation conflict/table allocation and lifecycle;
- customer history/consent/deduplication/retention;
- staff schedules, attendance events and corrections;
- approved customer/staff reporting.

Payroll and marketing automation remain separate scope unless explicitly approved.

### Exit criteria

Privacy, retention, export/anonymization, conflict handling and staff access tests pass.

## 10. Phase 6 — Hardening, scale and integrations

Potential scope, prioritized by evidence:

- payment-provider webhooks and settlement imports;
- receipt/kitchen printer integration;
- delivery-provider integration;
- accounting export/API;
- advanced reporting/materialized views;
- multi-location transfers and centralized procurement;
- performance tuning/partitioning;
- PWA enhancements and carefully bounded offline draft support;
- disaster-recovery exercises, penetration test and ongoing access review.

No integration is assumed until provider, ownership, fees, failure modes and data contract are known.

## 11. Cross-phase workstreams

| Workstream | Required throughout |
|---|---|
| Security | Threat model, RLS/command/storage tests, MFA, secret rotation, dependency review |
| Data | Migrations, fixture quality, import validation, lineage, retention, restore drills |
| Quality | Unit/integration/concurrency/browser/device tests and production-like staging |
| Accessibility | Keyboard/touch, focus, readable status, non-color cues, screen sizes |
| Operations | SOPs, training, support runbook, alert ownership, rollback/degraded modes |
| Observability | Correlation IDs, command/realtime/reconciliation metrics, error alerts |
| Change control | Decision log, approvals, release notes, pilot feedback, no undocumented production changes |

## 12. Recommended implementation order inside each vertical slice

1. Confirm operating rule and acceptance scenarios.
2. Add migration, constraints and RLS.
3. Add database command and audit/outbox behavior.
4. Generate types and build server adapter/action.
5. Build the smallest role-aware UI.
6. Test deny paths, state transitions, retries and concurrency.
7. Verify on representative hardware/network.
8. Pilot behind an explicit rollout gate, observe, then widen.

## 13. Test strategy

- schema constraint and migration tests;
- RLS matrix for every table/action/role/scope;
- database command state-machine and idempotency tests;
- concurrent POS/KDS/payment/close simulations;
- provider contract/webhook replay tests;
- Server Action validation/session/MFA tests;
- browser end-to-end journeys for every role;
- accessibility and tablet viewport checks;
- realtime disconnect/reconnect and stale-state tests;
- financial and inventory golden-ledger reconciliation cases;
- backup restore and incident response exercises.

## 14. Launch strategy

1. Configure staging with representative but non-production-sensitive fixtures.
2. Train owner/manager and run scripted service simulations.
3. Run a shadow period where outcomes are compared with current operational records.
4. Pilot one location/register/station set with documented fallback.
5. Reconcile every pilot day; resolve data/operational gaps before expansion.
6. Enable later finance/inventory claims only after their data prerequisites pass.

Rollback means stop new writes and revert application release where safe; it does not delete committed transactions or run destructive schema rollback on production data.

## 15. Phase 0 unresolved inputs

The consolidated open questions in the architecture and domain documents must be answered. Critical blockers for Phase 1A/1B are repository/deployment ownership, location/tax identity, KDS user model, payment methods/providers, role thresholds, receipt/order numbering, order-type rules, device/network constraints and launch-scope prioritization.
