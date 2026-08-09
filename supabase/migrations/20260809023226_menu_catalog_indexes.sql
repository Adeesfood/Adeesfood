-- Cover catalog foreign keys used by joins, deletes, and tenant-scoped queries.

begin;

create index menu_items_scope_idx
  on public.menu_items (organization_id, location_id);
create index menu_items_category_fk_idx
  on public.menu_items (category_id);
create index menu_items_created_by_idx
  on public.menu_items (created_by);

create index order_items_scope_idx
  on public.order_items (organization_id, location_id);
create index order_items_menu_item_idx
  on public.order_items (menu_item_id);

create index menu_item_categories_scope_idx
  on public.menu_item_categories (organization_id, location_id);
create index menu_item_categories_created_by_idx
  on public.menu_item_categories (created_by);

create index menu_item_variants_scope_idx
  on public.menu_item_variants (organization_id, location_id);
create index menu_item_variants_created_by_idx
  on public.menu_item_variants (created_by);

create index modifier_groups_scope_idx
  on public.modifier_groups (organization_id, location_id);
create index modifier_groups_created_by_idx
  on public.modifier_groups (created_by);

create index modifier_options_scope_idx
  on public.modifier_options (organization_id, location_id);
create index modifier_options_created_by_idx
  on public.modifier_options (created_by);

create index menu_item_modifier_groups_scope_idx
  on public.menu_item_modifier_groups (organization_id, location_id);
create index menu_item_modifier_groups_created_by_idx
  on public.menu_item_modifier_groups (created_by);

create index order_item_modifiers_scope_idx
  on public.order_item_modifiers (organization_id, location_id);
create index order_item_modifiers_group_idx
  on public.order_item_modifiers (modifier_group_id);
create index order_item_modifiers_option_idx
  on public.order_item_modifiers (modifier_option_id);

commit;
