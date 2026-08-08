# Adee's Food — Inventory Model

**Status:** Phase 0 stock-control proposal
**Principle:** On-hand quantity is a reproducible result of immutable movements, never a number staff directly overwrite

## 1. Scope and terminology

| Term | Meaning |
|---|---|
| Inventory item | A tracked ingredient, packaging item, beverage or other stock unit |
| Canonical unit | The single base unit in which an item's ledger and balance are stored |
| Purchase unit | Supplier-facing pack/unit converted to the canonical unit |
| Recipe unit | Kitchen measurement converted to the canonical unit |
| Storage location | Physical stock area within a restaurant location |
| Stock movement | Immutable signed change to quantity/value, linked to its source |
| Theoretical stock | Opening balance plus all posted movements |
| Physical count | Observed quantity at a controlled count time |
| Variance | Physical count minus theoretical quantity |

## 2. Item and unit design

Every `inventory_item` defines:

- organization, category, SKU, name and active/archive state;
- canonical unit and unit dimension (`mass`, `volume`, `count`);
- decimal precision and whether fractional quantity is allowed;
- reorder point and optional target/par level by location/storage area;
- whether lot, expiry or serial/pack tracking is required;
- preferred stock-valuation policy and negative-stock policy.

Conversions are explicit, versioned and dimension-safe. Examples such as kilogram to gram or carton to bottle are valid only when the exact factor is configured. A volume-to-mass conversion requires an ingredient-specific conversion and must never be inferred globally.

Changing an item's canonical unit after posted movements is prohibited. A controlled migration must create a new item/version or convert the entire ledger with documented validation.

## 3. Stock ledger

`stock_movements` is immutable and includes:

- organization, restaurant location and storage location;
- inventory item and optional lot;
- signed canonical quantity;
- cost per canonical unit and extended value snapshot;
- movement type;
- source type/id and unique source posting key;
- business date, posted timestamp and actor;
- optional linked original/reversal movement;
- reason and approval reference for manual adjustments.

### Movement types

| Type | Quantity direction | Source |
|---|---:|---|
| `OPENING_BALANCE` | positive/negative | Approved launch/migration count |
| `GOODS_RECEIPT` | positive | Posted accepted receipt line |
| `ORDER_CONSUMPTION` | negative | Recipe consumption at configured trigger |
| `CONSUMPTION_REVERSAL` | positive | Verified unstarted/reusable cancellation |
| `WASTAGE` | negative | Approved wastage record |
| `COUNT_ADJUSTMENT` | positive/negative | Posted physical count variance |
| `TRANSFER_OUT` | negative | Posted stock shipment |
| `TRANSFER_IN` | positive | Confirmed stock receipt |
| `SUPPLIER_RETURN` | negative | Posted return to supplier |
| `MANUAL_ADJUSTMENT` | positive/negative | Exceptional approved correction |
| `PRODUCTION_CONSUMPTION` | negative | Prepared-component batch input, if enabled |
| `PRODUCTION_OUTPUT` | positive | Prepared-component batch yield, if enabled |

`stock_balances` is a transaction-maintained performance projection. It can be rebuilt from movements and is reconciled automatically; applications cannot edit it directly.

## 4. Valuation

Recommended operational valuation is weighted average cost per item/location, updated when accepted receipts post. Each movement stores the cost basis used so historical recipe/wastage/margin reports remain reproducible.

Formula after a receipt, where quantities use the canonical unit:

```text
new_average_cost =
  ((old_quantity × old_average_cost) + (received_quantity × receipt_unit_cost))
  / (old_quantity + received_quantity)
```

Exceptions when old/new quantity is zero or negative must be defined and tested. If the accountant requires FIFO, lot-level FIFO can be adopted; the chosen method must remain consistent for reporting and cannot be switched casually.

Currency conversion is outside the initial model unless suppliers invoice in another currency. If added, store original currency/amount and the approved exchange-rate snapshot separately.

## 5. Operational flows

### 5.1 Goods receipt

Only **accepted** quantities from a posted goods receipt increase on-hand stock. The command validates PO line, conversion, storage location, lot/expiry data, tolerance, cost and duplicate delivery reference; then writes receipt, stock and cost events atomically.

Purchase requests, purchase orders and supplier invoices do not change quantity.

### 5.2 Order consumption

Recommended trigger is the first transition to kitchen `PREPARING`. The pinned recipe version is scaled by servings/quantity, converted to canonical units and posted exactly once. See `RECIPE_COSTING_MODEL.md` and `KITCHEN_WORKFLOW.md`.

### 5.3 Wastage

Staff selects item/recipe/order-item source, quantity/unit, reason category, description and storage location. The server converts and values the loss. Threshold rules may require approval. Posting creates a negative movement and an operational/financial event.

Suggested reason categories: spoilage, expiry, preparation error, overproduction, customer return, damaged delivery, spillage, quality rejection, theft/suspected loss, and other (detail required).

### 5.4 Transfer

A transfer has request, ship and receive states. Shipment posts `TRANSFER_OUT`; destination confirmation posts `TRANSFER_IN`. Differences remain visible as in-transit variance and require resolution. One direct balance-to-balance edit is prohibited.

### 5.5 Supplier return

A posted return references original receipt/lot where possible, creates a negative movement and a supplier credit/financial workflow. Throwing items away uses wastage, not supplier return.

## 6. Stock count workflow

1. Manager defines scope: location, storage area, categories/items and optional lots.
2. System records a frozen movement watermark/time and expected quantities.
3. Counters enter observed quantities without changing the ledger. Blind counts may hide expected quantity to reduce anchoring.
4. System calculates variance quantity and value at a documented cost basis.
5. Required reasons/approvals are collected for thresholds and controlled items.
6. `post_stock_count` locks the count and affected balances, verifies no unhandled movements after the watermark, then creates one `COUNT_ADJUSTMENT` per variance.
7. Count becomes immutable; reports link the adjustment back to count lines.

If sales/receipts continue during the count, the command must roll forward intervening movements or require a recount. It must never compare a stale expected balance with a later physical number silently.

## 7. Reorder and availability alerts

- `on_hand`: current posted balance.
- `reserved`: optional future quantity committed to approved internal production/transfer.
- `available = on_hand - reserved`.
- `on_order`: approved PO quantity not yet accepted.
- `reorder recommendation = max(0, target level - available - on_order)` with pack rounding.

Alerts are advisory and explain their inputs. They do not create or approve a PO automatically. A low-stock menu warning may derive from recipe availability, but a manager decides whether to mark an item unavailable.

Expiry alerts use lot-level dates and configurable warning windows. Stock without trustworthy lot/expiry data must be labelled as such.

## 8. Negative stock and exceptional operations

Recommendation: block movements that make a tracked balance negative. A manager override may be allowed temporarily where stopping kitchen operation is worse, but it must:

- require a specific permission and reason;
- create a high-severity alert;
- preserve the negative ledger honestly;
- trigger count/correction follow-up;
- never fabricate a receipt or opening balance.

Repeated negative stock is a configuration/data-quality problem, not something to hide in reports.

## 9. Permissions and audit

- Receptionist normally sees menu availability, not ingredient balances or costs.
- Manager may count, receive, transfer and post bounded wastage/adjustments.
- Owner controls high-value adjustments, valuation settings, period reopening and full cost reporting.
- Every receipt, count, wastage, transfer, return, adjustment, reversal, unit change and negative-stock override is audited.
- Application roles cannot update/delete movement rows.

## 10. Reconciliation and controls

Scheduled checks should prove:

1. balance projection equals summed movements;
2. every movement source exists and each posting source is unique;
3. order consumption corresponds to pinned recipe quantities;
4. accepted goods receipts equal receipt movements;
5. transfer out/in quantities and states reconcile;
6. wastage and count adjustments have required reasons/approvals;
7. unit dimensions and conversion versions are valid;
8. expired lots and negative balances generate unresolved alerts.

## 11. Acceptance criteria

1. No user can directly type a new on-hand balance.
2. Retrying goods receipt, consumption, count or wastage cannot duplicate stock.
3. Historical movement quantity and cost remain reproducible after catalog/recipe edits.
4. Counts handle concurrent movements explicitly.
5. Every manual variance has an actor, reason, value and approval where required.
6. Cross-location/organization stock access fails under RLS.

## 12. Decisions required

1. Approve weighted-average valuation or request FIFO from the accountant.
2. Identify items requiring lot and expiry tracking.
3. Confirm negative-stock policy and any manager override.
4. Define actual storage locations and stock-count frequency.
5. Define wastage/adjustment approval thresholds.
6. Decide whether transfers between future restaurant locations are needed initially.
7. Decide whether prepared-component production batches are required with recipes.
