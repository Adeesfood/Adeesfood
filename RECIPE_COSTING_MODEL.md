# Adee's Food — Recipe and Costing Model

**Status:** Phase 0 proposal
**Purpose:** Connect every sellable prepared item to reproducible ingredient consumption, food cost and margin without rewriting history

## 1. Recipe structure

A `recipe` is the identity for how a menu item/variant is produced. A `recipe_version` is a specific formulation with:

- version number and lifecycle (`DRAFT`, `PUBLISHED`, `RETIRED`);
- intended output quantity and output unit;
- number/size of sellable portions;
- preparation loss or yield basis;
- ingredient/component lines;
- effective dates and author/approver;
- costing snapshots by location and time.

Draft versions may change. A published version is immutable after use. Changes create a new version; old orders retain the version they consumed.

Each sellable variant that consumes stock pins an active published recipe version when the order is confirmed or when consumption is posted, according to the approved consistency rule. Recommendation: pin at order confirmation so staff see a deterministic requirement and later recipe edits do not change an open order.

## 2. Ingredient lines

Each `recipe_ingredient` specifies:

- inventory item or a prepared component (exactly one);
- entered quantity and recipe unit;
- conversion path to the item's canonical unit;
- whether entered quantity is gross/raw or net/usable;
- optional line-specific yield/waste factor;
- preparation note and sequence, if operationally useful.

Do not bury ingredient quantities in JSON or free text. Free text may supplement but never replace measurable lines.

## 3. Yield conventions

One convention must be selected and displayed clearly:

### Gross-input convention

```text
usable_quantity = gross_quantity × yield_percent
gross_required = desired_usable_quantity / yield_percent
```

### Net-input convention

The stored quantity already represents usable input; the system derives gross purchase consumption using the yield percentage.

Recommendation: store both the entered basis and normalized gross canonical consumption so calculations are explainable. Yield must be greater than 0 and at most 100% unless an explicit production expansion rule (for example hydration) is modeled separately.

## 4. Cost calculation

For each ingredient at a location and costing timestamp:

```text
ingredient_canonical_quantity = scaled recipe quantity after unit/yield conversion
ingredient_cost_minor = ingredient_canonical_quantity × current unit cost

batch_cost_minor = sum(ingredient costs) + packaging cost + configured direct add-ons
portion_cost_minor = batch_cost_minor / sellable portion yield
food_cost_percent = portion_cost_minor / net selling price_minor × 100
gross_margin_minor = net selling price_minor - portion_cost_minor
```

Round only at defined boundaries. Keep intermediate calculations at numeric precision, then round currency totals using one documented rule. Persist input cost references and final values in `recipe_cost_snapshots` so a historic margin can be reproduced.

Tax collected from customers is not menu revenue for margin calculation when it is remitted; service charges and delivery commissions must be classified explicitly with the accountant. Labor and overhead are outside basic ingredient food cost and should appear as separate management metrics rather than being hidden in an ingredient line.

## 5. Cost source

Recommended ingredient cost source is the location's current weighted-average stock cost. Alternatives such as latest purchase price or FIFO cost must be labelled and never mixed silently.

If an ingredient has no valid cost, recipe cost is `INCOMPLETE`, not zero. Publishing or selling may be allowed by configured override, but dashboards and reports must show the missing-data warning.

Cost snapshots should be recalculated when:

- a relevant goods receipt changes average cost;
- a published recipe version changes through replacement;
- packaging/direct add-on cost changes;
- location price changes;
- a manager requests a recomputation.

Recalculation creates a new snapshot; it does not rewrite old snapshots.

## 6. Consumption calculation

At the configured event (recommended: kitchen preparation start):

1. lock the order item and verify it has no active consumption posting;
2. read its pinned published recipe version;
3. scale ingredient gross canonical quantities by ordered/prepared servings;
4. choose storage location/lot using configured rules;
5. create negative stock movements with cost snapshots;
6. write `order_item_consumptions` and financial cost event;
7. update balances, audit and outbox atomically.

For an item prepared in stages/stations, consumption must still post once for the commercial quantity or be explicitly divided across component lines with unique keys. Multiple station tickets must not multiply the recipe.

## 7. Prepared components and nested recipes

Sauces, dough, marinades or other prepared components may need batch production:

1. a component recipe consumes raw inventory;
2. a production batch records actual output/yield;
3. raw inputs post `PRODUCTION_CONSUMPTION`;
4. component output posts `PRODUCTION_OUTPUT` into a tracked component item;
5. menu recipes consume the component item.

This is more accurate than recursively consuming raw ingredients every time when components are prepared and counted in advance. It also adds operational complexity. Adee's must decide whether it is required in the first inventory/recipe release.

Nested recipes must be acyclic; publication checks reject circular component dependencies.

## 8. Version workflow

```text
DRAFT --validate/approve--> PUBLISHED --replacement--> RETIRED
   |                            |
   +---- edit freely            +---- immutable after first use
```

Publication validation:

- menu variant and location applicability are valid;
- output and portions are positive;
- every line has compatible units and valid conversion;
- every ingredient is active and cost status is shown;
- no circular component dependency;
- exactly one active version exists for the effective scope/date;
- publisher has permission and any margin/cost exception approval.

Retiring a version prevents new pins but does not affect open/historic order items already pinned to it.

## 9. Menu pricing and margin governance

The system may recommend, but not automatically impose, a price. For a target food-cost percentage:

```text
suggested_net_price_minor = portion_cost_minor / target_food_cost_percent
```

The recommendation must display assumptions, tax treatment, current price, resulting margin and snapshot time. Price activation is a separate effective-dated, authorized menu command.

Alerts may identify:

- missing costs/conversions/recipes;
- food cost above threshold;
- margin below threshold;
- unusual cost change since prior snapshot;
- actual usage variance vs theoretical recipe consumption;
- menu item sold while recipe unavailable or stale.

## 10. Actual-versus-theoretical analysis

For a period/item:

```text
theoretical usage = sum(posted recipe consumption and other expected movements)
actual usage = opening + receipts + transfers in - closing - transfers out - documented wastage/returns
unexplained variance = actual usage - theoretical usage
```

The report must clearly state whether wastage is included/excluded and identify incomplete recipes, missing counts and negative stock. It must not present false precision where data quality is weak.

## 11. Permissions and audit

- Managers may draft recipes and, within policy, publish versions and view location cost.
- Owners control organization-wide margin thresholds, high-impact publication and full cost exports.
- Receptionists do not see ingredient cost or formulas by default.
- Audit recipe creation, publication, retirement, ingredient/yield change, missing-cost override, price activation and manual recost.

## 12. Acceptance criteria

1. A published recipe used by an order cannot be edited.
2. Consumption quantity is dimensionally valid and posts once per prepared order quantity.
3. Cost snapshots reproduce from stored quantities, conversions and cost sources.
4. Missing cost is visible and never treated as zero without an explicit labelled rule.
5. Multi-station tickets do not duplicate recipe consumption.
6. Cancellation/re-fire outcomes connect to stock reversal or wastage explicitly.
7. Historic margin remains unchanged after a new recipe or receipt cost.

## 13. Decisions required

1. Confirm gross-input vs net-input recipe entry and how Adee's kitchen measures yield.
2. Confirm recipe pin time (recommended: order confirmation).
3. Confirm cost method (recommended: location weighted average).
4. Identify packaging, labor and overhead components required in menu costing.
5. Decide whether prepared-component production batches are required.
6. Set margin/food-cost alert and approval thresholds.
7. Define recipe ownership, testing and sign-off process in the kitchen.
