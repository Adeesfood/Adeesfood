# Adee's Food — Purchasing Workflow

**Status:** Phase 0 procure-to-pay proposal
**Principle:** Request, approval, commitment, receipt, invoice and payment are distinct accountable events

## 1. End-to-end lifecycle

```text
Need / low-stock signal
        |
        v
PURCHASE REQUEST -> APPROVAL -> PURCHASE ORDER -> GOODS RECEIPT
                                            |             |
                                            |             +--> accepted stock movement
                                            v
                                    SUPPLIER INVOICE -> MATCH/APPROVAL -> PAYMENT
```

A recommendation is not a request, a request is not a purchase order, a PO is not received stock, an invoice is not a receipt, and payment is not approval. Keeping these events separate enables fraud control and correct stock/finance reporting.

## 2. Supplier master

Supplier records include identity, contacts, tax information, payment terms, status, item/catalog mapping and approved payment details. After transactions exist, archive rather than delete.

Controls:

- normalize/detect duplicate suppliers;
- restrict bank/mobile-money details and audit every change;
- require independent re-verification for payment-detail changes;
- never treat an email/phone request alone as verified payment instruction;
- retain supplier documents in a private Supabase Storage bucket with short-lived access;
- separate supplier activation/payment-detail approval from day-to-day ordering where staff capacity allows.

## 3. Purchase request

### States

`DRAFT -> SUBMITTED -> APPROVED | REJECTED | CANCELLED -> CONVERTED/PARTIALLY_CONVERTED`

### Flow

1. Manager selects requested items, quantities/units, needed date, preferred supplier and justification.
2. System may show on-hand, on-order, usage and reorder recommendation; these are advisory snapshots.
3. Submit freezes a version and estimate.
4. Approval policy checks amount, category and requester/approver separation.
5. Approval records exact payload hash, decision, actor, threshold policy and time.
6. A material edit after approval creates a new version and requires reapproval.

Requests do not affect inventory or supplier liability.

## 4. Purchase order

### States

`DRAFT -> PENDING_APPROVAL -> APPROVED -> ISSUED -> PARTIALLY_RECEIVED -> RECEIVED -> CLOSED`, with `REJECTED` and controlled `CANCELLED` paths.

### Flow

1. Convert approved request lines or create an authorized direct PO.
2. Select supplier and item/supplier purchase units; database converts to canonical quantities.
3. Record unit price, tax, delivery terms, expected date, storage destination and tolerances.
4. Database calculates totals. Approval follows configured thresholds and self-approval rules.
5. Issue allocates a unique PO number and freezes commercial terms.
6. Sending/printing/emailing the PO creates a communication audit event; it does not mean supplier acceptance unless explicitly recorded.

Changes to an issued PO use a versioned amendment with approval. Do not edit the original terms invisibly.

## 5. Goods receipt

### States

`DRAFT -> INSPECTED -> POSTED`, with `CANCELLED` before posting and `REVERSED` only through a linked authorized reversal.

### Flow

1. Receiver identifies PO and supplier delivery reference.
2. For each line record delivered, accepted and rejected quantities, actual unit/pack, condition, lot/expiry, storage destination and exception reason.
3. Database checks cumulative receipt against ordered quantity and tolerance.
4. Over-receipt, unexpected item, expired/short-dated stock or material price difference requires manager approval.
5. Posting creates immutable receipt lines, lots, positive stock movements and cost-basis updates in one transaction.
6. PO becomes partially/fully received according to accepted cumulative quantity.

Rejected quantity never increases stock. A PO may be closed short with a reason and authorization.

## 6. Supplier invoice and three-way match

### States

`DRAFT -> RECORDED -> MATCHED | EXCEPTION -> APPROVED -> PARTIALLY_PAID -> PAID`, plus controlled `DISPUTED`, `CANCELLED` before posting, and linked credit/reversal.

Record supplier invoice number/date/due date, currency, line quantities/prices/tax, document, PO and receipt allocation. A unique supplier/invoice-number constraint and normalized comparison detect duplicates.

Three-way match compares:

1. PO: what was authorized and at what terms;
2. goods receipt: what was actually accepted;
3. invoice: what the supplier asks Adee's to pay.

Tolerance differences may auto-match; exceptions require classification, explanation and approval. Posting creates a supplier liability/financial event but does not alter inventory quantity.

## 7. Supplier payment

### States

`REQUESTED -> APPROVED -> PROCESSING -> SUCCEEDED | FAILED | CANCELLED`, with linked reversal where a settled provider permits it.

Controls:

- allocate payment to approved open invoices;
- enforce supplier currency and open balance;
- bind approval to supplier, payment destination, amount, invoices and method;
- reapprove after any material change;
- require owner/MFA by default for processing, with optional bounded manager policy;
- store provider/bank/mobile-money reference uniquely;
- record cash/bank financial event only on successful settlement;
- reconcile provider statement separately from a typed reference.

Do not store sensitive payment secrets or full banking credentials in general audit payloads.

## 8. Returns and credits

1. Supplier return references item, lot and original goods receipt where possible.
2. Posting creates a negative stock movement and return document.
3. Supplier credit note references invoice/return and reduces liability through an immutable financial event.
4. Refund from supplier is a separate settlement event.
5. Quantity, liability and cash must reconcile but remain separate ledgers.

## 9. Partial and exceptional cases

| Case | Treatment |
|---|---|
| Partial receipt | Post accepted amount; PO stays partially received |
| Over-receipt | Block above tolerance until authorized; approval captured |
| Substitution | New/approved item mapping and price, never relabel original line |
| Damaged goods | Rejected receipt quantity or accepted then wastage only if Adee's takes ownership |
| Invoice before receipt | Record but block match/approval unless approved exception |
| Price variance | Preserve PO and invoice values; classify match exception |
| Duplicate invoice | Block supplier + normalized invoice number; review suspected duplicate |
| PO cancellation after receipt | Prohibited; close remaining quantity or use return/reversal |
| Failed supplier payment | No liability settlement; retain attempt and retry idempotently |

## 10. Segregation of duties

At minimum:

- requester cannot satisfy required independent purchase approval;
- receiver identity is distinct from the supplier and recorded even if same employee requested;
- invoice exception approval and supplier payment approval follow thresholds;
- payment-detail changer cannot approve the first payment to changed details under dual-control policy;
- owner can inspect the full chain and audit evidence.

Small-team reality may mean one manager performs several steps. The system must make that visible and require owner approval for high-risk combinations rather than pretending segregation exists.

## 11. Metrics and reports

- requested/approved/ordered/received/invoiced/paid pipeline;
- supplier on-time delivery and fill rate;
- purchase and invoice price variance;
- rejected/short-dated/damaged quantity;
- unmatched invoices and overdue liabilities;
- spend by supplier/category/item/location;
- purchase-to-receipt and invoice-to-payment cycle time;
- amendments, over-receipts, duplicate attempts and threshold exceptions.

Reports identify currency, business date, status inclusion and source freshness.

## 12. Audit events

Supplier creation/status/payment-detail change; request submit/approve/reject; PO create/amend/approve/issue/cancel/close-short; receipt inspect/post/reverse; invoice record/match/exception/approve/dispute; payment request/approve/process/succeed/fail/reverse; return/credit; every threshold or segregation exception.

## 13. Acceptance criteria

1. A PO or invoice cannot increase on-hand stock; only accepted posted receipt lines can.
2. Retrying receipt/invoice/payment cannot duplicate stock, liability or cash events.
3. Issued PO terms and posted receipts/invoices/payments remain immutable.
4. Partial quantities and allocations cannot exceed source balances without an approved tolerance.
5. Three-way match exceptions are explicit and searchable.
6. Supplier payment uses approved current destination details and unique settlement references.
7. RLS prevents front-of-house and cross-location access to supplier/financial data.

## 14. Decisions required

1. Supply purchase/invoice approval thresholds and tolerances.
2. Confirm supplier payment methods and who can process them.
3. Define whether direct POs without purchase requests are allowed.
4. Define acceptable short-dated/over-delivery/price variance limits.
5. Confirm tax and supplier invoice requirements with an accountant.
6. Decide whether supplier statements and payment reconciliation imports are required.
7. Define retention and verification process for supplier payment details.
