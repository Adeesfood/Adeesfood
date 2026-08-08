# Adee's Food Restaurant Management System — System Architecture

**Status:** Phase 0 proposal for review
**Scope:** Architecture only; no management features or UI are implemented by this document
**System:** Adee's Food, independent of every other business or codebase

## 1. Current project state

The repository currently contains a public-facing Next.js 16 website deployed on Vercel. It has React, TypeScript, Tailwind CSS, GSAP, static brand assets, and a placeholder menu data file. It does **not** yet contain:

- Supabase configuration, migrations, database tables, Row Level Security (RLS), or generated database types;
- staff authentication, internal management routes, or role enforcement;
- order, kitchen, table, inventory, recipe, purchasing, finance, or reporting modules;
- a reliable transaction, audit, or realtime event model.

The public website must remain operational while the internal restaurant system is introduced. Phase 0 therefore adds documentation only.

## 2. Recommended system boundary

Use one product domain with two independently deployable applications:

| Surface | Purpose | Recommended deployment |
|---|---|---|
| Public website | Brand, menu discovery, contact, future customer ordering | `adeesfood.com` Vercel project |
| Operations application | POS, KDS, tables, inventory, purchasing, finance, reports, settings | `ops.adeesfood.com` separate Vercel project |
| Supabase project | Postgres, Auth, Storage, Realtime, database functions | One production project, with separate development and staging projects |

The operations application should not be placed behind an obscure URL in the public application. A separate deployment limits accidental exposure, reduces release coupling, and allows stricter headers, authentication, monitoring, and rollout controls.

After Phase 0 approval, restructure deliberately into a monorepo rather than moving files piecemeal:

```text
apps/
  web/                 public website
  ops/                 internal restaurant application
packages/
  domain/              shared types, validation, money and unit rules
  database/            generated Supabase types and typed query adapters
  ui/                  intentionally shared, non-domain UI primitives
supabase/
  migrations/          reviewed, immutable SQL migrations
  seed/                development and test fixtures only
  tests/               RLS, constraints, command and concurrency tests
```

No repository restructuring is authorized during Phase 0. If the owner prefers a separate private repository for `ops`, the same application boundaries still apply; that is Decision D-01 below.

## 3. Target architecture

```text
Staff browser / tablet
        |
        | HTTPS + Supabase cookie session
        v
Next.js operations app on Vercel
  - authenticated layouts and route guards
  - Server Components for reads
  - Server Actions / Route Handlers for commands
  - Zod-style input validation
        |
        | user JWT for normal access
        | tightly held server credential only for explicit admin jobs
        v
Supabase
  - Auth: staff identity, session, MFA
  - Postgres: source of truth, RLS, constraints, transactions
  - database command functions: atomic business transitions
  - Realtime: change notification, never the source of truth
  - Storage: receipt and supplier-document objects protected by RLS
        |
        v
Operational projections, reports, alerts and audit history
```

### Architectural responsibilities

| Layer | Responsibility | Must not do |
|---|---|---|
| UI | Present permitted actions, collect input, show connection and command state | Treat a hidden button as security; invent financial totals |
| Route/layout | Require a valid session and provide safe navigation | Replace permission checks in commands or RLS |
| Server command | Validate input, require permission/MFA/approval, invoke one transaction, map errors | Perform multi-step financial or stock mutations without a transaction |
| Postgres | Enforce scope, permissions, constraints, state transitions, idempotency, audit and ledgers | Trust client-computed totals or status values |
| Realtime | Notify subscribed screens that durable state changed | Become the durable order queue |

## 4. Foundational design decisions

### 4.1 Tenancy and location scope

Model `organizations` and `locations` from the first migration, even if Adee's Food begins with one location. Every operational record carries `organization_id`; location-specific records also carry `location_id`. Foreign keys must prevent a row from joining records from different organizations or locations.

This is not premature multi-branch UI. It prevents a future second location from requiring a dangerous rewrite of identity, reporting, inventory, and RLS.

### 4.2 Identity and permissions

- Supabase Auth owns credentials and sessions; `profiles` links one-to-one to `auth.users`.
- Roles and permissions live in normalized application tables.
- Initial primary roles are `RECEPTIONIST`, `MANAGER`, and `OWNER`.
- Assignments are scoped to an organization and, when applicable, a location.
- Authorization is permission-based (`orders.refund`, not `is_manager`) so approval limits can evolve without rewriting every policy.
- Database authorization reads current assignments through a private `has_permission(...)` function. A JWT role claim may speed UI rendering, but cannot be the only authority because claims remain stale until token refresh.
- Owner sessions and sensitive manager actions require Supabase MFA at Authenticator Assurance Level 2 (`aal2`).

Authorization is enforced at four levels:

1. navigation and controls omit actions the user cannot take;
2. authenticated route layouts reject unavailable modules;
3. every Server Action/Route Handler authorizes the exact command and scope;
4. RLS and database command functions provide the final, non-bypassable boundary.

The Supabase secret/service-role credential must never be shipped to a browser. Normal staff commands should retain the user's JWT so RLS can identify the actor. Exceptional server-only jobs using elevated credentials must set an explicit actor/context and write an audit event.

### 4.3 Command/query split

Routine reads may use RLS-protected tables or security-invoker views. Business mutations use named commands such as `submit_order`, `record_payment`, `post_goods_receipt`, or `post_daily_close`.

Each command must:

1. validate actor, permission, location, input and current state;
2. accept a client-generated idempotency key;
3. lock the affected aggregate rows;
4. calculate trusted totals in the database;
5. write the business rows, immutable ledger entries, audit event and outbox event in one transaction;
6. return the committed identifier, version, and resulting status.

This prevents partial orders, double payments, duplicated stock deductions, and unaudited overrides.

### 4.4 Money, time and quantities

- Store money as signed `bigint` minor units plus ISO currency code (`GHS` initially); never use binary floating point.
- Store all timestamps as `timestamptz` in UTC. Derive `business_date` in the location's configured IANA timezone (`Africa/Accra` initially).
- Store inventory quantity and conversion factors as constrained `numeric`, using a canonical base unit per item and a unit dimension (`mass`, `volume`, `count`).
- Store display order numbers separately from UUID primary keys. Generate them in the database, uniquely per location and sequence.
- Snapshot names, prices, rates, recipe versions and costs at transaction time. Historical records must not change when a menu item or recipe is edited later.

### 4.5 Statuses are separate dimensions

An order does not have one overloaded status. It has independent lifecycle dimensions:

- `order_status`: commercial lifecycle;
- `kitchen_status`: preparation lifecycle;
- `payment_status`: settlement lifecycle;
- `fulfillment_status`: handoff/delivery lifecycle.

Transitions occur through commands and append to status history. Clients cannot assign arbitrary status strings.

### 4.6 Immutable ledgers and reversible corrections

Completed payments, stock movements, posted goods receipts, closed periods, and audit events are not edited or deleted. Corrections create linked reversal or adjustment entries with a required reason and authorization. Catalog records are archived, not deleted, once referenced.

### 4.7 Concurrency and retry safety

- Aggregates use an integer `version`; edits require the expected version.
- Critical commands use row locks and constraint-backed uniqueness.
- `idempotency_keys` stores actor, location, command, request hash, result and expiry.
- Duplicate requests with the same key and body return the original result; reuse with a different body is rejected.
- Payment provider references, order numbers, receipt numbers and posting references have unique constraints.

## 5. Supabase-specific security architecture

### Schemas

| Schema | Exposure | Content |
|---|---|---|
| `public` | Supabase Data API, authenticated access only unless explicitly public | RLS-protected business tables and security-invoker read views |
| `private` | Not exposed through Data API | permission helpers, command internals, sensitive configuration, maintenance functions |
| `reporting` | Not exposed initially | materialized/reporting views refreshed by controlled jobs |
| `storage` | Managed by Supabase | object metadata protected with bucket-specific RLS |

All business tables in exposed schemas enable and force RLS. Grants are explicit. Views exposed to staff use `security_invoker = true`; elevated views remain in an unexposed schema.

### RLS policy shape

Every policy combines:

- authenticated identity (`auth.uid()`);
- active staff assignment;
- matching `organization_id` and allowed `location_id`;
- required permission code;
- record-state limitations where needed;
- `aal2` for sensitive owner-level data or commands.

`private.has_permission(permission_code, organization_id, location_id)` is a `stable security definer` function with a fixed empty `search_path`, fully qualified objects, minimal execute grants, and dedicated tests. It is kept out of exposed schemas.

### Storage

Use private buckets such as `supplier-documents`, `expense-receipts`, and `exports`. Object paths begin with organization and location IDs. Storage RLS mirrors application permissions. Signed URLs are short-lived. File type, size, malware-handling policy, and retention are validated before document uploads are enabled.

### Environments and secrets

- Separate Supabase projects for development, staging and production.
- Schema changes move through version-controlled migrations; never make undocumented production-only dashboard edits.
- Vercel environment variables are scoped per project/environment.
- Browser bundles receive only the Supabase URL and publishable key.
- Secret/service keys remain server-side, are rotated, and are never pasted into chat, source control or logs.
- Production data is not copied into development without documented anonymization.

## 6. Realtime and operational resilience

Realtime is used for KDS queues, order state, table occupancy and actionable alerts. Subscribe only to the location/station topics a staff member is authorized to see. Private channels must require authenticated Realtime authorization.

Every realtime payload carries only identifiers, event type, version and timestamp. On receipt—or after reconnection—the client re-queries durable Postgres state. Missing a broadcast therefore causes a temporary stale screen, not a lost order.

The initial release will not claim full offline operation:

- harmless draft entry may be retained locally;
- payment, send-to-kitchen, stock posting and close commands require connectivity;
- the UI shows connection state and prevents unsafe commands while offline;
- retry uses the original idempotency key;
- KDS has a visible stale-data indicator and automatic resynchronization.

## 7. Audit, observability and recovery

`audit_events` is append-only and records actor, acting role, organization/location, command, entity, reason, approval reference, request/correlation ID, timestamp, and redacted before/after snapshots. Database triggers supplement command logging for protected tables; they do not replace domain-specific audit messages.

Minimum observability:

- structured server logs with correlation IDs and no secrets or unnecessary personal data;
- command success/failure/latency metrics;
- alerts for payment mismatches, failed stock postings, duplicate-key conflicts, KDS queue age, close variances and repeated authorization denials;
- error reporting separated by environment;
- Supabase backup/PITR plan appropriate to the selected tier, plus scheduled restore drills;
- an incident runbook covering credential rotation, staff offboarding, payment outage, realtime outage and data restoration.

## 8. Non-functional targets for Phase 1 approval

| Area | Initial target |
|---|---|
| Availability | POS/KDS degraded-state behavior documented; no silent command loss |
| Performance | p95 interactive reads under 1 second on restaurant network; command acknowledgement under 2 seconds excluding external providers |
| KDS freshness | committed order visible within 3 seconds normally; resync after reconnect |
| Accessibility | keyboard-operable core flows, clear focus, non-color status cues, touch targets suitable for tablets |
| Security | RLS tests for every table/role/scope; MFA for owner and high-risk approvals |
| Data integrity | all money/stock transitions transactional and idempotent |
| Recovery | production restore procedure tested before live financial use |
| Auditability | sensitive actions explain who, what, when, where and why |

These are acceptance targets, not current capabilities.

## 9. Decision register

| ID | Decision | Recommendation | Status |
|---|---|---|---|
| D-01 | Repository shape | One monorepo with independently deployed `web` and `ops` apps | Owner approval required |
| D-02 | Operations hostname | `ops.adeesfood.com`, not a hidden public route | Owner approval required |
| D-03 | Database platform | Supabase Postgres/Auth/Storage/Realtime | Confirmed by owner |
| D-04 | Location scope | Organization/location columns from first migration | Proposed |
| D-05 | Mutation style | Transactional database commands plus RLS | Proposed |
| D-06 | Inventory consumption point | Post once when preparation begins | Operational approval required |
| D-07 | KDS identity | Add narrow `KITCHEN_OPERATOR` role or named station users | Unresolved |
| D-08 | Accounting boundary | Operational subledger and reconciliation, not a statutory general ledger | Owner/accountant approval required |
| D-09 | Offline scope | No offline financial or stock posting in initial release | Proposed |

## 10. Unresolved questions before implementation

1. Should the operations app live in this public repository as a monorepo, or in a separate private repository?
2. Will there be one location at launch, and what are its legal name, address, timezone and Ghana tax settings?
3. Do kitchen staff sign in individually, use station accounts, or require a fourth narrow `KITCHEN_OPERATOR` role?
4. Which payment methods and providers are required at launch—cash, mobile money, card, bank transfer—and must payments be provider-verified?
5. Are delivery orders fulfilled internally or handed to third-party couriers? Which delivery statuses are verifiable?
6. At what operational event should ingredients be consumed: send to kitchen, start preparation, or completion? This proposal recommends start preparation.
7. Who may approve discounts, voids, refunds, wastage, purchase orders, expenses and close variances, and at what value thresholds?
8. Is shift-level cash reconciliation required in addition to the location's daily close?
9. What receipt printers, kitchen displays, tablets and network conditions exist on site?
10. Which reports must be accepted by an accountant, and which accounting/tax export format is needed?
11. What personal data retention period and Ghana privacy/legal obligations apply to customers, staff and supplier documents?
12. Are recipes measured from raw yield, cooked yield, or both, and are prepared sub-recipes required at launch?

## 11. Authoritative platform references

- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase custom claims and RBAC](https://supabase.com/docs/guides/api/custom-claims-and-role-based-access-control-rbac)
- [Supabase server-side authentication](https://supabase.com/docs/guides/auth/server-side)
- [Supabase multi-factor authentication](https://supabase.com/docs/guides/auth/auth-mfa)
- [Supabase Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
- [Supabase Realtime Broadcast](https://supabase.com/docs/guides/realtime/broadcast)
- [Supabase Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes)
