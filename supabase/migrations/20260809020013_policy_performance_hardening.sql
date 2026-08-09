-- Keep read and write policies disjoint so PostgreSQL evaluates only the
-- permission expression relevant to the requested operation.

drop policy inventory_categories_write on public.inventory_categories;
create policy inventory_categories_insert on public.inventory_categories for insert to authenticated
with check (private.has_permission('inventory.manage_items_units', organization_id, location_id));
create policy inventory_categories_update on public.inventory_categories for update to authenticated
using (private.has_permission('inventory.manage_items_units', organization_id, location_id))
with check (private.has_permission('inventory.manage_items_units', organization_id, location_id));

drop policy inventory_items_write on public.inventory_items;
create policy inventory_items_insert on public.inventory_items for insert to authenticated
with check (private.has_permission('inventory.manage_items_units', organization_id, location_id));
create policy inventory_items_update on public.inventory_items for update to authenticated
using (private.has_permission('inventory.manage_items_units', organization_id, location_id))
with check (private.has_permission('inventory.manage_items_units', organization_id, location_id));

drop policy recipes_write on public.recipes;
create policy recipes_insert on public.recipes for insert to authenticated
with check (private.has_permission('recipes.create_draft', organization_id, location_id));
create policy recipes_update on public.recipes for update to authenticated
using (private.has_permission('recipes.create_draft', organization_id, location_id))
with check (private.has_permission('recipes.create_draft', organization_id, location_id));
create policy recipes_delete on public.recipes for delete to authenticated
using (private.has_permission('recipes.create_draft', organization_id, location_id));

drop policy recipe_ingredients_write on public.recipe_ingredients;
create policy recipe_ingredients_insert on public.recipe_ingredients for insert to authenticated
with check (private.has_permission('recipes.create_draft', organization_id, location_id));
create policy recipe_ingredients_update on public.recipe_ingredients for update to authenticated
using (private.has_permission('recipes.create_draft', organization_id, location_id))
with check (private.has_permission('recipes.create_draft', organization_id, location_id));
create policy recipe_ingredients_delete on public.recipe_ingredients for delete to authenticated
using (private.has_permission('recipes.create_draft', organization_id, location_id));

drop policy suppliers_write on public.suppliers;
create policy suppliers_insert on public.suppliers for insert to authenticated
with check (private.has_permission('suppliers.manage', organization_id, location_id));
create policy suppliers_update on public.suppliers for update to authenticated
using (private.has_permission('suppliers.manage', organization_id, location_id))
with check (private.has_permission('suppliers.manage', organization_id, location_id));

drop policy staff_shifts_write on public.staff_shifts;
create policy staff_shifts_insert on public.staff_shifts for insert to authenticated
with check (private.has_permission('staff.manage_shifts_attendance', organization_id, location_id));
create policy staff_shifts_update on public.staff_shifts for update to authenticated
using (private.has_permission('staff.manage_shifts_attendance', organization_id, location_id))
with check (private.has_permission('staff.manage_shifts_attendance', organization_id, location_id));

drop policy operational_settings_write on public.operational_settings;
create policy operational_settings_insert on public.operational_settings for insert to authenticated
with check (
  private.has_permission('settings.manage_location', organization_id, location_id)
  or private.has_permission('settings.manage_financial_security', organization_id, location_id)
);
create policy operational_settings_update on public.operational_settings for update to authenticated
using (
  private.has_permission('settings.manage_location', organization_id, location_id)
  or private.has_permission('settings.manage_financial_security', organization_id, location_id)
)
with check (
  private.has_permission('settings.manage_location', organization_id, location_id)
  or private.has_permission('settings.manage_financial_security', organization_id, location_id)
);
