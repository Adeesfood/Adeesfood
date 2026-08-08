# Adee's Food — Finance Model

**Status:** Phase 0 operational-finance proposal
**Boundary:** Restaurant operational subledger and reconciliation; not a replacement for statutory accounting software or professional accounting advice

## 1. Financial truth model

Financial reports are derived from immutable operational events:

- successful customer payments and refunds;
- order subtotal, tax, service charge, discount and delivery-fee snapshots;
- posted expenses and reversals;
- posted supplier invoices, credits and payments;
- stock consumption/wastage/variance cost events;
- cash-session movements and daily-close declarations.

Staff never type "daily revenue" or overwrite a settled amount. Corrections create linked reversals or adjustments under an open financial period.

## 2. Money representation

- `amount_minor bigint` stores signed smallest currency units.
- `currency_code char(3)` stores ISO currency; `GHS` is initial default.
- A row never combines values from different currencies.
- Rates/percentages use basis points or constrained decimal, not floating point.
- Calculation and rounding order is centralized, versioned and covered by golden tests.
- Original, tax, service charge, discount, fee, tender and refund components remain separate.

If multi-currency purchasing is introduced, store original currency/amount, approved exchange rate and functional-currency amount independently.

## 3. Operational subledger

`financial_events` provides a consistent reporting stream. Each entry includes organization/location, business date, event type, source entity, amount/currency, classification, posting timestamp, actor, and optional reversal link.

Representative event types:

| Domain | Events |
|---|---|
| Sales | order revenue, tax payable, service charge, delivery fee, discount/complimentary amount |
| Customer settlement | cash/card/mobile-money/other receipt, payment reversal, refund |
| Cost | recipe consumption, wastage cost, stock count variance |
| Purchasing | supplier invoice liability, supplier credit, supplier payment |
| Expense | expense posting, expense reversal |
| Cash control | opening float, cash sale receipt, paid-in/out, safe drop, cash refund, close variance |

This is a management subledger with balanced/reconcilable classifications. Whether it exports journal lines into an external general ledger is a later integration decision.

## 4. Sales recognition and settlement

Sales and payment are distinct:

- order completion/posting recognizes commercial sale components according to the approved accounting timing;
- successful payment records settlement and method;
- a deposit/prepayment may settle cash before order completion and remains classified separately until earned;
- refund reverses settlement and, under policy, revenue/tax components; it does not erase the sale;
- void/cancellation treatment depends on order/payment/preparation state and is explicit.

The owner/accountant must approve the exact recognition point and Ghana tax/service-charge treatment before financial reports are labelled final.

### Reconciliation equation

For an order:

```text
gross line amount
- item/order discounts
+ tax (if exclusive)
+ service charge
+ delivery/other fee
= order total

successful payment allocations
- successful refunds
= net settled

order total - net settled = amount due
```

Inclusive tax is extracted, not added. The calculation version is snapshotted on the order.

## 5. Payment model

Payment methods are configurable (`CASH`, mobile money, card, transfer, other) and may have a provider. A successful record stores unique provider/reference data, receipt/cash session, actor and idempotency key.

States distinguish `PENDING`, `SUCCEEDED`, `FAILED`, `CANCELLED` and linked `REVERSED`; an unknown provider result stays pending until reconciliation. Typing a transaction reference alone must not be treated as provider confirmation where verification is available.

Mixed tender uses explicit allocations. Refunds trace back to original tender(s); policy must define allocation order and provider constraints for partial refunds.

## 6. Expense model

Expenses are categorized, scoped, evidenced and approved:

1. draft with supplier/payee, date, amount, method, category, description and optional private receipt image;
2. approval based on value/category and self-approval rule;
3. posting creates financial and, for cash, cash-session events;
4. correction uses reversal and replacement.

Inventory purchases normally flow through supplier invoice/receipt rather than a generic expense so stock and liability reconcile. Minor cash purchases may use an approved petty-cash flow that still identifies any inventory received.

## 7. Supplier liability

- Approved posted supplier invoice increases open liability.
- Credit note decreases liability.
- Successful supplier payment allocation decreases open liability.
- Goods receipt changes stock, not liability by itself unless the accountant approves an accrued-receipt model.
- Open supplier balance equals posted invoices minus credits and successful allocations.

The system prevents allocation above invoice/payment balance and flags invoices with unresolved three-way-match exceptions.

## 8. Cash control

Each cash register has one open `cash_session`:

```text
expected closing cash =
  opening float
  + successful cash receipts
  + approved cash paid-ins
  - cash refunds
  - approved cash paid-outs
  - safe drops
```

Staff declare actual cash; the system calculates variance. Policies may hide expected cash until declaration. A variance is not quietly forced to zero; it requires explanation and threshold approval.

Cash sessions feed the location daily close. If Adee's operates no distinct registers/shifts, one controlled daily session may be used initially, but the schema keeps the separation.

## 9. Cost and margin

- Theoretical food cost comes from pinned recipe consumption using movement cost snapshots.
- Wastage and unexplained stock variance are separate loss categories.
- Gross margin report uses net menu revenue minus documented product cost and labels incomplete recipe/cost data.
- Labor, rent, utilities and overhead remain separate operating expenses unless an approved management allocation model is added.
- No report should imply audited profit when key expenses, counts, recipes or provider settlements are missing.

## 10. Financial periods and corrections

Financial periods have `OPEN`, `LOCKED`, or `CLOSED` states.

- Routine posting requires an open business date/period.
- Daily close locks routine operational posting for that date under location policy.
- Owner may reopen with `aal2`, reason and possibly second approval.
- Reopening creates a new close version and preserves the prior close/audit trail.
- Late external settlements post on their true timestamp with a reconciliation link to the original business date; they do not silently rewrite history.

## 11. Core reports

| Report | Primary sources | Required caveats |
|---|---|---|
| Sales summary | Completed/recognized order components | Status, tax basis, timezone |
| Payment reconciliation | Successful payments/refunds/provider settlements | Pending/unknown transactions |
| Cash reconciliation | Cash sessions/movements/declarations | Register/shift coverage |
| Discount/void/refund | Order adjustments and approvals | Gross/net presentation |
| Expense summary | Posted expenses/reversals | Missing receipt/approval flags |
| Supplier aging | Invoices/credits/payment allocations | Disputed/unmatched items |
| Food cost/margin | Recipe consumption/cost snapshots/sales | Incomplete recipes or cost |
| Inventory loss | Wastage/count variance | Valuation method and count freshness |
| Daily close | Derived sales/payments/expenses/cash/exceptions | Close version and reopen status |

Every report shows generated time, business-date timezone, active filters, included statuses, data freshness and export author.

## 12. Security and fraud controls

- Finance views are permission/location scoped through RLS.
- Owners use MFA for role/settings, high-value refunds/payments, exports and period reopen.
- Approval binds exact amount, entity, destination and payload hash.
- Supplier bank/mobile-money changes trigger independent verification and heightened audit.
- Cash, refund, void, discount, expense, supplier payment and close anomalies generate alerts.
- Exports are time-limited, watermarked/identified, audited and exclude unnecessary personal data.
- Secret/provider credentials remain server-side; payment card data is never stored in application tables.

## 13. Reconciliation controls

Scheduled jobs and close checks verify:

1. order total, payment allocation, refunds and due amount agree;
2. successful provider payments reconcile to provider settlement/import where available;
3. cash-session expected formula ties to source transactions;
4. supplier invoice/payment allocations equal liabilities;
5. financial event source exists and is not duplicated;
6. reversals reference compatible originals and net correctly;
7. business dates fall in permitted open/closed periods;
8. inventory cost events tie to stock movements.

## 14. Acceptance criteria

1. Financial totals derive from immutable transactions, not manually entered summaries.
2. Payment/refund retries cannot duplicate settled value.
3. Cash variance remains visible and approved rather than overwritten.
4. Supplier liability, stock receipt and payment remain distinct and reconcile.
5. Historic totals preserve calculation/cost/settings versions.
6. Closed dates reject routine backdated posting.
7. Reports label incomplete or unreconciled data.

## 15. Decisions required from owner/accountant

1. Confirm Ghana tax, inclusive/exclusive pricing, service-charge and receipt requirements.
2. Confirm revenue recognition and cash-vs-accrual reporting expectations.
3. Choose inventory valuation method.
4. Define cash registers, shifts, floats, safe drops and variance thresholds.
5. Define refund/discount/expense/purchasing approval thresholds.
6. Choose external accounting export/integration requirements.
7. Define payment providers, settlement imports and fees.
8. Confirm financial/data retention and period-lock policy.
