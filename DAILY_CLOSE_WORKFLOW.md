# Adee's Food — Daily Close Workflow

**Status:** Phase 0 close-and-reconciliation proposal
**Goal:** Produce a reproducible, approved business-day snapshot without hiding unsettled transactions or variances

## 1. Close hierarchy

Recommended design:

1. individual cash register/shift sessions are declared and closed;
2. the manager prepares one location `daily_close` for the location's `business_date`;
3. the owner may review, lock or exceptionally reopen it.

This supports one register now and multiple registers later. If operations use no shifts, the single cash session still feeds the same daily close.

## 2. Preconditions

The close screen shows readiness checks, not just a submit button:

- current business date and timezone are explicit;
- all staff/register sessions accounted for;
- open orders, unpaid balances and unfulfilled orders listed;
- KDS queued/preparing tickets listed;
- pending/unknown electronic payments listed;
- cash declarations completed;
- refunds/voids/discount approvals complete;
- goods receipts, expenses and supplier payments for the date have posting status;
- critical ledger/reconciliation jobs have no failures;
- previous close/reopen state is known.

Blocking versus warning exceptions must be configured and displayed separately.

## 3. Cash-session close

1. Cashier stops new activity on the register or hands it over under a controlled process.
2. System computes expected cash from opening float and immutable cash movements.
3. Under blind-count policy, cashier enters actual denominations/total before expected cash is revealed.
4. System calculates variance.
5. Cashier explains nonzero variance and submits.
6. Manager approves according to threshold; large variance may require owner.
7. Session closes and is no longer available for routine cash entries.

Reopening a cash session follows the same exceptional versioned process as daily close; it never erases the original declaration.

## 4. Daily-close calculation

`prepare_daily_close` derives a draft snapshot from source transactions up to a movement watermark:

| Section | Derived values |
|---|---|
| Orders | opened, completed, cancelled, voided; gross/net sales; tax/service/delivery/discount |
| Payments | successful payments, refunds and net by method; pending/unknown list |
| Cash | expected/declared/variance by register/session and movement category |
| Kitchen/service | open orders/tickets, late tickets, cancellations after start |
| Discounts/control | manual discounts, complimentary items, voids, refunds and approvals |
| Expenses | posted expenses and cash impact |
| Purchasing | receipts/invoices/payments posted that day, unmatched exceptions |
| Inventory | consumption, wastage, manual adjustments, negative stock and failed postings |
| Finance | net operational inflow/outflow and reconciliation differences |

The snapshot records the source watermark/query version. Staff enter only declarations and explanations, not source totals.

## 5. Exception policy

### Recommended blockers

- payment total/order allocation inconsistency;
- unresolved successful-or-unknown electronic payment affecting settlement;
- open cash session;
- failed stock or financial posting;
- unauthorized void/refund/discount;
- duplicate settlement/source reference;
- another close already current for the same location/date;
- database reconciliation mismatch.

### Configurable warnings

- intentionally open order carried into next service period;
- minor approved cash variance;
- late but non-financial KDS ticket;
- low/negative stock override already assigned for follow-up;
- unmatched invoice not due for daily settlement.

Warnings require acknowledgment/comment. Blockers must be resolved or converted through a specific owner-approved exception command; a generic "ignore" is prohibited.

## 6. Submit and post

### Manager submit

`submit_daily_close`:

1. locks location/date close and source watermark;
2. recalculates totals to detect activity since preparation;
3. rejects stale drafts and unresolved blockers;
4. records declarations, explanations and manager identity;
5. sets `SUBMITTED`.

### Final post

`post_daily_close`:

1. checks permission, thresholds, approval and version;
2. recalculates or verifies the frozen source set;
3. persists the immutable summary and payment lines;
4. marks the close `CLOSED`;
5. locks routine posting for the date under location policy;
6. writes audit/outbox events and generates a close report reference.

The exact owner-vs-manager post rule is a decision. Recommendation: manager may post when all variances are within owner-set thresholds; owner approval is required otherwise.

## 7. Reopen and correction

Only the owner with current `aal2` may request/perform reopen, subject to optional second approval.

1. Select the closed date/version and enter a specific reason.
2. System identifies affected downstream reports/exports and requires acknowledgement.
3. Preserve original close as immutable; mark its lineage appropriately.
4. Open a bounded correction window and record authorized corrections as reversals/replacements.
5. Recalculate a new close version.
6. Post new close; mark prior version `SUPERSEDED`, never deleted.
7. Alert/report clearly that the date was reopened and why.

Do not reopen merely to make a variance disappear. The correction must point to source evidence.

## 8. Cross-midnight and late events

- `business_date` is derived from location timezone and configured trading-day cutoff, not device clock.
- Orders retain their assigned business date across midnight according to policy.
- Provider callbacks record actual event time and reference the original order/business date.
- If a callback arrives after close, it posts to the permitted current period with a reconciliation link; it does not silently modify a locked date.
- Future clock/cutoff changes are effective-dated.

The owner must approve the trading-day cutoff rule before implementation.

## 9. Outputs

The daily-close report contains:

- organization/location, business date/timezone, close version/status;
- prepared/submitted/closed/reopened actors and timestamps;
- sales/tax/service/discount/refund totals;
- payment method and cash-session reconciliation;
- expenses/supplier cash events as included by policy;
- open/exception lists and explanations;
- inventory wastage/variance/negative-stock highlights;
- source watermark and report-generation time;
- owner/accountant notes and export history.

Reports and exports come from the closed snapshot and linked details, with sensitive personal data excluded.

## 10. Alerts and follow-up

Close can create assigned follow-up alerts for:

- cash variance investigation;
- unknown/pending provider transaction;
- open order/ticket;
- high discount/refund/void activity;
- failed stock consumption;
- negative stock or unexplained adjustment;
- purchasing/invoice exception;
- repeat reopen behavior.

Resolving an alert requires evidence/comment and does not rewrite the close.

## 11. Permissions and audit

- Receptionist closes/declares only own assigned cash session.
- Manager prepares close, reviews exceptions and posts within configured limits.
- Owner views all locations, approves large exceptions and is the only default role that can reopen.
- Audit every declaration, variance explanation/approval, stale close attempt, exception resolution, submit, post, export and reopen.

## 12. Failure behavior

| Failure | Required response |
|---|---|
| New transaction during preparation | Version/watermark mismatch; refresh draft |
| Network loss on post | Retry same idempotency key; query close status |
| Partial command concern | Database transaction commits all or nothing |
| Provider unavailable | Pending payments remain blockers or explicit approved exception |
| Reconciliation job fails | Block close; do not trust stale totals |
| Printer/export fails | Close remains posted; regenerate output later |
| Duplicate post | Unique current-close/idempotency constraint returns original result |

## 13. Acceptance criteria

1. Expected totals reproduce from underlying immutable transactions.
2. A manager cannot type over sales/payment/cash expectations.
3. New activity invalidates a stale prepared close.
4. Blocking discrepancies prevent ordinary close.
5. Retry cannot create multiple current closes.
6. Reopen preserves original version, actor, reason and downstream impact.
7. Cross-midnight and late-provider events follow a documented business-date policy.
8. RLS prevents other locations and Receptionists from viewing/posting daily-close finance.

## 14. Decisions required

1. Define business-day cutoff and timezone (proposed `Africa/Accra`).
2. Define registers/shifts and blind cash-count policy.
3. Set manager variance/exception post thresholds.
4. Confirm whether owner reviews every close or only exceptions.
5. Define treatment of intentionally open orders across days.
6. Define late payment-provider settlement and fee reconciliation.
7. Confirm accountant-required daily report and export fields.
