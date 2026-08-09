-- Adee's Food structured menu catalog and initial production seed.
-- Prices are stored in pesewas. Source ambiguities are preserved as notes.

begin;

alter table public.menu_items
  add column source_notes text,
  add column is_price_from boolean not null default false;

create table public.menu_item_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  category_id uuid not null references public.menu_categories(id) on delete cascade,
  is_primary boolean not null default false,
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (menu_item_id, category_id)
);

create unique index menu_item_categories_one_primary_idx
  on public.menu_item_categories (menu_item_id)
  where is_primary;
create index menu_item_categories_category_idx
  on public.menu_item_categories (category_id, menu_item_id);

create table public.menu_item_variants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  code text not null check (length(btrim(code)) between 1 and 32),
  name text check (name is null or length(btrim(name)) between 1 and 80),
  price_minor bigint not null check (price_minor >= 0),
  currency_code text not null default 'GHS' check (currency_code ~ '^[A-Z]{3}$'),
  sort_order integer not null default 0,
  is_default boolean not null default false,
  is_available boolean not null default true,
  is_active boolean not null default true,
  source_notes text,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (menu_item_id, code)
);

create unique index menu_item_variants_one_default_idx
  on public.menu_item_variants (menu_item_id)
  where is_default and is_active;
create index menu_item_variants_item_idx
  on public.menu_item_variants (menu_item_id, is_active, is_available, sort_order);

create table public.modifier_groups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  code text not null check (length(btrim(code)) between 2 and 40),
  name text not null check (length(btrim(name)) between 2 and 100),
  selection_type text not null check (selection_type in ('SINGLE', 'MULTIPLE')),
  min_selections integer not null default 0 check (min_selections >= 0),
  max_selections integer not null default 1 check (max_selections > 0),
  is_required boolean not null default false,
  source_notes text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (location_id, code),
  check (min_selections <= max_selections),
  check ((selection_type = 'SINGLE' and max_selections = 1) or selection_type = 'MULTIPLE'),
  check ((is_required and min_selections > 0) or not is_required)
);

create table public.modifier_options (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  modifier_group_id uuid not null references public.modifier_groups(id) on delete cascade,
  code text not null check (length(btrim(code)) between 1 and 40),
  name text not null check (length(btrim(name)) between 1 and 100),
  price_delta_minor bigint not null default 0,
  currency_code text not null default 'GHS' check (currency_code ~ '^[A-Z]{3}$'),
  sort_order integer not null default 0,
  is_available boolean not null default true,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (modifier_group_id, code)
);

create index modifier_options_group_idx
  on public.modifier_options (modifier_group_id, is_active, is_available, sort_order);

create table public.menu_item_modifier_groups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  modifier_group_id uuid not null references public.modifier_groups(id) on delete cascade,
  sort_order integer not null default 0,
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (menu_item_id, modifier_group_id)
);

create index menu_item_modifier_groups_group_idx
  on public.menu_item_modifier_groups (modifier_group_id, menu_item_id);

alter table public.order_items
  add column menu_item_variant_id uuid references public.menu_item_variants(id) on delete restrict,
  add column variant_name text;

create index order_items_variant_idx
  on public.order_items (menu_item_variant_id)
  where menu_item_variant_id is not null;

create table public.order_item_modifiers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  order_item_id uuid not null references public.order_items(id) on delete restrict,
  modifier_group_id uuid not null references public.modifier_groups(id) on delete restrict,
  modifier_option_id uuid not null references public.modifier_options(id) on delete restrict,
  group_name text not null,
  option_name text not null,
  price_delta_minor bigint not null,
  created_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (order_item_id, modifier_option_id)
);

create index order_item_modifiers_order_item_idx
  on public.order_item_modifiers (order_item_id);

create trigger menu_item_variants_touch_version before update on public.menu_item_variants
for each row execute function private.touch_versioned_row();
create trigger modifier_groups_touch_version before update on public.modifier_groups
for each row execute function private.touch_versioned_row();
create trigger modifier_options_touch_version before update on public.modifier_options
for each row execute function private.touch_versioned_row();

create trigger menu_item_categories_audit after insert or update or delete on public.menu_item_categories
for each row execute function private.audit_row_change();
create trigger menu_item_variants_audit after insert or update or delete on public.menu_item_variants
for each row execute function private.audit_row_change();
create trigger modifier_groups_audit after insert or update or delete on public.modifier_groups
for each row execute function private.audit_row_change();
create trigger modifier_options_audit after insert or update or delete on public.modifier_options
for each row execute function private.audit_row_change();
create trigger menu_item_modifier_groups_audit after insert or update or delete on public.menu_item_modifier_groups
for each row execute function private.audit_row_change();

alter table public.menu_item_categories enable row level security;
alter table public.menu_item_variants enable row level security;
alter table public.modifier_groups enable row level security;
alter table public.modifier_options enable row level security;
alter table public.menu_item_modifier_groups enable row level security;
alter table public.order_item_modifiers enable row level security;

alter table public.menu_item_categories force row level security;
alter table public.menu_item_variants force row level security;
alter table public.modifier_groups force row level security;
alter table public.modifier_options force row level security;
alter table public.menu_item_modifier_groups force row level security;
alter table public.order_item_modifiers force row level security;

create policy menu_item_categories_select on public.menu_item_categories for select to authenticated
using (private.has_permission('menu.view_internal', organization_id, location_id));
create policy menu_item_categories_insert on public.menu_item_categories for insert to authenticated
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy menu_item_categories_update on public.menu_item_categories for update to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id))
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy menu_item_categories_delete on public.menu_item_categories for delete to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id));

create policy menu_item_variants_select on public.menu_item_variants for select to authenticated
using (private.has_permission('menu.view_internal', organization_id, location_id));
create policy menu_item_variants_insert on public.menu_item_variants for insert to authenticated
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy menu_item_variants_update on public.menu_item_variants for update to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id))
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy menu_item_variants_delete on public.menu_item_variants for delete to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id));

create policy modifier_groups_select on public.modifier_groups for select to authenticated
using (private.has_permission('menu.view_internal', organization_id, location_id));
create policy modifier_groups_insert on public.modifier_groups for insert to authenticated
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy modifier_groups_update on public.modifier_groups for update to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id))
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy modifier_groups_delete on public.modifier_groups for delete to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id));

create policy modifier_options_select on public.modifier_options for select to authenticated
using (private.has_permission('menu.view_internal', organization_id, location_id));
create policy modifier_options_insert on public.modifier_options for insert to authenticated
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy modifier_options_update on public.modifier_options for update to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id))
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy modifier_options_delete on public.modifier_options for delete to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id));

create policy menu_item_modifier_groups_select on public.menu_item_modifier_groups for select to authenticated
using (private.has_permission('menu.view_internal', organization_id, location_id));
create policy menu_item_modifier_groups_insert on public.menu_item_modifier_groups for insert to authenticated
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy menu_item_modifier_groups_update on public.menu_item_modifier_groups for update to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id))
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy menu_item_modifier_groups_delete on public.menu_item_modifier_groups for delete to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id));

create policy order_item_modifiers_select on public.order_item_modifiers for select to authenticated
using (private.has_permission('orders.view', organization_id, location_id));

grant select, insert, update, delete on
  public.menu_item_categories,
  public.menu_item_variants,
  public.modifier_groups,
  public.modifier_options,
  public.menu_item_modifier_groups
to authenticated;
grant select on public.order_item_modifiers to authenticated;

do $$
declare
  v_organization_id uuid;
  v_location_id uuid;
  v_owner_id uuid;
begin
  select o.id, l.id, p.id
  into v_organization_id, v_location_id, v_owner_id
  from public.organizations o
  join public.locations l on l.organization_id = o.id and l.is_active
  join public.profiles p on p.is_active
  join auth.users u on u.id = p.id and lower(u.email) = 'adeesfoods1@gmail.com'
  where lower(o.trading_name) in ('adees food', 'adee''s food')
  order by (l.name = 'Main Branch') desc, l.created_at
  limit 1;

  if v_organization_id is null or v_location_id is null or v_owner_id is null then
    raise exception 'Adee''s Food organization, active location, or owner profile was not found';
  end if;

  insert into public.menu_categories (
    organization_id, location_id, name, description, sort_order, is_active, created_by
  ) values
    (v_organization_id, v_location_id, 'APPETISER', null, 10, true, v_owner_id),
    (v_organization_id, v_location_id, 'BREAKFAST', null, 20, true, v_owner_id),
    (v_organization_id, v_location_id, 'SHAWARMA', null, 30, true, v_owner_id),
    (v_organization_id, v_location_id, 'BURGER', null, 40, true, v_owner_id),
    (v_organization_id, v_location_id, 'MAINS', null, 50, true, v_owner_id),
    (v_organization_id, v_location_id, 'LOCALS', null, 60, true, v_owner_id),
    (v_organization_id, v_location_id, 'NOODLES & PASTA', null, 70, true, v_owner_id),
    (v_organization_id, v_location_id, 'GRILLS', null, 80, true, v_owner_id),
    (v_organization_id, v_location_id, 'GRAVIES', 'Served with any side dish of your choice', 90, true, v_owner_id),
    (v_organization_id, v_location_id, 'SIDE DISH', null, 100, true, v_owner_id),
    (v_organization_id, v_location_id, 'PASTRIES', null, 110, true, v_owner_id),
    (v_organization_id, v_location_id, 'PIZZA', null, 120, true, v_owner_id),
    (v_organization_id, v_location_id, 'SALAD BAR', null, 130, true, v_owner_id),
    (v_organization_id, v_location_id, 'SANDWICH', null, 140, true, v_owner_id)
  on conflict (location_id, name) do update set
    description = excluded.description,
    sort_order = excluded.sort_order,
    is_active = true;

  with seed(sku, category_name, name, description, price_minor, station, source_notes, is_price_from) as (
    values
      ('APP-STIR-VEG', 'APPETISER', 'Stir Fry Vegetables', null, 5000, 'MAIN KITCHEN', null, false),
      ('APP-SPICY-GIZZARD', 'APPETISER', 'Spicy Gizzard', null, 4000, 'MAIN KITCHEN', null, false),
      ('APP-SAUTE-POTATO', 'APPETISER', 'Sauté Potatoes', null, 5000, 'MAIN KITCHEN', null, false),
      ('APP-CRISPY-CHICKEN', 'APPETISER', 'Crispy Fried Chicken', null, 5000, 'MAIN KITCHEN', null, false),
      ('APP-BEEF-SAUSAGE', 'APPETISER', 'Beef Sausage', null, 4000, 'MAIN KITCHEN', null, false),
      ('APP-CRISPY-SHRIMP', 'APPETISER', 'Crispy Shrimps (5 pcs)', null, 10000, 'MAIN KITCHEN', null, false),
      ('APP-CALAMARI', 'APPETISER', 'Deep Fried Calamari', null, 11000, 'MAIN KITCHEN', null, false),
      ('APP-FISH-CHIPS', 'APPETISER', 'Fish and Chips', null, 10000, 'MAIN KITCHEN', null, false),
      ('APP-KELEWELE', 'APPETISER', 'Kelewele', null, 3000, 'MAIN KITCHEN', null, false),
      ('APP-SPRING-ROLL', 'APPETISER', 'Spring Rolls', null, 500, 'MAIN KITCHEN', 'Confirm whether GH₵5 is per piece.', false),
      ('APP-SAMOSA', 'APPETISER', 'Samosa', null, 500, 'MAIN KITCHEN', 'Confirm whether GH₵5 is per piece.', false),

      ('BRK-TEA-BREAD-EGG', 'BREAKFAST', 'Tea with Bread and Egg', null, 2000, 'MAIN KITCHEN', null, false),
      ('BRK-TEA-BREAD-MILK-EGG', 'BREAKFAST', 'Tea with Bread, Milk and Egg', null, 2500, 'MAIN KITCHEN', null, false),
      ('BRK-WHEAT-BREAD-EGG', 'BREAKFAST', 'Wheat with Bread and Egg', null, 2000, 'MAIN KITCHEN', null, false),
      ('BRK-WHEAT-BREAD-MILK', 'BREAKFAST', 'Wheat with Bread, Milk and Egg', null, 2500, 'MAIN KITCHEN', null, false),
      ('BRK-TEA-BREAD-SALAD', 'BREAKFAST', 'Tea with Bread and Salad', null, 5000, 'MAIN KITCHEN', null, false),
      ('BRK-TEA-BEANS-EGG', 'BREAKFAST', 'Tea, Bread, Beans and Egg with Milk', null, 3500, 'MAIN KITCHEN', null, false),
      ('BRK-BEANS-ONLY', 'BREAKFAST', 'Beans Only', null, 1000, 'MAIN KITCHEN', null, false),
      ('BRK-OAT-BREAD-EGG', 'BREAKFAST', 'Oat with Bread and Egg', null, 2500, 'MAIN KITCHEN', null, false),
      ('BRK-FULL', 'BREAKFAST', 'Tea, Bread, Eggs, Salad, Pancakes/Waffles', null, 7000, 'MAIN KITCHEN', null, false),

      ('SHW-CHICKEN', 'SHAWARMA', 'Chicken Shawarma', 'Chicken, assorted vegetables, fries, sweet corn', 5000, 'MAIN KITCHEN', null, false),
      ('SHW-BEEF', 'SHAWARMA', 'Beef Shawarma', 'Beef, assorted vegetables, fries, sweet corn', 5000, 'MAIN KITCHEN', null, false),
      ('SHW-LOADED', 'SHAWARMA', 'Loaded Shawarma', 'Chicken, beef, sausage, assorted vegetables, sweet corn, fries', 7000, 'MAIN KITCHEN', null, false),

      ('BRG-CHICKEN', 'BURGER', 'Chicken Burger', 'Chicken breast topped with tomato, pickles, lettuce, onion and special Adee''s sauce', 8000, 'MAIN KITCHEN', null, false),
      ('BRG-SMASH-SINGLE', 'BURGER', 'Smash Single Burger', 'Minced beef topped with tomato, pickles, onion, lettuce, cheddar cheese and special Adee''s sauce', 9000, 'MAIN KITCHEN', null, false),
      ('BRG-ZINGER', 'BURGER', 'Zinger Burger', 'Crispy chicken topped with tomato, pickles, onion, lettuce and special sauce', 9500, 'MAIN KITCHEN', null, false),
      ('BRG-LOADED-FRIES', 'BURGER', 'Loaded Fries Beef/Chicken', 'Chicken or beef, mozzarella cheese, cheddar cheese, fries, cocktail sauce, green pepper, tomatoes, chilli sauce', 12000, 'MAIN KITCHEN', 'Also listed under Sandwich; stored once and linked to both categories.', false),

      ('MAIN-GOAT-JOLLOF', 'MAINS', 'Goat Jollof', 'Jollof rice with chopped spicy goat served with plantain, salad or coleslaw', 9000, 'MAIN KITCHEN', null, false),
      ('MAIN-GF-JOLLOF', 'MAINS', 'Guinea Fowl Jollof', 'Jollof rice with chopped guinea fowl served with plantain, salad or coleslaw', 9000, 'MAIN KITCHEN', null, false),
      ('MAIN-HALF-GF-GRAVY', 'MAINS', 'Half Guinea Fowl in Tomato Gravy with Rice', null, 11000, 'MAIN KITCHEN', null, false),
      ('MAIN-CRISPY-BREAST', 'MAINS', 'Crispy Chicken Breast with Jollof / Yam / Fried Rice', null, 7000, 'MAIN KITCHEN', null, false),
      ('MAIN-CHICKEN-RICE', 'MAINS', 'Chicken Jollof / Fried Rice', null, 8000, 'MAIN KITCHEN', null, false),
      ('MAIN-BEEF-RICE', 'MAINS', 'Beef Jollof / Fried Rice', null, 7000, 'MAIN KITCHEN', null, false),
      ('MAIN-ASSORTED-RICE', 'MAINS', 'Assorted Jollof / Fried Rice', 'Chicken, beef, sausage, gizzard, egg, carrot, green pepper, onion, cabbage', 10000, 'MAIN KITCHEN', null, false),
      ('MAIN-SHRIMP-RICE', 'MAINS', 'Shrimp Jollof / Fried Rice', null, 12000, 'MAIN KITCHEN', null, false),
      ('MAIN-CHECK-CHECK', 'MAINS', 'Check Check', null, 7000, 'MAIN KITCHEN', 'Confirm the exact dish name and description.', false),
      ('MAIN-RICE-GOAT-STEW', 'MAINS', 'Plain Rice with Goat Stew', null, 7000, 'MAIN KITCHEN', null, false),
      ('MAIN-GOAT-VEG-RICE', 'MAINS', 'Goat Vegetable Rice', null, 7500, 'MAIN KITCHEN', null, false),
      ('MAIN-PERI-FISH', 'MAINS', 'Peri Peri Fish Fillet Served with Any Side Dish of Your Choice', null, 2000, 'MAIN KITCHEN', 'Confirm whether the source price is GH₵20; it appears unusually low.', false),

      ('LOC-FUFU', 'LOCALS', 'Fufu', null, 1500, 'MAIN KITCHEN', 'Source price is GH₵15 and above.', true),
      ('LOC-RICE-BALLS', 'LOCALS', 'Rice Balls', null, 1000, 'MAIN KITCHEN', null, false),
      ('LOC-TUO-ZAAFI', 'LOCALS', 'Tuo Zaafi', null, 1000, 'MAIN KITCHEN', null, false),
      ('LOC-BANKU', 'LOCALS', 'Banku', null, 1000, 'MAIN KITCHEN', null, false),

      ('NDP-CHICKEN-NOODLES', 'NOODLES & PASTA', 'Chicken Noodles', null, 7000, 'MAIN KITCHEN', null, false),
      ('NDP-BEEF-NOODLES', 'NOODLES & PASTA', 'Beef Noodles', null, 7000, 'MAIN KITCHEN', null, false),
      ('NDP-ASSORTED-NOODLES', 'NOODLES & PASTA', 'Assorted Noodles', null, 10000, 'MAIN KITCHEN', null, false),
      ('NDP-VEG-NOODLE-SOUP', 'NOODLES & PASTA', 'Vegetable Noodle Soup', null, 11000, 'MAIN KITCHEN', null, false),
      ('NDP-SPAGHETTI', 'NOODLES & PASTA', 'Spaghetti', 'Beef, sausage, chicken, gizzard and assorted vegetables', 7500, 'MAIN KITCHEN', null, false),
      ('NDP-BOLOGNAISE', 'NOODLES & PASTA', 'Spaghetti Bolognaise', 'Spaghetti, minced meat, tomato sauce, parmesan cheese, onion, parsley', 10000, 'MAIN KITCHEN', null, false),
      ('NDP-ALFREDO', 'NOODLES & PASTA', 'Chicken Alfredo Pasta', null, 10000, 'MAIN KITCHEN', null, false),
      ('NDP-CHICKEN-SOUP', 'NOODLES & PASTA', 'Chicken Noodle Soup', null, 10000, 'MAIN KITCHEN', null, false),

      ('GRL-GUINEA-FOWL', 'GRILLS', 'Guinea Fowl', 'Served with a side dish of your choice', 10000, 'GRILL', null, false),
      ('GRL-CHICKEN-QUARTER', 'GRILLS', 'Chicken Quarter', 'BBQ / spicy / lemon butter, plantain, egg, salad and a side of your choice', 12000, 'GRILL', null, false),
      ('GRL-QUARTER-CRISPY', 'GRILLS', 'Quarter Chicken Crispy', 'Plantain, egg, salad and a side dish of your choice', 8000, 'GRILL', null, false),
      ('GRL-WINGS-6', 'GRILLS', 'Grill Wings (6)', 'BBQ / spicy / lemon butter, plantain, egg, salad and a side dish of your choice', 10000, 'GRILL', null, false),
      ('GRL-CRISPY-WINGS-6', 'GRILLS', 'Crispy Chicken Wing (6)', 'Plantain, egg, salad and a side dish of your choice', 10000, 'GRILL', null, false),
      ('GRL-BEEF-FILLET', 'GRILLS', 'Beef Steak Fillet (South Africa)', 'Homemade pepper sauce, mashed potato and vegetables', 13000, 'GRILL', null, false),
      ('GRL-TBONE', 'GRILLS', 'T-Bone Steak (South Africa)', 'Mashed potato and vegetables, creamy pepper sauce', 20000, 'GRILL', null, false),
      ('GRL-BEEF-KEBAB', 'GRILLS', 'Beef Kebab (3 Skewers)', 'Served with a side dish of choice', 8000, 'GRILL', null, false),
      ('GRL-CHICKEN-KEBAB', 'GRILLS', 'Chicken Kebab (3 Skewers)', 'Served with a side dish of your choice', 9000, 'GRILL', null, false),
      ('GRL-TURKEY-WINGS', 'GRILLS', 'Turkey Wings with Yam Chips', 'Served with a dish of your choice', 12000, 'GRILL', 'Confirm whether yam chips are included or another side is selectable.', false),
      ('GRL-TILAPIA', 'GRILLS', 'Grilled Tilapia', null, 10000, 'GRILL', 'Three source prices are preserved as unlabeled variants.', false),

      ('GRV-GOAT', 'GRAVIES', 'Goat Gravy', 'Served with any side dish of your choice', 7500, 'MAIN KITCHEN', null, false),
      ('GRV-BEEF', 'GRAVIES', 'Beef Gravy', 'Served with any side dish of your choice', 5000, 'MAIN KITCHEN', null, false),
      ('GRV-TILAPIA', 'GRAVIES', 'Tilapia Gravy', 'Served with any side dish of your choice', 8000, 'MAIN KITCHEN', null, false),
      ('GRV-CHICKEN', 'GRAVIES', 'Chicken Gravy', 'Served with any side dish of your choice', 5500, 'MAIN KITCHEN', null, false),
      ('GRV-FISH', 'GRAVIES', 'Fish Gravy', 'Served with any side dish of your choice', 6000, 'MAIN KITCHEN', null, false),

      ('SIDE-JOLLOF', 'SIDE DISH', 'Jollof Rice', null, 3000, 'MAIN KITCHEN', null, false),
      ('SIDE-FRIED-RICE', 'SIDE DISH', 'Fried Rice', null, 3500, 'MAIN KITCHEN', null, false),
      ('SIDE-YAM-CHIPS', 'SIDE DISH', 'Yam Chips', null, 2500, 'MAIN KITCHEN', null, false),
      ('SIDE-PLANTAIN', 'SIDE DISH', 'Plantain', null, 2500, 'MAIN KITCHEN', null, false),
      ('SIDE-BANKU', 'SIDE DISH', 'Banku', null, 1000, 'MAIN KITCHEN', null, false),
      ('SIDE-FRENCH-FRIES', 'SIDE DISH', 'French Fries', null, 3500, 'MAIN KITCHEN', null, false),
      ('SIDE-WAAKYE', 'SIDE DISH', 'Waakye', null, 2500, 'MAIN KITCHEN', null, false),
      ('SIDE-PLAIN-RICE', 'SIDE DISH', 'Plain Rice', null, 2000, 'MAIN KITCHEN', null, false),
      ('SIDE-YAM-BALLS', 'SIDE DISH', 'Yam Balls', null, 1000, 'MAIN KITCHEN', null, false),

      ('PST-MEAT-PIE', 'PASTRIES', 'Meat Pie', null, 2000, 'PASTRY', null, false),
      ('PST-SAUSAGE-ROLL', 'PASTRIES', 'Sausage Rolls', null, 1500, 'PASTRY', null, false),
      ('PST-CHIPS', 'PASTRIES', 'Chips', null, 1500, 'PASTRY', 'Four source price tiers are preserved without invented labels.', false),
      ('PST-SAMOSA', 'PASTRIES', 'Samosa', null, 2000, 'PASTRY', null, false),
      ('PST-SPRING-ROLL', 'PASTRIES', 'Spring Rolls', null, 2000, 'PASTRY', null, false),
      ('PST-PANCAKE-5', 'PASTRIES', 'Pancake (5)', null, 5000, 'PASTRY', null, false),
      ('PST-MILKY-DOUGHNUT', 'PASTRIES', 'Milky Doughnut', null, 4500, 'PASTRY', 'Confirm the unusual GH₵45 for 5 pieces and GH₵85 for 6 pieces progression.', false),
      ('PST-WAFFLES', 'PASTRIES', 'Waffles', null, 6000, 'PASTRY', null, false),
      ('PST-WAFFLES-ICE', 'PASTRIES', 'Waffles with Ice Cream', null, 8000, 'PASTRY', null, false),
      ('PST-RING-DOUGHNUT-10', 'PASTRIES', 'Ring Doughnut (10)', null, 5000, 'PASTRY', null, false),
      ('PST-CROISSANT-3', 'PASTRIES', 'Croissant (3)', null, 3500, 'PASTRY', null, false),
      ('PST-ROCK-BUN', 'PASTRIES', 'Rock Bun', null, 1000, 'PASTRY', null, false),

      ('PZA-MARGHERITA', 'PIZZA', 'Margherita Pizza', 'Tomato sauce, mozzarella, basil', 9000, 'PIZZA', null, false),
      ('PZA-PEPPERONI', 'PIZZA', 'Pepperoni Pizza', 'Pepperoni, mozzarella, sweet corn', 10000, 'PIZZA', null, false),
      ('PZA-HAWAIIAN', 'PIZZA', 'Hawaiian Pizza', 'Ham, pineapple', 10000, 'PIZZA', null, false),
      ('PZA-MEAT-LOVERS', 'PIZZA', 'Meat Lovers Pizza', 'Pepperoni, sausage, bacon, beef, chicken', 12000, 'PIZZA', null, false),
      ('PZA-SEAFOOD', 'PIZZA', 'Seafood Pizza', 'Calamari, shrimps, grouper fish', 12000, 'PIZZA', null, false),
      ('PZA-VEGETARIAN', 'PIZZA', 'Vegetarian Pizza', 'Assorted vegetables, mushroom, black olives, sweet corn', 8000, 'PIZZA', null, false),
      ('PZA-ADEES-SPECIAL', 'PIZZA', 'Adee''s Special Pizza', 'Chicken, beef, sausage, shrimps, onion, green pepper, tomatoes, mushroom, sweet corn, olives', 10000, 'PIZZA', 'Three source prices are preserved as unlabeled variants.', false),
      ('PZA-TUNA', 'PIZZA', 'Tuna Pizza', 'Tuna flakes, black olives, feta cheese, sweet corn, mozzarella, onion, green pepper', 10000, 'PIZZA', null, false),
      ('PZA-SHRIMPS', 'PIZZA', 'Shrimps Pizza', 'Shrimps, onion, green pepper, sweet corn, mozzarella', 10000, 'PIZZA', null, false),

      ('SAL-GREEN', 'SALAD BAR', 'Green Salad', 'Assorted vegetables, avocado, bacon, lemon juice', 6000, 'MAIN KITCHEN', null, false),
      ('SAL-CAESAR', 'SALAD BAR', 'Caesar Salad', 'Lettuce mix, lettuce, olive, egg, parmesan', 10000, 'MAIN KITCHEN', null, false),
      ('SAL-GHANAIAN', 'SALAD BAR', 'Ghanaian Salad', 'Tuna, baked beans, assorted vegetables, boiled egg, chef''s secret', 9000, 'MAIN KITCHEN', null, false),
      ('SAL-CHICKEN', 'SALAD BAR', 'Chicken Salad', 'Diced chicken, assorted vegetables, lemon dressing', 8000, 'MAIN KITCHEN', null, false),
      ('SAL-BEEF', 'SALAD BAR', 'Beef Salad', 'Beef fillet, assorted vegetables, avocado, lemon dressing', 7500, 'MAIN KITCHEN', null, false),
      ('SAL-TUNA', 'SALAD BAR', 'Tuna Salad', 'Tuna flake, assorted vegetables, boiled egg, black olive, sweet corn, chef''s secret', 8000, 'MAIN KITCHEN', null, false),
      ('SAL-POTATO', 'SALAD BAR', 'Potato Salad', 'Irish potato, cucumber, carrot, onion, tomato, pickles, boiled egg, parsley, mayonnaise', 9000, 'MAIN KITCHEN', null, false),
      ('SAL-FRUIT', 'SALAD BAR', 'Fruit Salad', 'Mango, pineapple, banana, apple, pawpaw, yellow melon, yoghurt, honey', 8000, 'MAIN KITCHEN', null, false),

      ('SND-CHICKEN', 'SANDWICH', 'Chicken Sandwich', null, 5500, 'MAIN KITCHEN', null, false),
      ('SND-TUNA', 'SANDWICH', 'Tuna Sandwich', null, 5000, 'MAIN KITCHEN', null, false),
      ('SND-CLUB', 'SANDWICH', 'Club Sandwich', null, 6500, 'MAIN KITCHEN', null, false)
  )
  insert into public.menu_items (
    organization_id, location_id, category_id, sku, name, description,
    price_minor, currency_code, station, source_notes, is_price_from,
    is_available, is_active, created_by
  )
  select
    v_organization_id, v_location_id, c.id, s.sku, s.name, s.description,
    s.price_minor, 'GHS', s.station, s.source_notes, s.is_price_from,
    true, true, v_owner_id
  from seed s
  join public.menu_categories c
    on c.location_id = v_location_id and c.name = s.category_name
  on conflict (organization_id, sku) do update set
    category_id = excluded.category_id,
    name = excluded.name,
    description = excluded.description,
    price_minor = excluded.price_minor,
    currency_code = excluded.currency_code,
    station = excluded.station,
    source_notes = excluded.source_notes,
    is_price_from = excluded.is_price_from,
    is_available = true,
    is_active = true;

  insert into public.menu_item_categories (
    organization_id, location_id, menu_item_id, category_id, is_primary, created_by
  )
  select
    mi.organization_id, mi.location_id, mi.id, mi.category_id, true, v_owner_id
  from public.menu_items mi
  where mi.organization_id = v_organization_id
    and mi.location_id = v_location_id
  on conflict (menu_item_id, category_id) do update set is_primary = true;

  insert into public.menu_item_categories (
    organization_id, location_id, menu_item_id, category_id, is_primary, created_by
  )
  select v_organization_id, v_location_id, mi.id, c.id, false, v_owner_id
  from public.menu_items mi
  join public.menu_categories c on c.location_id = v_location_id and c.name = 'SANDWICH'
  where mi.organization_id = v_organization_id and mi.sku = 'BRG-LOADED-FRIES'
  on conflict (menu_item_id, category_id) do update set is_primary = false;

  with seed(item_sku, code, name, price_minor, sort_order, is_default, source_notes) as (
    values
      ('GRL-GUINEA-FOWL', 'FULL', 'Full', 20000, 10, false, null),
      ('GRL-GUINEA-FOWL', 'HALF', 'Half', 10000, 20, true, null),
      ('GRL-TILAPIA', 'PRICE-100', null, 10000, 10, true, 'Size label not supplied.'),
      ('GRL-TILAPIA', 'PRICE-120', null, 12000, 20, false, 'Size label not supplied.'),
      ('GRL-TILAPIA', 'PRICE-160', null, 16000, 30, false, 'Size label not supplied.'),
      ('PST-CHIPS', 'PRICE-15', null, 1500, 10, true, 'Tier label not supplied.'),
      ('PST-CHIPS', 'PRICE-25', null, 2500, 20, false, 'Tier label not supplied.'),
      ('PST-CHIPS', 'PRICE-30', null, 3000, 30, false, 'Tier label not supplied.'),
      ('PST-CHIPS', 'PRICE-100', null, 10000, 40, false, 'Tier label not supplied.'),
      ('PST-MILKY-DOUGHNUT', '5-PCS', '5 pcs', 4500, 10, true, null),
      ('PST-MILKY-DOUGHNUT', '6-PCS', '6 pcs', 8500, 20, false, 'Confirm unusual pricing progression.'),
      ('PZA-MARGHERITA', 'SMALL', 'Small', 9000, 10, true, null),
      ('PZA-MARGHERITA', 'MEDIUM', 'Medium', 11000, 20, false, null),
      ('PZA-MARGHERITA', 'LARGE', 'Large', 15000, 30, false, null),
      ('PZA-PEPPERONI', 'SMALL', 'Small', 10000, 10, true, null),
      ('PZA-PEPPERONI', 'MEDIUM', 'Medium', 12000, 20, false, null),
      ('PZA-PEPPERONI', 'LARGE', 'Large', 14000, 30, false, null),
      ('PZA-HAWAIIAN', 'SMALL', 'Small', 10000, 10, true, null),
      ('PZA-HAWAIIAN', 'MEDIUM', 'Medium', 11000, 20, false, null),
      ('PZA-HAWAIIAN', 'LARGE', 'Large', 16000, 30, false, null),
      ('PZA-MEAT-LOVERS', 'SMALL', 'Small', 12000, 10, true, null),
      ('PZA-MEAT-LOVERS', 'MEDIUM', 'Medium', 15000, 20, false, null),
      ('PZA-MEAT-LOVERS', 'LARGE', 'Large', 18000, 30, false, null),
      ('PZA-SEAFOOD', 'SMALL', 'Small', 12000, 10, true, null),
      ('PZA-SEAFOOD', 'MEDIUM', 'Medium', 14000, 20, false, null),
      ('PZA-SEAFOOD', 'LARGE', 'Large', 18000, 30, false, null),
      ('PZA-VEGETARIAN', 'SMALL', 'Small', 8000, 10, true, null),
      ('PZA-VEGETARIAN', 'MEDIUM', 'Medium', 10000, 20, false, null),
      ('PZA-VEGETARIAN', 'LARGE', 'Large', 15000, 30, false, null),
      ('PZA-ADEES-SPECIAL', 'PRICE-100', null, 10000, 10, true, 'Size label not supplied.'),
      ('PZA-ADEES-SPECIAL', 'PRICE-150', null, 15000, 20, false, 'Size label not supplied.'),
      ('PZA-ADEES-SPECIAL', 'PRICE-200', null, 20000, 30, false, 'Size label not supplied.'),
      ('PZA-TUNA', 'SMALL', 'Small', 10000, 10, true, null),
      ('PZA-TUNA', 'MEDIUM', 'Medium', 12000, 20, false, null),
      ('PZA-TUNA', 'LARGE', 'Large', 16000, 30, false, null),
      ('PZA-SHRIMPS', 'SMALL', 'Small', 10000, 10, true, null),
      ('PZA-SHRIMPS', 'MEDIUM', 'Medium', 15000, 20, false, null),
      ('PZA-SHRIMPS', 'LARGE', 'Large', 20000, 30, false, null)
  )
  insert into public.menu_item_variants (
    organization_id, location_id, menu_item_id, code, name, price_minor,
    currency_code, sort_order, is_default, is_available, is_active,
    source_notes, created_by
  )
  select
    v_organization_id, v_location_id, mi.id, s.code, s.name, s.price_minor,
    'GHS', s.sort_order, s.is_default, true, true, s.source_notes, v_owner_id
  from seed s
  join public.menu_items mi
    on mi.organization_id = v_organization_id and mi.sku = s.item_sku
  on conflict (menu_item_id, code) do update set
    name = excluded.name,
    price_minor = excluded.price_minor,
    sort_order = excluded.sort_order,
    is_default = excluded.is_default,
    is_available = true,
    is_active = true,
    source_notes = excluded.source_notes;

  insert into public.modifier_groups (
    organization_id, location_id, code, name, selection_type,
    min_selections, max_selections, is_required, source_notes,
    sort_order, is_active, created_by
  ) values
    (v_organization_id, v_location_id, 'LOCAL_PROTEIN', 'Protein / add-ons', 'MULTIPLE', 0, 9, false, 'Source says these may function as add-ons for local meals.', 10, true, v_owner_id),
    (v_organization_id, v_location_id, 'RICE_CHOICE', 'Choose rice', 'SINGLE', 1, 1, true, null, 20, true, v_owner_id),
    (v_organization_id, v_location_id, 'CRISPY_SIDE', 'Choose jollof, yam or fried rice', 'SINGLE', 1, 1, true, null, 30, true, v_owner_id),
    (v_organization_id, v_location_id, 'GRILL_FLAVOR', 'Choose grill flavour', 'SINGLE', 1, 1, true, null, 40, true, v_owner_id),
    (v_organization_id, v_location_id, 'SIDE_CHOICE', 'Choose a side dish', 'SINGLE', 1, 1, true, 'No surcharge is listed for the included side choice.', 50, true, v_owner_id),
    (v_organization_id, v_location_id, 'PLANTAIN_SALAD', 'Choose plantain, salad or coleslaw', 'SINGLE', 1, 1, true, null, 60, true, v_owner_id),
    (v_organization_id, v_location_id, 'LOADED_PROTEIN', 'Choose chicken or beef', 'SINGLE', 1, 1, true, null, 70, true, v_owner_id),
    (v_organization_id, v_location_id, 'PIZZA_TOPPING', 'Extra pizza toppings', 'MULTIPLE', 0, 17, false, 'Each topping is listed at GH₵20.', 80, true, v_owner_id)
  on conflict (location_id, code) do update set
    name = excluded.name,
    selection_type = excluded.selection_type,
    min_selections = excluded.min_selections,
    max_selections = excluded.max_selections,
    is_required = excluded.is_required,
    source_notes = excluded.source_notes,
    sort_order = excluded.sort_order,
    is_active = true;

  with seed(group_code, code, name, price_delta_minor, sort_order) as (
    values
      ('LOCAL_PROTEIN', 'GOAT', 'Goat Meat', 2000, 10),
      ('LOCAL_PROTEIN', 'BEEF', 'Beef', 1500, 20),
      ('LOCAL_PROTEIN', 'WINGS', 'Wings', 1500, 30),
      ('LOCAL_PROTEIN', 'TILAPIA', 'Tilapia', 5000, 40),
      ('LOCAL_PROTEIN', 'SALMON', 'Salmon', 2000, 50),
      ('LOCAL_PROTEIN', 'REDFISH', 'Redfish', 3000, 60),
      ('LOCAL_PROTEIN', 'WELE', 'Wele', 500, 70),
      ('LOCAL_PROTEIN', 'INTESTINES', 'Intestines', 1000, 80),
      ('LOCAL_PROTEIN', 'MOY-MOY', 'Moy Moy', 2000, 90),
      ('RICE_CHOICE', 'JOLLOF', 'Jollof Rice', 0, 10),
      ('RICE_CHOICE', 'FRIED', 'Fried Rice', 0, 20),
      ('CRISPY_SIDE', 'JOLLOF', 'Jollof Rice', 0, 10),
      ('CRISPY_SIDE', 'YAM', 'Yam', 0, 20),
      ('CRISPY_SIDE', 'FRIED', 'Fried Rice', 0, 30),
      ('GRILL_FLAVOR', 'BBQ', 'BBQ', 0, 10),
      ('GRILL_FLAVOR', 'SPICY', 'Spicy', 0, 20),
      ('GRILL_FLAVOR', 'LEMON-BUTTER', 'Lemon Butter', 0, 30),
      ('SIDE_CHOICE', 'JOLLOF', 'Jollof Rice', 0, 10),
      ('SIDE_CHOICE', 'FRIED-RICE', 'Fried Rice', 0, 20),
      ('SIDE_CHOICE', 'YAM-CHIPS', 'Yam Chips', 0, 30),
      ('SIDE_CHOICE', 'PLANTAIN', 'Plantain', 0, 40),
      ('SIDE_CHOICE', 'BANKU', 'Banku', 0, 50),
      ('SIDE_CHOICE', 'FRENCH-FRIES', 'French Fries', 0, 60),
      ('SIDE_CHOICE', 'WAAKYE', 'Waakye', 0, 70),
      ('SIDE_CHOICE', 'PLAIN-RICE', 'Plain Rice', 0, 80),
      ('SIDE_CHOICE', 'YAM-BALLS', 'Yam Balls', 0, 90),
      ('PLANTAIN_SALAD', 'PLANTAIN', 'Plantain', 0, 10),
      ('PLANTAIN_SALAD', 'SALAD', 'Salad', 0, 20),
      ('PLANTAIN_SALAD', 'COLESLAW', 'Coleslaw', 0, 30),
      ('LOADED_PROTEIN', 'CHICKEN', 'Chicken', 0, 10),
      ('LOADED_PROTEIN', 'BEEF', 'Beef', 0, 20),
      ('PIZZA_TOPPING', 'PEPPERONI', 'Pepperoni', 2000, 10),
      ('PIZZA_TOPPING', 'SAUSAGE', 'Sausage', 2000, 20),
      ('PIZZA_TOPPING', 'HAM', 'Ham', 2000, 30),
      ('PIZZA_TOPPING', 'BACON', 'Bacon', 2000, 40),
      ('PIZZA_TOPPING', 'BEEF', 'Beef', 2000, 50),
      ('PIZZA_TOPPING', 'CHICKEN', 'Chicken', 2000, 60),
      ('PIZZA_TOPPING', 'ONION', 'Onion', 2000, 70),
      ('PIZZA_TOPPING', 'GREEN-PEPPER', 'Green Pepper', 2000, 80),
      ('PIZZA_TOPPING', 'TOMATOES', 'Tomatoes', 2000, 90),
      ('PIZZA_TOPPING', 'MUSHROOM', 'Mushroom', 2000, 100),
      ('PIZZA_TOPPING', 'OLIVES', 'Olives', 2000, 110),
      ('PIZZA_TOPPING', 'PINEAPPLE', 'Pineapple', 2000, 120),
      ('PIZZA_TOPPING', 'MOZZARELLA', 'Mozzarella', 2000, 130),
      ('PIZZA_TOPPING', 'CHEDDAR', 'Cheddar', 2000, 140),
      ('PIZZA_TOPPING', 'PARMESAN', 'Parmesan', 2000, 150),
      ('PIZZA_TOPPING', 'TOMATO-SAUCE', 'Tomato Sauce', 2000, 160),
      ('PIZZA_TOPPING', 'BBQ-SAUCE', 'BBQ Sauce', 2000, 170)
  )
  insert into public.modifier_options (
    organization_id, location_id, modifier_group_id, code, name,
    price_delta_minor, currency_code, sort_order, is_available,
    is_active, created_by
  )
  select
    v_organization_id, v_location_id, mg.id, s.code, s.name,
    s.price_delta_minor, 'GHS', s.sort_order, true, true, v_owner_id
  from seed s
  join public.modifier_groups mg
    on mg.location_id = v_location_id and mg.code = s.group_code
  on conflict (modifier_group_id, code) do update set
    name = excluded.name,
    price_delta_minor = excluded.price_delta_minor,
    sort_order = excluded.sort_order,
    is_available = true,
    is_active = true;

  with links(item_sku, group_code, sort_order) as (
    values
      ('LOC-FUFU', 'LOCAL_PROTEIN', 10),
      ('LOC-RICE-BALLS', 'LOCAL_PROTEIN', 10),
      ('LOC-TUO-ZAAFI', 'LOCAL_PROTEIN', 10),
      ('LOC-BANKU', 'LOCAL_PROTEIN', 10),
      ('MAIN-CHICKEN-RICE', 'RICE_CHOICE', 10),
      ('MAIN-BEEF-RICE', 'RICE_CHOICE', 10),
      ('MAIN-ASSORTED-RICE', 'RICE_CHOICE', 10),
      ('MAIN-SHRIMP-RICE', 'RICE_CHOICE', 10),
      ('MAIN-CRISPY-BREAST', 'CRISPY_SIDE', 10),
      ('MAIN-GOAT-JOLLOF', 'PLANTAIN_SALAD', 10),
      ('MAIN-GF-JOLLOF', 'PLANTAIN_SALAD', 10),
      ('BRG-LOADED-FRIES', 'LOADED_PROTEIN', 10),
      ('GRL-CHICKEN-QUARTER', 'GRILL_FLAVOR', 10),
      ('GRL-WINGS-6', 'GRILL_FLAVOR', 10),
      ('GRL-GUINEA-FOWL', 'SIDE_CHOICE', 20),
      ('GRL-CHICKEN-QUARTER', 'SIDE_CHOICE', 20),
      ('GRL-QUARTER-CRISPY', 'SIDE_CHOICE', 20),
      ('GRL-WINGS-6', 'SIDE_CHOICE', 20),
      ('GRL-CRISPY-WINGS-6', 'SIDE_CHOICE', 20),
      ('GRL-BEEF-KEBAB', 'SIDE_CHOICE', 20),
      ('GRL-CHICKEN-KEBAB', 'SIDE_CHOICE', 20),
      ('GRL-TURKEY-WINGS', 'SIDE_CHOICE', 20),
      ('MAIN-PERI-FISH', 'SIDE_CHOICE', 20),
      ('GRV-GOAT', 'SIDE_CHOICE', 10),
      ('GRV-BEEF', 'SIDE_CHOICE', 10),
      ('GRV-TILAPIA', 'SIDE_CHOICE', 10),
      ('GRV-CHICKEN', 'SIDE_CHOICE', 10),
      ('GRV-FISH', 'SIDE_CHOICE', 10),
      ('PZA-MARGHERITA', 'PIZZA_TOPPING', 10),
      ('PZA-PEPPERONI', 'PIZZA_TOPPING', 10),
      ('PZA-HAWAIIAN', 'PIZZA_TOPPING', 10),
      ('PZA-MEAT-LOVERS', 'PIZZA_TOPPING', 10),
      ('PZA-SEAFOOD', 'PIZZA_TOPPING', 10),
      ('PZA-VEGETARIAN', 'PIZZA_TOPPING', 10),
      ('PZA-ADEES-SPECIAL', 'PIZZA_TOPPING', 10),
      ('PZA-TUNA', 'PIZZA_TOPPING', 10),
      ('PZA-SHRIMPS', 'PIZZA_TOPPING', 10)
  )
  insert into public.menu_item_modifier_groups (
    organization_id, location_id, menu_item_id, modifier_group_id,
    sort_order, created_by
  )
  select
    v_organization_id, v_location_id, mi.id, mg.id,
    l.sort_order, v_owner_id
  from links l
  join public.menu_items mi
    on mi.organization_id = v_organization_id and mi.sku = l.item_sku
  join public.modifier_groups mg
    on mg.location_id = v_location_id and mg.code = l.group_code
  on conflict (menu_item_id, modifier_group_id) do update set
    sort_order = excluded.sort_order;
end;
$$;

create or replace function public.create_order(
  p_organization_id uuid,
  p_location_id uuid,
  p_channel text,
  p_items jsonb,
  p_customer_id uuid default null,
  p_table_id uuid default null,
  p_notes text default null,
  p_send_to_kitchen boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_order_item_id uuid;
  v_order_number text;
  v_currency text;
  v_item jsonb;
  v_menu_item public.menu_items%rowtype;
  v_variant public.menu_item_variants%rowtype;
  v_quantity numeric(12,3);
  v_subtotal bigint := 0;
  v_unit_price bigint;
  v_line_total bigint;
  v_modifier_total bigint;
  v_modifier_count integer;
  v_distinct_modifier_count integer;
  v_group record;
  v_selected_count integer;
begin
  perform private.require_permission('orders.create', p_organization_id, p_location_id, false);

  if p_channel not in ('DINE_IN', 'TAKEAWAY', 'PHONE', 'WHATSAPP', 'WEBSITE', 'DELIVERY', 'WALK_IN') then
    raise exception using errcode = '22023', message = 'Unsupported order channel';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception using errcode = '22023', message = 'At least one order item is required';
  end if;
  if p_channel = 'DINE_IN' and p_table_id is null then
    raise exception using errcode = '22023', message = 'Dine-in orders require a table';
  end if;
  if p_table_id is not null and not exists (
    select 1 from public.restaurant_tables rt
    where rt.id = p_table_id and rt.organization_id = p_organization_id
      and rt.location_id = p_location_id and rt.is_active
  ) then
    raise exception using errcode = '23503', message = 'Table is not available in this location';
  end if;
  if p_customer_id is not null and not exists (
    select 1 from public.customers c
    where c.id = p_customer_id and c.organization_id = p_organization_id and c.is_active
  ) then
    raise exception using errcode = '23503', message = 'Customer is not available in this organization';
  end if;

  select o.default_currency_code into strict v_currency
  from public.organizations o where o.id = p_organization_id and o.is_active;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_quantity := coalesce((v_item ->> 'quantity')::numeric, 0);
    if v_quantity <= 0 or v_quantity > 999 then
      raise exception using errcode = '22023', message = 'Order quantities must be greater than zero';
    end if;

    select * into strict v_menu_item
    from public.menu_items mi
    where mi.id = (v_item ->> 'menu_item_id')::uuid
      and mi.organization_id = p_organization_id
      and mi.location_id = p_location_id
      and mi.is_active and mi.is_available
    for share;

    v_variant := null;
    if nullif(v_item ->> 'menu_item_variant_id', '') is not null then
      select * into strict v_variant
      from public.menu_item_variants miv
      where miv.id = (v_item ->> 'menu_item_variant_id')::uuid
        and miv.menu_item_id = v_menu_item.id
        and miv.organization_id = p_organization_id
        and miv.location_id = p_location_id
        and miv.is_active and miv.is_available
      for share;
    else
      select * into v_variant
      from public.menu_item_variants miv
      where miv.menu_item_id = v_menu_item.id
        and miv.is_default and miv.is_active and miv.is_available
      order by miv.sort_order
      limit 1;
    end if;

    if v_item ? 'modifier_option_ids' and jsonb_typeof(v_item -> 'modifier_option_ids') <> 'array' then
      raise exception using errcode = '22023', message = 'Modifier selections must be an array';
    end if;

    select count(*), count(distinct selected.option_id)
    into v_modifier_count, v_distinct_modifier_count
    from (
      select value::uuid as option_id
      from jsonb_array_elements_text(coalesce(v_item -> 'modifier_option_ids', '[]'::jsonb))
    ) selected;
    if v_modifier_count <> v_distinct_modifier_count then
      raise exception using errcode = '22023', message = 'A modifier option cannot be selected twice';
    end if;

    select count(*), coalesce(sum(mo.price_delta_minor), 0)
    into v_selected_count, v_modifier_total
    from jsonb_array_elements_text(coalesce(v_item -> 'modifier_option_ids', '[]'::jsonb)) selected(value)
    join public.modifier_options mo on mo.id = selected.value::uuid
    join public.menu_item_modifier_groups link
      on link.modifier_group_id = mo.modifier_group_id
      and link.menu_item_id = v_menu_item.id
    join public.modifier_groups mg on mg.id = mo.modifier_group_id
    where mo.organization_id = p_organization_id
      and mo.location_id = p_location_id
      and mo.is_active and mo.is_available and mg.is_active;
    if v_selected_count <> v_modifier_count then
      raise exception using errcode = '22023', message = 'A modifier selection is unavailable or invalid for this item';
    end if;

    for v_group in
      select mg.id, mg.name, mg.min_selections, mg.max_selections
      from public.menu_item_modifier_groups link
      join public.modifier_groups mg on mg.id = link.modifier_group_id
      where link.menu_item_id = v_menu_item.id and mg.is_active
    loop
      select count(*) into v_selected_count
      from jsonb_array_elements_text(coalesce(v_item -> 'modifier_option_ids', '[]'::jsonb)) selected(value)
      join public.modifier_options mo on mo.id = selected.value::uuid
      where mo.modifier_group_id = v_group.id;
      if v_selected_count < v_group.min_selections or v_selected_count > v_group.max_selections then
        raise exception using errcode = '22023',
          message = format('%s requires between %s and %s selections', v_group.name, v_group.min_selections, v_group.max_selections);
      end if;
    end loop;

    v_unit_price := coalesce(v_variant.price_minor, v_menu_item.price_minor) + v_modifier_total;
    v_line_total := round(v_unit_price * v_quantity)::bigint;
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  if p_send_to_kitchen then
    perform private.require_permission('orders.send_kitchen', p_organization_id, p_location_id, false);
  end if;

  v_order_number := 'AF-' || to_char(timezone('Africa/Accra', now()), 'YYYYMMDD') || '-' ||
    lpad(nextval('public.order_number_seq')::text, 6, '0');

  insert into public.orders (
    organization_id, location_id, order_number, channel, customer_id,
    restaurant_table_id, order_status, kitchen_status, currency_code,
    subtotal_minor, total_minor, notes
  ) values (
    p_organization_id, p_location_id, v_order_number, p_channel, p_customer_id,
    p_table_id, case when p_send_to_kitchen then 'IN_PROGRESS' else 'CONFIRMED' end,
    case when p_send_to_kitchen then 'QUEUED' else 'NOT_SENT' end,
    v_currency, v_subtotal, v_subtotal, nullif(btrim(p_notes), '')
  ) returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_quantity := (v_item ->> 'quantity')::numeric;
    select * into strict v_menu_item from public.menu_items
    where id = (v_item ->> 'menu_item_id')::uuid;

    v_variant := null;
    if nullif(v_item ->> 'menu_item_variant_id', '') is not null then
      select * into strict v_variant from public.menu_item_variants
      where id = (v_item ->> 'menu_item_variant_id')::uuid and menu_item_id = v_menu_item.id;
    else
      select * into v_variant from public.menu_item_variants
      where menu_item_id = v_menu_item.id and is_default and is_active and is_available
      order by sort_order limit 1;
    end if;

    select coalesce(sum(mo.price_delta_minor), 0) into v_modifier_total
    from jsonb_array_elements_text(coalesce(v_item -> 'modifier_option_ids', '[]'::jsonb)) selected(value)
    join public.modifier_options mo on mo.id = selected.value::uuid;
    v_unit_price := coalesce(v_variant.price_minor, v_menu_item.price_minor) + v_modifier_total;
    v_line_total := round(v_unit_price * v_quantity)::bigint;

    insert into public.order_items (
      organization_id, location_id, order_id, menu_item_id, menu_item_variant_id,
      item_name, variant_name, sku, station, quantity, unit_price_minor,
      line_total_minor, notes
    ) values (
      p_organization_id, p_location_id, v_order_id, v_menu_item.id, v_variant.id,
      v_menu_item.name, v_variant.name, v_menu_item.sku, v_menu_item.station,
      v_quantity, v_unit_price, v_line_total, nullif(btrim(v_item ->> 'notes'), '')
    ) returning id into v_order_item_id;

    insert into public.order_item_modifiers (
      organization_id, location_id, order_item_id, modifier_group_id,
      modifier_option_id, group_name, option_name, price_delta_minor
    )
    select
      p_organization_id, p_location_id, v_order_item_id, mg.id,
      mo.id, mg.name, mo.name, mo.price_delta_minor
    from jsonb_array_elements_text(coalesce(v_item -> 'modifier_option_ids', '[]'::jsonb)) selected(value)
    join public.modifier_options mo on mo.id = selected.value::uuid
    join public.modifier_groups mg on mg.id = mo.modifier_group_id;
  end loop;

  if p_send_to_kitchen then
    insert into public.kitchen_tickets (
      organization_id, location_id, order_id, ticket_number, station
    )
    select
      p_organization_id, p_location_id, v_order_id,
      'K-' || v_order_number || '-' || row_number() over (order by oi.station),
      oi.station
    from (select distinct station from public.order_items where order_id = v_order_id) oi;
  end if;

  if p_table_id is not null then
    update public.restaurant_tables
    set status = 'OCCUPIED', occupied_since = coalesce(occupied_since, now())
    where id = p_table_id;
  end if;

  return v_order_id;
exception
  when no_data_found then
    raise exception using errcode = '22023', message = 'An order item, variant, or modifier is unavailable or invalid';
end;
$$;

revoke all on function public.create_order(uuid, uuid, text, jsonb, uuid, uuid, text, boolean) from public, anon;
grant execute on function public.create_order(uuid, uuid, text, jsonb, uuid, uuid, text, boolean) to authenticated;

alter publication supabase_realtime add table public.menu_item_variants;

comment on table public.menu_item_variants is
  'Priced menu sizes or portions. A null name preserves an unlabeled source price without inventing a size.';
comment on table public.modifier_groups is
  'Reusable choice rules linked to menu items, including required sides and optional paid add-ons.';
comment on column public.menu_items.source_notes is
  'Internal source-verification notes; not customer-facing marketing copy.';

commit;
