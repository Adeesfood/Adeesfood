-- Adee's Food inventory, recipes, procurement, staffing, finance, and settings.

begin;

create sequence public.purchase_order_number_seq start 1001;

create table public.inventory_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  name text not null check (length(btrim(name)) between 2 and 80),
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (location_id, name)
);

create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  category_id uuid references public.inventory_categories(id) on delete set null,
  sku text not null check (length(btrim(sku)) between 2 and 32),
  name text not null check (length(btrim(name)) between 2 and 120),
  item_type text not null default 'RAW_INGREDIENT'
    check (item_type in ('RAW_INGREDIENT', 'PACKAGED_PRODUCT', 'BEVERAGE', 'CONSUMABLE', 'CLEANING_SUPPLY', 'PACKAGING', 'OTHER')),
  unit text not null check (unit in ('kg', 'g', 'litre', 'ml', 'piece', 'bottle', 'carton', 'bag', 'pack')),
  current_stock numeric(14,3) not null default 0 check (current_stock >= 0),
  reorder_level numeric(14,3) not null default 0 check (reorder_level >= 0),
  target_stock numeric(14,3) not null default 0 check (target_stock >= 0),
  average_cost_minor bigint not null default 0 check (average_cost_minor >= 0),
  latest_cost_minor bigint not null default 0 check (latest_cost_minor >= 0),
  storage_location text,
  track_expiry boolean not null default false,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (organization_id, sku)
);

create index inventory_items_stock_alert_idx
  on public.inventory_items (location_id, current_stock, reorder_level)
  where is_active;

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  movement_type text not null check (movement_type in (
    'PURCHASE_RECEIPT', 'SALE_CONSUMPTION', 'WASTAGE', 'ADJUSTMENT_IN',
    'ADJUSTMENT_OUT', 'TRANSFER', 'STAFF_MEAL', 'COMPLIMENTARY',
    'RETURN_TO_SUPPLIER', 'STOCK_COUNT_CORRECTION'
  )),
  quantity_delta numeric(14,3) not null check (quantity_delta <> 0),
  unit text not null,
  unit_cost_minor bigint check (unit_cost_minor is null or unit_cost_minor >= 0),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  reference_type text,
  reference_id uuid,
  posted_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  posted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict
);

create index stock_movements_item_posted_idx
  on public.stock_movements (inventory_item_id, posted_at desc);

create table public.recipes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  menu_item_id uuid not null references public.menu_items(id) on delete restrict,
  name text not null check (length(btrim(name)) between 2 and 120),
  version_number integer not null default 1 check (version_number > 0),
  yield_quantity numeric(12,3) not null default 1 check (yield_quantity > 0),
  status text not null default 'DRAFT' check (status in ('DRAFT', 'PUBLISHED', 'ARCHIVED')),
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (menu_item_id, version_number)
);

create table public.recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  quantity numeric(14,3) not null check (quantity > 0),
  unit text not null,
  waste_percentage numeric(6,3) not null default 0 check (waste_percentage between 0 and 100),
  created_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (recipe_id, inventory_item_id)
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  code text not null check (length(btrim(code)) between 2 and 20),
  name text not null check (length(btrim(name)) between 2 and 160),
  contact_person text,
  phone text,
  email text check (email is null or email = lower(email)),
  address text,
  payment_terms text,
  notes text,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (organization_id, code)
);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  po_number text not null,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  status text not null default 'DRAFT'
    check (status in ('DRAFT', 'SUBMITTED', 'APPROVED', 'ORDERED', 'RECEIVED', 'CLOSED', 'REJECTED')),
  expected_delivery date,
  currency_code text not null default 'GHS' check (currency_code ~ '^[A-Z]{3}$'),
  subtotal_minor bigint not null default 0 check (subtotal_minor >= 0),
  tax_minor bigint not null default 0 check (tax_minor >= 0),
  discount_minor bigint not null default 0 check (discount_minor >= 0),
  total_minor bigint not null default 0 check (total_minor >= 0),
  notes text,
  received_at timestamptz,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (location_id, po_number),
  check (discount_minor <= subtotal_minor + tax_minor)
);

create table public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  item_name text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit text not null,
  unit_cost_minor bigint not null check (unit_cost_minor >= 0),
  line_total_minor bigint not null check (line_total_minor >= 0),
  received_quantity numeric(14,3) not null default 0 check (received_quantity >= 0),
  created_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (purchase_order_id, inventory_item_id),
  check (received_quantity <= quantity)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  category text not null check (length(btrim(category)) between 2 and 80),
  amount_minor bigint not null check (amount_minor > 0),
  currency_code text not null default 'GHS' check (currency_code ~ '^[A-Z]{3}$'),
  payment_method text not null check (payment_method in ('CASH', 'MOMO', 'CARD', 'ONLINE')),
  vendor text,
  incurred_on date not null default current_date,
  description text not null check (length(btrim(description)) between 3 and 500),
  status text not null default 'POSTED' check (status in ('DRAFT', 'SUBMITTED', 'POSTED', 'REJECTED', 'REVERSED')),
  approved_by uuid references public.profiles(id) on delete restrict,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict
);

create index expenses_location_date_idx on public.expenses (location_id, incurred_on desc, status);

create table public.daily_closes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  business_date date not null,
  status text not null default 'OPEN' check (status in ('OPEN', 'SUBMITTED', 'REVIEWED', 'CLOSED')),
  orders_count integer not null default 0 check (orders_count >= 0),
  gross_sales_minor bigint not null default 0,
  discounts_minor bigint not null default 0,
  net_sales_minor bigint not null default 0,
  expenses_minor bigint not null default 0,
  expected_cash_minor bigint not null default 0,
  expected_momo_minor bigint not null default 0,
  expected_card_minor bigint not null default 0,
  expected_online_minor bigint not null default 0,
  actual_cash_minor bigint,
  cash_variance_minor bigint,
  notes text,
  submitted_by uuid references public.profiles(id) on delete restrict,
  submitted_at timestamptz,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (location_id, business_date)
);

create table public.staff_shifts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  employment_id uuid not null references public.staff_employments(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'SCHEDULED'
    check (status in ('SCHEDULED', 'CLOCKED_IN', 'COMPLETED', 'ABSENT', 'CANCELLED')),
  notes text,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  check (ends_at > starts_at)
);

create index staff_shifts_location_start_idx on public.staff_shifts (location_id, starts_at);

create table public.operational_settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  setting_key text not null check (setting_key ~ '^[a-z][a-z0-9_.-]{2,79}$'),
  setting_value jsonb not null,
  description text,
  version integer not null default 1 check (version > 0),
  updated_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (location_id, setting_key)
);

create trigger inventory_categories_touch before update on public.inventory_categories
for each row execute function private.touch_versioned_row();
create trigger inventory_items_touch before update on public.inventory_items
for each row execute function private.touch_versioned_row();
create trigger recipes_touch before update on public.recipes
for each row execute function private.touch_versioned_row();
create trigger suppliers_touch before update on public.suppliers
for each row execute function private.touch_versioned_row();
create trigger purchase_orders_touch before update on public.purchase_orders
for each row execute function private.touch_versioned_row();
create trigger expenses_touch before update on public.expenses
for each row execute function private.touch_versioned_row();
create trigger daily_closes_touch before update on public.daily_closes
for each row execute function private.touch_versioned_row();
create trigger staff_shifts_touch before update on public.staff_shifts
for each row execute function private.touch_versioned_row();
create trigger operational_settings_touch before update on public.operational_settings
for each row execute function private.touch_versioned_row();

create or replace function private.protect_inventory_balance()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.current_stock <> old.current_stock
    and coalesce(current_setting('app.stock_command', true), '') <> 'on' then
    raise exception using errcode = '55000', message = 'Inventory balances may change only through stock movements';
  end if;
  return new;
end;
$$;

create trigger inventory_items_protect_balance
before update on public.inventory_items
for each row execute function private.protect_inventory_balance();

create trigger inventory_categories_audit after insert or update or delete on public.inventory_categories
for each row execute function private.audit_row_change();
create trigger inventory_items_audit after insert or update or delete on public.inventory_items
for each row execute function private.audit_row_change();
create trigger stock_movements_audit after insert on public.stock_movements
for each row execute function private.audit_row_change();
create trigger stock_movements_immutable before update or delete on public.stock_movements
for each row execute function private.block_immutable_mutation();
create trigger recipes_audit after insert or update or delete on public.recipes
for each row execute function private.audit_row_change();
create trigger recipe_ingredients_audit after insert or update or delete on public.recipe_ingredients
for each row execute function private.audit_row_change();
create trigger suppliers_audit after insert or update or delete on public.suppliers
for each row execute function private.audit_row_change();
create trigger purchase_orders_audit after insert or update or delete on public.purchase_orders
for each row execute function private.audit_row_change();
create trigger purchase_order_lines_audit after insert or update or delete on public.purchase_order_lines
for each row execute function private.audit_row_change();
create trigger expenses_audit after insert or update or delete on public.expenses
for each row execute function private.audit_row_change();
create trigger daily_closes_audit after insert or update on public.daily_closes
for each row execute function private.audit_row_change();
create trigger staff_shifts_audit after insert or update or delete on public.staff_shifts
for each row execute function private.audit_row_change();
create trigger operational_settings_audit after insert or update or delete on public.operational_settings
for each row execute function private.audit_row_change();

alter table public.inventory_categories enable row level security;
alter table public.inventory_items enable row level security;
alter table public.stock_movements enable row level security;
alter table public.recipes enable row level security;
alter table public.recipe_ingredients enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_lines enable row level security;
alter table public.expenses enable row level security;
alter table public.daily_closes enable row level security;
alter table public.staff_shifts enable row level security;
alter table public.operational_settings enable row level security;

alter table public.inventory_categories force row level security;
alter table public.inventory_items force row level security;
alter table public.stock_movements force row level security;
alter table public.recipes force row level security;
alter table public.recipe_ingredients force row level security;
alter table public.suppliers force row level security;
alter table public.purchase_orders force row level security;
alter table public.purchase_order_lines force row level security;
alter table public.expenses force row level security;
alter table public.daily_closes force row level security;
alter table public.staff_shifts force row level security;
alter table public.operational_settings force row level security;

create policy inventory_categories_select on public.inventory_categories for select to authenticated
using (private.has_permission('inventory.view_on_hand', organization_id, location_id));
create policy inventory_categories_write on public.inventory_categories for all to authenticated
using (private.has_permission('inventory.manage_items_units', organization_id, location_id))
with check (private.has_permission('inventory.manage_items_units', organization_id, location_id));

create policy inventory_items_select on public.inventory_items for select to authenticated
using (private.has_permission('inventory.view_on_hand', organization_id, location_id));
create policy inventory_items_write on public.inventory_items for all to authenticated
using (private.has_permission('inventory.manage_items_units', organization_id, location_id))
with check (private.has_permission('inventory.manage_items_units', organization_id, location_id));
create policy stock_movements_select on public.stock_movements for select to authenticated
using (private.has_permission('inventory.view_on_hand', organization_id, location_id));

create policy recipes_select on public.recipes for select to authenticated
using (private.has_permission('recipes.view', organization_id, location_id));
create policy recipes_write on public.recipes for all to authenticated
using (private.has_permission('recipes.create_draft', organization_id, location_id))
with check (private.has_permission('recipes.create_draft', organization_id, location_id));
create policy recipe_ingredients_select on public.recipe_ingredients for select to authenticated
using (private.has_permission('recipes.view', organization_id, location_id));
create policy recipe_ingredients_write on public.recipe_ingredients for all to authenticated
using (private.has_permission('recipes.create_draft', organization_id, location_id))
with check (private.has_permission('recipes.create_draft', organization_id, location_id));

create policy suppliers_select on public.suppliers for select to authenticated
using (private.has_permission('suppliers.view', organization_id, location_id));
create policy suppliers_write on public.suppliers for all to authenticated
using (private.has_permission('suppliers.manage', organization_id, location_id))
with check (private.has_permission('suppliers.manage', organization_id, location_id));

create policy purchase_orders_select on public.purchase_orders for select to authenticated
using (
  private.has_permission('purchase_requests.create', organization_id, location_id)
  or private.has_permission('purchase_orders.create_issue', organization_id, location_id)
);
create policy purchase_order_lines_select on public.purchase_order_lines for select to authenticated
using (
  private.has_permission('purchase_requests.create', organization_id, location_id)
  or private.has_permission('purchase_orders.create_issue', organization_id, location_id)
);

create policy expenses_select on public.expenses for select to authenticated
using (
  private.has_permission('expenses.create', organization_id, location_id)
  or private.has_permission('reports.view_financial', organization_id, location_id)
);
create policy expenses_insert on public.expenses for insert to authenticated
with check (private.has_permission('expenses.create', organization_id, location_id));
create policy expenses_update on public.expenses for update to authenticated
using (private.has_permission('expenses.approve_post', organization_id, location_id))
with check (private.has_permission('expenses.approve_post', organization_id, location_id));

create policy daily_closes_select on public.daily_closes for select to authenticated
using (
  private.has_permission('daily_close.prepare', organization_id, location_id)
  or private.has_permission('reports.view_financial', organization_id, location_id)
);

create policy staff_shifts_select on public.staff_shifts for select to authenticated
using (private.has_permission('staff.view_schedule', organization_id, location_id));
create policy staff_shifts_write on public.staff_shifts for all to authenticated
using (private.has_permission('staff.manage_shifts_attendance', organization_id, location_id))
with check (private.has_permission('staff.manage_shifts_attendance', organization_id, location_id));

create policy operational_settings_select on public.operational_settings for select to authenticated
using (private.has_any_active_assignment(organization_id, location_id));
create policy operational_settings_write on public.operational_settings for all to authenticated
using (
  private.has_permission('settings.manage_location', organization_id, location_id)
  or private.has_permission('settings.manage_financial_security', organization_id, location_id)
)
with check (
  private.has_permission('settings.manage_location', organization_id, location_id)
  or private.has_permission('settings.manage_financial_security', organization_id, location_id)
);

grant select, insert, update on public.inventory_categories, public.inventory_items to authenticated;
grant select on public.stock_movements to authenticated;
grant select, insert, update, delete on public.recipes, public.recipe_ingredients to authenticated;
grant select, insert, update on public.suppliers to authenticated;
grant select on public.purchase_orders, public.purchase_order_lines to authenticated;
grant select, insert, update on public.expenses to authenticated;
grant select on public.daily_closes to authenticated;
grant select, insert, update on public.staff_shifts, public.operational_settings to authenticated;

create or replace function public.post_stock_movement(
  p_inventory_item_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_unit_cost_minor bigint,
  p_reason text,
  p_reference_type text default null,
  p_reference_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.inventory_items%rowtype;
  v_delta numeric(14,3);
  v_movement_id uuid;
  v_new_stock numeric(14,3);
  v_new_average bigint;
begin
  select * into strict v_item from public.inventory_items where id = p_inventory_item_id for update;

  if p_movement_type = 'WASTAGE' then
    perform private.require_permission('inventory.record_wastage', v_item.organization_id, v_item.location_id, false);
  else
    perform private.require_permission('inventory.adjust', v_item.organization_id, v_item.location_id, false);
  end if;

  if p_movement_type not in (
    'PURCHASE_RECEIPT', 'SALE_CONSUMPTION', 'WASTAGE', 'ADJUSTMENT_IN',
    'ADJUSTMENT_OUT', 'TRANSFER', 'STAFF_MEAL', 'COMPLIMENTARY',
    'RETURN_TO_SUPPLIER', 'STOCK_COUNT_CORRECTION'
  ) then
    raise exception using errcode = '22023', message = 'Unsupported stock movement type';
  end if;
  if p_quantity <= 0 then
    raise exception using errcode = '22023', message = 'Stock quantity must be greater than zero';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception using errcode = '22023', message = 'A reason is required';
  end if;

  v_delta := case
    when p_movement_type in ('PURCHASE_RECEIPT', 'ADJUSTMENT_IN') then p_quantity
    else -p_quantity
  end;
  v_new_stock := v_item.current_stock + v_delta;
  if v_new_stock < 0 then
    raise exception using errcode = '22023', message = 'Stock movement would create a negative balance';
  end if;

  v_new_average := v_item.average_cost_minor;
  if v_delta > 0 and p_unit_cost_minor is not null and v_new_stock > 0 then
    v_new_average := round(
      ((v_item.current_stock * v_item.average_cost_minor) + (v_delta * p_unit_cost_minor)) / v_new_stock
    )::bigint;
  end if;

  insert into public.stock_movements (
    organization_id, location_id, inventory_item_id, movement_type,
    quantity_delta, unit, unit_cost_minor, reason, reference_type, reference_id
  ) values (
    v_item.organization_id, v_item.location_id, v_item.id, p_movement_type,
    v_delta, v_item.unit, p_unit_cost_minor, btrim(p_reason), p_reference_type, p_reference_id
  ) returning id into v_movement_id;

  perform set_config('app.stock_command', 'on', true);
  update public.inventory_items
  set current_stock = v_new_stock,
      average_cost_minor = v_new_average,
      latest_cost_minor = case when p_unit_cost_minor is not null then p_unit_cost_minor else latest_cost_minor end
  where id = v_item.id;

  return v_movement_id;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Inventory item was not found';
end;
$$;

create or replace function public.receive_purchase_order(p_purchase_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_po public.purchase_orders%rowtype;
  v_line public.purchase_order_lines%rowtype;
  v_item public.inventory_items%rowtype;
begin
  select * into strict v_po from public.purchase_orders where id = p_purchase_order_id for update;
  perform private.require_permission('goods_receipts.record', v_po.organization_id, v_po.location_id, false);

  if v_po.status not in ('APPROVED', 'ORDERED') then
    raise exception using errcode = '55000', message = 'Only approved or ordered purchases can be received';
  end if;

  perform set_config('app.stock_command', 'on', true);
  for v_line in select * from public.purchase_order_lines where purchase_order_id = v_po.id for update
  loop
    select * into strict v_item from public.inventory_items where id = v_line.inventory_item_id for update;

    insert into public.stock_movements (
      organization_id, location_id, inventory_item_id, movement_type,
      quantity_delta, unit, unit_cost_minor, reason, reference_type, reference_id
    ) values (
      v_po.organization_id, v_po.location_id, v_item.id, 'PURCHASE_RECEIPT',
      v_line.quantity - v_line.received_quantity, v_item.unit, v_line.unit_cost_minor,
      'Goods received for ' || v_po.po_number, 'purchase_order', v_po.id
    );

    update public.inventory_items
    set current_stock = current_stock + (v_line.quantity - v_line.received_quantity),
        latest_cost_minor = v_line.unit_cost_minor,
        average_cost_minor = case
          when current_stock + (v_line.quantity - v_line.received_quantity) > 0 then
            round(
              ((current_stock * average_cost_minor) +
              ((v_line.quantity - v_line.received_quantity) * v_line.unit_cost_minor)) /
              (current_stock + (v_line.quantity - v_line.received_quantity))
            )::bigint
          else average_cost_minor
        end
    where id = v_item.id;

    update public.purchase_order_lines set received_quantity = quantity where id = v_line.id;
  end loop;

  update public.purchase_orders set status = 'RECEIVED', received_at = now() where id = v_po.id;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Purchase order was not found';
end;
$$;

create or replace function public.create_purchase_order(
  p_organization_id uuid,
  p_location_id uuid,
  p_supplier_id uuid,
  p_inventory_item_id uuid,
  p_quantity numeric,
  p_unit_cost_minor bigint,
  p_expected_delivery date default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_supplier public.suppliers%rowtype;
  v_item public.inventory_items%rowtype;
  v_po_id uuid;
  v_po_number text;
  v_currency text;
  v_total bigint;
begin
  perform private.require_permission('purchase_orders.create_issue', p_organization_id, p_location_id, false);
  select * into strict v_supplier from public.suppliers
    where id = p_supplier_id and organization_id = p_organization_id and location_id = p_location_id and is_active;
  select * into strict v_item from public.inventory_items
    where id = p_inventory_item_id and organization_id = p_organization_id and location_id = p_location_id and is_active;
  if p_quantity <= 0 or p_unit_cost_minor < 0 then
    raise exception using errcode = '22023', message = 'Quantity and unit cost must be valid';
  end if;
  select default_currency_code into v_currency from public.organizations where id = p_organization_id;
  v_total := round(p_quantity * p_unit_cost_minor)::bigint;
  v_po_number := 'PO-' || to_char(timezone('Africa/Accra', now()), 'YYYYMMDD') || '-' ||
    lpad(nextval('public.purchase_order_number_seq')::text, 6, '0');

  insert into public.purchase_orders (
    organization_id, location_id, po_number, supplier_id, status,
    expected_delivery, currency_code, subtotal_minor, total_minor, notes
  ) values (
    p_organization_id, p_location_id, v_po_number, v_supplier.id, 'ORDERED',
    p_expected_delivery, v_currency, v_total, v_total, nullif(btrim(p_notes), '')
  ) returning id into v_po_id;

  insert into public.purchase_order_lines (
    organization_id, location_id, purchase_order_id, inventory_item_id,
    item_name, quantity, unit, unit_cost_minor, line_total_minor
  ) values (
    p_organization_id, p_location_id, v_po_id, v_item.id,
    v_item.name, p_quantity, v_item.unit, p_unit_cost_minor, v_total
  );

  return v_po_id;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Supplier or inventory item was not found';
end;
$$;

create or replace function public.prepare_daily_close(
  p_organization_id uuid,
  p_location_id uuid,
  p_business_date date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_close_id uuid;
  v_orders_count integer;
  v_gross bigint;
  v_discounts bigint;
  v_expenses bigint;
  v_cash bigint;
  v_momo bigint;
  v_card bigint;
  v_online bigint;
begin
  perform private.require_permission('daily_close.prepare', p_organization_id, p_location_id, false);

  select count(*)::integer, coalesce(sum(total_minor), 0), coalesce(sum(discount_minor), 0)
  into v_orders_count, v_gross, v_discounts
  from public.orders
  where organization_id = p_organization_id and location_id = p_location_id
    and business_date = p_business_date and order_status not in ('CANCELLED', 'VOIDED');

  select
    coalesce(sum(amount_minor) filter (where payment_method = 'CASH' and status = 'SUCCEEDED'), 0),
    coalesce(sum(amount_minor) filter (where payment_method = 'MOMO' and status = 'SUCCEEDED'), 0),
    coalesce(sum(amount_minor) filter (where payment_method = 'CARD' and status = 'SUCCEEDED'), 0),
    coalesce(sum(amount_minor) filter (where payment_method = 'ONLINE' and status = 'SUCCEEDED'), 0)
  into v_cash, v_momo, v_card, v_online
  from public.payments
  where organization_id = p_organization_id and location_id = p_location_id
    and (timezone('Africa/Accra', received_at))::date = p_business_date;

  select coalesce(sum(amount_minor), 0) into v_expenses
  from public.expenses
  where organization_id = p_organization_id and location_id = p_location_id
    and incurred_on = p_business_date and status = 'POSTED';

  insert into public.daily_closes (
    organization_id, location_id, business_date, orders_count,
    gross_sales_minor, discounts_minor, net_sales_minor, expenses_minor,
    expected_cash_minor, expected_momo_minor, expected_card_minor, expected_online_minor
  ) values (
    p_organization_id, p_location_id, p_business_date, v_orders_count,
    v_gross, v_discounts, v_cash + v_momo + v_card + v_online, v_expenses,
    v_cash, v_momo, v_card, v_online
  )
  on conflict (location_id, business_date) do update set
    orders_count = excluded.orders_count,
    gross_sales_minor = excluded.gross_sales_minor,
    discounts_minor = excluded.discounts_minor,
    net_sales_minor = excluded.net_sales_minor,
    expenses_minor = excluded.expenses_minor,
    expected_cash_minor = excluded.expected_cash_minor,
    expected_momo_minor = excluded.expected_momo_minor,
    expected_card_minor = excluded.expected_card_minor,
    expected_online_minor = excluded.expected_online_minor
  returning id into v_close_id;

  return v_close_id;
end;
$$;

revoke all on function public.post_stock_movement(uuid, text, numeric, bigint, text, text, uuid) from public, anon;
revoke all on function public.receive_purchase_order(uuid) from public, anon;
revoke all on function public.create_purchase_order(uuid, uuid, uuid, uuid, numeric, bigint, date, text) from public, anon;
revoke all on function public.prepare_daily_close(uuid, uuid, date) from public, anon;
grant execute on function public.post_stock_movement(uuid, text, numeric, bigint, text, text, uuid) to authenticated;
grant execute on function public.receive_purchase_order(uuid) to authenticated;
grant execute on function public.create_purchase_order(uuid, uuid, uuid, uuid, numeric, bigint, date, text) to authenticated;
grant execute on function public.prepare_daily_close(uuid, uuid, date) to authenticated;

alter publication supabase_realtime add table public.inventory_items;

commit;
