# Adee's Food Restaurant Management System — Risk Register

**Status:** Phase 0 initial register
**Scales:** Likelihood (L) and Impact (I) are `Low`, `Medium`, `High`, or `Critical`. Priority should be reviewed before each phase.

## 1. Risk register

| ID | Risk | L | I | Mitigation / control | Trigger / owner |
|---|---|---:|---:|---|---|
| R-01 | RLS or role gap exposes another location's financial, staff or customer data | M | Critical | Default deny; forced RLS; private helpers; full role/scope tests; no browser service key | Any policy change; technical owner |
| R-02 | Service/secret credential leaks through source, browser, logs or chat | M | Critical | Server-only secrets, bundle scan, redaction, rotation runbook, least privilege | Suspected exposure; owner + technical owner |
| R-03 | Public website and operations release become coupled, causing accidental outage/exposure | M | High | Separate app/deployment/hostname; staged migrations; independent rollback | Monorepo/deployment design; technical owner |
| R-04 | A single overloaded order status creates contradictory payment/kitchen/fulfillment behavior | H | High | Four status dimensions, command transitions, history, invariant tests | Any new state/feature; product owner |
| R-05 | Retried or concurrent commands duplicate payments, tickets, receipts or stock | H | Critical | Idempotency keys, unique references, row locks, versions, concurrency tests | Network/provider retry; technical owner |
| R-06 | Realtime message loss causes missed kitchen orders | M | Critical | Postgres source of truth, durable tickets, reconnect query, stale indicator, polling fallback | Realtime/network outage; restaurant manager |
| R-07 | Poor restaurant connectivity blocks service | H | High | Connectivity assessment, degraded UI, safe local drafts only, network redundancy/SOP | Pilot/device test; owner |
| R-08 | Staff share accounts, destroying accountability | H | High | Individual Supabase users, proposed kitchen role, rapid offboarding, session policy, audit | Training/account setup; manager |
| R-09 | Role change/custom JWT remains stale and grants old permissions | M | High | Live database assignment in commands/RLS; JWT claims only for UX; refresh/revoke sessions | Role/offboarding change; technical owner |
| R-10 | Owner/high-risk account takeover enables fraud | M | Critical | Mandatory AAL2, step-up on sensitive actions, alerts, recovery controls | Owner onboarding/security event; owner |
| R-11 | Unit conversion error materially corrupts stock and recipe costs | H | High | Dimension-safe conversions, canonical unit lock, publication validation, test fixtures | Item/recipe setup; inventory lead |
| R-12 | Missing/inaccurate recipes make theoretical stock and margin misleading | H | High | Data-completeness flags, no zero-cost assumption, staged enablement, recipe sign-off | Phase 2 entry; kitchen/owner |
| R-13 | Inventory is consumed twice for multi-station or retried kitchen events | M | Critical | One pinned consumption record/unique key per order quantity; atomic start command | KDS/recipe test; technical owner |
| R-14 | Cancellation silently returns already-prepared ingredients to stock | M | High | Required item disposition; prepared food as wastage/fulfilled-no-charge; audit | Cancel-after-start; manager |
| R-15 | Negative stock is hidden, producing false availability/margin | H | High | Block by default; audited override + alert + count; honest reporting | Consumption/receipt mismatch; inventory lead |
| R-16 | Physical count races with ongoing sales/receipts and posts false variance | M | High | Movement watermark, freeze/roll-forward policy, row locks, recount path | Stock count; manager |
| R-17 | Incorrect valuation or rounding yields unreliable financial reports | M | High | Accountant-approved method, integer money, golden tests, immutable snapshots | Finance design/change; owner/accountant |
| R-18 | Supplier invoice/payment fraud or changed bank/mobile-money destination | M | Critical | Independent verification, dual control, payload-bound approval, AAL2, anomaly alerts | Supplier detail change/payment; owner |
| R-19 | Duplicate supplier invoice or payment | M | High | Normalized unique invoice/reference, idempotency, allocation limits, reconciliation | Invoice/payment entry; finance owner |
| R-20 | PO, receipt and invoice are conflated, misstating stock/liability | M | High | Separate workflows/tables; three-way match; command/invariant tests | Purchasing implementation; manager |
| R-21 | Payment provider timeout is retried as a new charge | M | Critical | Pending/unknown state, provider idempotency/reference, reconciliation before retry | Provider timeout; cashier/manager |
| R-22 | Card or payment secrets are stored improperly | L | Critical | Provider-hosted/tokenized flows; never store card data; server secret controls | Payment integration; technical owner |
| R-23 | Cash variance is overwritten to force a clean close | M | High | Blind declaration, immutable expected/actual/variance, threshold approval/audit | Shift/daily close; manager/owner |
| R-24 | Daily close misses late/concurrent transactions | M | High | Source watermark/version, lock/recompute at submit, unique close, late-event policy | Close posting; manager |
| R-25 | Reopening a day rewrites historical reports without visibility | L | Critical | Owner AAL2, reason/approval, versioned supersession, downstream alert/export lineage | Reopen request; owner |
| R-26 | Ghana tax/service-charge/receipt treatment is wrong | M | Critical | Accountant/legal validation before final reporting; effective-dated settings; golden cases | Phase 1B/4 gates; owner/accountant |
| R-27 | Reports present incomplete recipe, count or settlement data as precise profit | H | High | Freshness/completeness warnings, status filters, reconciliation gates, clear non-GL boundary | Report release; product/finance owner |
| R-28 | Customer/staff personal data is over-collected or retained unlawfully | M | High | Data minimization, privacy/retention policy, access/export audit, anonymization workflow | Schema/form/export design; owner/privacy lead |
| R-29 | Uploaded receipt/supplier document exposes malware or sensitive data | M | High | Private buckets/RLS, file allow-list/limits, scanning policy, short URLs, retention | Upload feature; technical owner |
| R-30 | Audit data can be altered, deleted or contains secrets | L | Critical | Append-only permissions/triggers, restricted exports, redacted snapshots, retention/backup | Audit schema/log review; security owner |
| R-31 | Backup exists but cannot be restored in a service emergency | M | Critical | Correct Supabase tier, documented PITR/backup, scheduled staging restore drill | Before live finance; owner + technical owner |
| R-32 | Production dashboard changes bypass migrations and cause schema drift | M | High | Migration-only policy, drift check, limited admin access, change audit | Every release; technical owner |
| R-33 | Migration or deployment breaks public site or live POS | M | Critical | Independent apps, backward-compatible expand/migrate/contract, staging, canary/pilot, rollback | Release; technical owner |
| R-34 | Hardware/printer/browser incompatibility interrupts service | H | Medium | Inventory actual devices, browser/print prototype, fallback receipt/KDS SOP | Phase 1 pilot; operations owner |
| R-35 | Accessibility/touch design slows or excludes staff | M | High | Representative-user testing, keyboard/touch targets, non-color cues, readable states | UI acceptance; product owner |
| R-36 | Requirements expand into every module before core POS is safe | H | High | Architecture gates, phased vertical slices, explicit backlog/non-goals, exit criteria | Scope review; owner/product owner |
| R-37 | Staff resist workflow or use side channels, degrading data accuracy | H | High | Co-design, training, fast flows, shadow pilot, SOPs, feedback and metric review | Pilot; restaurant manager |
| R-38 | Opening stock/customer/supplier import is inaccurate or duplicated | M | High | Templates, dry-run validation, reconciliation totals, dedupe, signed import report | Data migration; data owner |
| R-39 | One-location shortcuts prevent expansion or leak cross-branch data | M | High | Org/location from first migration, composite FKs, scope tests; no premature multi-branch UI | Schema review; technical owner |
| R-40 | Delivery statuses/fees are trusted without provider evidence | M | Medium | Staff-reported label, explicit provider events, separate fee rules, reconciliation | Delivery scope; operations owner |
| R-41 | Allergen data is incomplete but shown as authoritative | M | Critical | Defined data owner/review process, strong disclaimer/block until verified, version/audit | Menu/KDS design; owner/kitchen lead |
| R-42 | Shared/long-lived device sessions expose owner powers | H | High | Short idle timeout/lock, role-specific devices, step-up MFA, no saved owner session on KDS/POS | Device setup; owner/manager |
| R-43 | An elevated server job bypasses RLS without actor context | M | Critical | Narrow server jobs, private command API, explicit actor/correlation, audit and secret review | Background/admin feature; technical owner |
| R-44 | Supabase plan/quotas, region or Realtime limits are chosen without load evidence | M | High | Capacity/cost review, staging load test, monitoring/alerts, scaling plan | Before pilot/expansion; owner + technical owner |
| R-45 | Vendor lock-in or outage blocks data access | L | High | Standard Postgres schema/migrations, documented exports/backups, degraded SOP, provider exit plan | Annual architecture review; owner |

## 2. Highest-priority treatment before Phase 1 pilot

The pilot must not begin until adequate controls exist for:

- R-01/R-02/R-09/R-10/R-42/R-43: identity, secrets, RLS, MFA and device sessions;
- R-05/R-06/R-07/R-21: retry, concurrency, durable KDS and connectivity/payment failure;
- R-26: accountant-approved tax, service-charge and receipt rules;
- R-31/R-33: restore and deployment safety;
- R-34/R-35/R-37: actual restaurant devices, usability, training and fallback.

Inventory/recipe/finance accuracy claims remain disabled until the corresponding Phase 2–4 risks and data prerequisites are treated.

## 3. Risk governance

- Owner assigns a named risk owner and due phase for every High/Critical risk.
- Review this register at each phase gate and after any incident, provider/infrastructure change, new location or sensitive feature.
- Accepted risk includes rationale, approver, review date and expiry; it is not silently left open.
- Mitigations must become test cases, alerts, operating procedures or contractual checks—not remain prose only.
- Closed risk retains history and evidence.

## 4. Immediate open risk decisions

1. Repository privacy/deployment separation for the operations app.
2. Supabase project ownership, region, paid backup/PITR capability and recovery responsibility.
3. Kitchen user identity and shared-device session policy.
4. Actual network, tablets, printers and backup connectivity.
5. Payment providers and their idempotency/webhook/settlement behavior.
6. Accountant-approved Ghana financial rules.
7. Personal-data/privacy, file-retention and allergen governance.
8. Approval thresholds and segregation possible with Adee's actual staff count.
