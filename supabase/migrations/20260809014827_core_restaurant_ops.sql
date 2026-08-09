-- Adee's Food core restaurant operations.
-- Menu, POS, orders, payments, kitchen, tables, customers, and reservations.

begin;

create extension if not exists btree_gist with schema extensions;

create sequence public.order_number_seq start 1001;
create sequence public.payment_reference_seq start 1001;

create table public.menu_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  name text not null check (length(btrim(name)) between 2 and 80),
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (location_id, name)
);

create table public.menu_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  category_id uuid not null references public.menu_categories(id) on delete restrict,
  sku text not null check (length(btrim(sku)) between 2 and 32),
  name text not null check (length(btrim(name)) between 2 and 120),
  description text,
  price_minor bigint not null check (price_minor >= 0),
  currency_code text not null default 'GHS' check (currency_code ~ '^[A-Z]{3}$'),
  station text not null default 'MAIN KITCHEN'
    check (station in ('MAIN KITCHEN', 'GRILL', 'PIZZA', 'DRINKS', 'PASTRY')),
  image_url text,
  is_available boolean not null default true,
  is_featured boolean not null default false,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (organization_id, sku)
);

create index menu_items_location_category_idx
  on public.menu_items (location_id, category_id, is_active, is_available);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  display_name text not null check (length(btrim(display_name)) between 2 and 120),
  phone text,
  email text check (email is null or email = lower(email)),
  birthday date,
  notes text,
  marketing_consent boolean not null default false,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict
);

create unique index customers_phone_org_key
  on public.customers (organization_id, phone)
  where phone is not null and is_active;

create unique index customers_email_org_key
  on public.customers (organization_id, email)
  where email is not null and is_active;

create table public.restaurant_tables (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_-]{0,11}$'),
  section_name text not null default 'Main Floor',
  capacity integer not null check (capacity between 1 and 50),
  status text not null default 'AVAILABLE'
    check (status in ('AVAILABLE', 'OCCUPIED', 'RESERVED', 'CLEANING', 'UNAVAILABLE')),
  occupied_since timestamptz,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (location_id, code),
  check ((status = 'OCCUPIED' and occupied_since is not null) or status <> 'OCCUPIED')
);

create table public.reservations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  customer_id uuid references public.customers(id) on delete set null,
  restaurant_table_id uuid references public.restaurant_tables(id) on delete restrict,
  guest_name text not null check (length(btrim(guest_name)) between 2 and 120),
  guest_phone text not null check (length(btrim(guest_phone)) between 6 and 30),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  party_size integer not null check (party_size between 1 and 50),
  occasion text,
  notes text,
  source text not null default 'PHONE'
    check (source in ('PHONE', 'WHATSAPP', 'WEBSITE', 'WALK_IN', 'STAFF')),
  status text not null default 'REQUESTED'
    check (status in ('REQUESTED', 'CONFIRMED', 'SEATED', 'COMPLETED', 'CANCELLED', 'NO_SHOW')),
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  check (ends_at > starts_at)
);

alter table public.reservations
  add constraint reservations_no_table_overlap
  exclude using gist (
    restaurant_table_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (
    restaurant_table_id is not null
    and status in ('REQUESTED', 'CONFIRMED', 'SEATED')
  );

create index reservations_location_start_idx
  on public.reservations (location_id, starts_at, status);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  order_number text not null,
  business_date date not null default (timezone('Africa/Accra', now()))::date,
  channel text not null
    check (channel in ('DINE_IN', 'TAKEAWAY', 'PHONE', 'WHATSAPP', 'WEBSITE', 'DELIVERY', 'WALK_IN')),
  customer_id uuid references public.customers(id) on delete set null,
  restaurant_table_id uuid references public.restaurant_tables(id) on delete restrict,
  order_status text not null default 'CONFIRMED'
    check (order_status in ('DRAFT', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'VOIDED', 'REFUNDED')),
  kitchen_status text not null default 'NOT_SENT'
    check (kitchen_status in ('NOT_REQUIRED', 'NOT_SENT', 'QUEUED', 'PREPARING', 'READY', 'SERVED', 'CANCELLED')),
  payment_status text not null default 'UNPAID'
    check (payment_status in ('UNPAID', 'PARTIALLY_PAID', 'PAID', 'PARTIALLY_REFUNDED', 'REFUNDED')),
  fulfillment_status text not null default 'NOT_STARTED'
    check (fulfillment_status in ('NOT_STARTED', 'READY_FOR_HANDOFF', 'SERVED', 'COLLECTED', 'DISPATCHED', 'DELIVERED', 'CANCELLED')),
  currency_code text not null default 'GHS' check (currency_code ~ '^[A-Z]{3}$'),
  subtotal_minor bigint not null default 0 check (subtotal_minor >= 0),
  discount_minor bigint not null default 0 check (discount_minor >= 0),
  tax_minor bigint not null default 0 check (tax_minor >= 0),
  service_charge_minor bigint not null default 0 check (service_charge_minor >= 0),
  total_minor bigint not null default 0 check (total_minor >= 0),
  amount_paid_minor bigint not null default 0 check (amount_paid_minor >= 0),
  notes text,
  completed_at timestamptz,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (location_id, order_number),
  check (discount_minor <= subtotal_minor + tax_minor + service_charge_minor),
  check (amount_paid_minor <= total_minor)
);

create index orders_location_business_date_idx
  on public.orders (location_id, business_date desc, created_at desc);
create index orders_active_idx
  on public.orders (location_id, order_status, kitchen_status)
  where order_status not in ('COMPLETED', 'CANCELLED', 'VOIDED', 'REFUNDED');

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  order_id uuid not null references public.orders(id) on delete restrict,
  menu_item_id uuid not null references public.menu_items(id) on delete restrict,
  item_name text not null,
  sku text not null,
  station text not null,
  quantity numeric(12,3) not null check (quantity > 0),
  unit_price_minor bigint not null check (unit_price_minor >= 0),
  line_total_minor bigint not null check (line_total_minor >= 0),
  notes text,
  created_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict
);

create index order_items_order_idx on public.order_items (order_id, created_at);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  order_id uuid not null references public.orders(id) on delete restrict,
  reference text not null,
  payment_method text not null check (payment_method in ('CASH', 'MOMO', 'CARD', 'ONLINE')),
  amount_minor bigint not null check (amount_minor > 0),
  currency_code text not null default 'GHS' check (currency_code ~ '^[A-Z]{3}$'),
  status text not null default 'SUCCEEDED'
    check (status in ('PENDING', 'SUCCEEDED', 'FAILED', 'REFUNDED')),
  external_reference text,
  received_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (organization_id, reference)
);

create index payments_location_received_idx
  on public.payments (location_id, received_at desc, status);

create table public.kitchen_tickets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  order_id uuid not null references public.orders(id) on delete restrict,
  ticket_number text not null,
  station text not null,
  priority text not null default 'NORMAL' check (priority in ('NORMAL', 'RUSH')),
  status text not null default 'QUEUED'
    check (status in ('QUEUED', 'PREPARING', 'READY', 'SERVED', 'CANCELLED')),
  target_seconds integer not null default 1200 check (target_seconds between 60 and 14400),
  queued_at timestamptz not null default now(),
  started_at timestamptz,
  ready_at timestamptz,
  served_at timestamptz,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (order_id, station)
);

create index kitchen_tickets_queue_idx
  on public.kitchen_tickets (location_id, status, queued_at)
  where status in ('QUEUED', 'PREPARING', 'READY');

create trigger menu_categories_touch_version before update on public.menu_categories
for each row execute function private.touch_versioned_row();
create trigger menu_items_touch_version before update on public.menu_items
for each row execute function private.touch_versioned_row();
create trigger customers_touch_version before update on public.customers
for each row execute function private.touch_versioned_row();
create trigger restaurant_tables_touch_version before update on public.restaurant_tables
for each row execute function private.touch_versioned_row();
create trigger reservations_touch_version before update on public.reservations
for each row execute function private.touch_versioned_row();
create trigger orders_touch_version before update on public.orders
for each row execute function private.touch_versioned_row();
create trigger kitchen_tickets_touch_version before update on public.kitchen_tickets
for each row execute function private.touch_versioned_row();

create trigger menu_categories_audit after insert or update or delete on public.menu_categories
for each row execute function private.audit_row_change();
create trigger menu_items_audit after insert or update or delete on public.menu_items
for each row execute function private.audit_row_change();
create trigger customers_audit after insert or update or delete on public.customers
for each row execute function private.audit_row_change();
create trigger restaurant_tables_audit after insert or update or delete on public.restaurant_tables
for each row execute function private.audit_row_change();
create trigger reservations_audit after insert or update or delete on public.reservations
for each row execute function private.audit_row_change();
create trigger orders_audit after insert or update on public.orders
for each row execute function private.audit_row_change();
create trigger payments_audit after insert or update on public.payments
for each row execute function private.audit_row_change();
create trigger kitchen_tickets_audit after insert or update on public.kitchen_tickets
for each row execute function private.audit_row_change();

alter table public.menu_categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.customers enable row level security;
alter table public.restaurant_tables enable row level security;
alter table public.reservations enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;
alter table public.kitchen_tickets enable row level security;

alter table public.menu_categories force row level security;
alter table public.menu_items force row level security;
alter table public.customers force row level security;
alter table public.restaurant_tables force row level security;
alter table public.reservations force row level security;
alter table public.orders force row level security;
alter table public.order_items force row level security;
alter table public.payments force row level security;
alter table public.kitchen_tickets force row level security;

create policy menu_categories_select on public.menu_categories for select to authenticated
using (private.has_permission('menu.view_internal', organization_id, location_id));
create policy menu_categories_insert on public.menu_categories for insert to authenticated
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy menu_categories_update on public.menu_categories for update to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id))
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));

create policy menu_items_select on public.menu_items for select to authenticated
using (private.has_permission('menu.view_internal', organization_id, location_id));
create policy menu_items_insert on public.menu_items for insert to authenticated
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));
create policy menu_items_update on public.menu_items for update to authenticated
using (private.has_permission('menu.manage_catalog', organization_id, location_id))
with check (private.has_permission('menu.manage_catalog', organization_id, location_id));

create policy customers_select on public.customers for select to authenticated
using (private.has_permission('customers.lookup', organization_id, location_id));
create policy customers_insert on public.customers for insert to authenticated
with check (private.has_permission('customers.create_update_basic', organization_id, location_id));
create policy customers_update on public.customers for update to authenticated
using (private.has_permission('customers.create_update_basic', organization_id, location_id))
with check (private.has_permission('customers.create_update_basic', organization_id, location_id));

create policy restaurant_tables_select on public.restaurant_tables for select to authenticated
using (private.has_permission('tables.view', organization_id, location_id));
create policy restaurant_tables_insert on public.restaurant_tables for insert to authenticated
with check (private.has_permission('settings.manage_location', organization_id, location_id));
create policy restaurant_tables_update on public.restaurant_tables for update to authenticated
using (private.has_permission('settings.manage_location', organization_id, location_id))
with check (private.has_permission('settings.manage_location', organization_id, location_id));

create policy reservations_select on public.reservations for select to authenticated
using (private.has_permission('reservations.view', organization_id, location_id));
create policy reservations_insert on public.reservations for insert to authenticated
with check (private.has_permission('reservations.create_update', organization_id, location_id));
create policy reservations_update on public.reservations for update to authenticated
using (private.has_permission('reservations.create_update', organization_id, location_id))
with check (private.has_permission('reservations.create_update', organization_id, location_id));

create policy orders_select on public.orders for select to authenticated
using (private.has_permission('orders.view', organization_id, location_id));
create policy order_items_select on public.order_items for select to authenticated
using (private.has_permission('orders.view', organization_id, location_id));
create policy payments_select on public.payments for select to authenticated
using (
  private.has_permission('payments.view_order', organization_id, location_id)
  or private.has_permission('reports.view_financial', organization_id, location_id)
);
create policy kitchen_tickets_select on public.kitchen_tickets for select to authenticated
using (private.has_permission('kitchen.view_status', organization_id, location_id));

grant select, insert, update on public.menu_categories to authenticated;
grant select, insert, update on public.menu_items to authenticated;
grant select, insert, update on public.customers to authenticated;
grant select, insert, update on public.restaurant_tables to authenticated;
grant select, insert, update on public.reservations to authenticated;
grant select on public.orders, public.order_items, public.payments, public.kitchen_tickets to authenticated;

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
  v_order_number text;
  v_currency text;
  v_item jsonb;
  v_menu_item public.menu_items%rowtype;
  v_quantity numeric(12,3);
  v_subtotal bigint := 0;
  v_line_total bigint;
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

  select o.default_currency_code into v_currency
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
      and mi.is_active
      and mi.is_available
    for share;

    v_line_total := round(v_menu_item.price_minor * v_quantity)::bigint;
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
    v_line_total := round(v_menu_item.price_minor * v_quantity)::bigint;

    insert into public.order_items (
      organization_id, location_id, order_id, menu_item_id, item_name,
      sku, station, quantity, unit_price_minor, line_total_minor, notes
    ) values (
      p_organization_id, p_location_id, v_order_id, v_menu_item.id, v_menu_item.name,
      v_menu_item.sku, v_menu_item.station, v_quantity, v_menu_item.price_minor,
      v_line_total, nullif(btrim(v_item ->> 'notes'), '')
    );
  end loop;

  if p_send_to_kitchen then
    insert into public.kitchen_tickets (
      organization_id, location_id, order_id, ticket_number, station
    )
    select
      p_organization_id,
      p_location_id,
      v_order_id,
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
    raise exception using errcode = '22023', message = 'An order item is unavailable or invalid';
end;
$$;

create or replace function public.record_order_payment(
  p_order_id uuid,
  p_payment_method text,
  p_amount_minor bigint,
  p_external_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_payment_id uuid;
  v_new_paid bigint;
begin
  select * into strict v_order from public.orders where id = p_order_id for update;
  perform private.require_permission('payments.record', v_order.organization_id, v_order.location_id, false);

  if p_payment_method not in ('CASH', 'MOMO', 'CARD', 'ONLINE') then
    raise exception using errcode = '22023', message = 'Unsupported payment method';
  end if;
  if p_amount_minor <= 0 or v_order.amount_paid_minor + p_amount_minor > v_order.total_minor then
    raise exception using errcode = '22023', message = 'Payment amount exceeds the outstanding balance';
  end if;
  if v_order.order_status in ('CANCELLED', 'VOIDED', 'REFUNDED') then
    raise exception using errcode = '55000', message = 'This order cannot accept payment';
  end if;

  insert into public.payments (
    organization_id, location_id, order_id, reference, payment_method,
    amount_minor, currency_code, external_reference
  ) values (
    v_order.organization_id,
    v_order.location_id,
    v_order.id,
    'PAY-' || to_char(timezone('Africa/Accra', now()), 'YYYYMMDD') || '-' ||
      lpad(nextval('public.payment_reference_seq')::text, 6, '0'),
    p_payment_method,
    p_amount_minor,
    v_order.currency_code,
    nullif(btrim(p_external_reference), '')
  ) returning id into v_payment_id;

  v_new_paid := v_order.amount_paid_minor + p_amount_minor;
  update public.orders
  set amount_paid_minor = v_new_paid,
      payment_status = case when v_new_paid = total_minor then 'PAID' else 'PARTIALLY_PAID' end,
      order_status = case
        when v_new_paid = total_minor and kitchen_status in ('READY', 'SERVED', 'NOT_REQUIRED') then 'COMPLETED'
        else order_status
      end,
      completed_at = case
        when v_new_paid = total_minor and kitchen_status in ('READY', 'SERVED', 'NOT_REQUIRED') then now()
        else completed_at
      end
  where id = v_order.id;

  return v_payment_id;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Order was not found';
end;
$$;

create or replace function public.advance_kitchen_ticket(
  p_ticket_id uuid,
  p_next_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ticket public.kitchen_tickets%rowtype;
  v_order_id uuid;
begin
  select * into strict v_ticket from public.kitchen_tickets where id = p_ticket_id for update;

  if p_next_status = 'PREPARING' then
    perform private.require_permission('kitchen.start_ticket', v_ticket.organization_id, v_ticket.location_id, false);
    if v_ticket.status <> 'QUEUED' then
      raise exception using errcode = '55000', message = 'Only queued tickets can be started';
    end if;
    update public.kitchen_tickets set status = 'PREPARING', started_at = now() where id = p_ticket_id;
  elsif p_next_status = 'READY' then
    perform private.require_permission('kitchen.ready_ticket', v_ticket.organization_id, v_ticket.location_id, false);
    if v_ticket.status <> 'PREPARING' then
      raise exception using errcode = '55000', message = 'Only preparing tickets can be marked ready';
    end if;
    update public.kitchen_tickets set status = 'READY', ready_at = now() where id = p_ticket_id;
  elsif p_next_status = 'SERVED' then
    perform private.require_permission('kitchen.ready_ticket', v_ticket.organization_id, v_ticket.location_id, false);
    if v_ticket.status <> 'READY' then
      raise exception using errcode = '55000', message = 'Only ready tickets can be served';
    end if;
    update public.kitchen_tickets set status = 'SERVED', served_at = now() where id = p_ticket_id;
  else
    raise exception using errcode = '22023', message = 'Unsupported kitchen status';
  end if;

  v_order_id := v_ticket.order_id;
  update public.orders o
  set kitchen_status = case
        when exists (select 1 from public.kitchen_tickets kt where kt.order_id = v_order_id and kt.status = 'PREPARING') then 'PREPARING'
        when exists (select 1 from public.kitchen_tickets kt where kt.order_id = v_order_id and kt.status = 'QUEUED') then 'QUEUED'
        when exists (select 1 from public.kitchen_tickets kt where kt.order_id = v_order_id and kt.status = 'READY') then 'READY'
        else 'SERVED'
      end,
      fulfillment_status = case
        when not exists (select 1 from public.kitchen_tickets kt where kt.order_id = v_order_id and kt.status not in ('READY', 'SERVED'))
          then 'READY_FOR_HANDOFF'
        else fulfillment_status
      end
  where o.id = v_order_id;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Kitchen ticket was not found';
end;
$$;

revoke all on function public.create_order(uuid, uuid, text, jsonb, uuid, uuid, text, boolean) from public, anon;
revoke all on function public.record_order_payment(uuid, text, bigint, text) from public, anon;
revoke all on function public.advance_kitchen_ticket(uuid, text) from public, anon;
grant execute on function public.create_order(uuid, uuid, text, jsonb, uuid, uuid, text, boolean) to authenticated;
grant execute on function public.record_order_payment(uuid, text, bigint, text) to authenticated;
grant execute on function public.advance_kitchen_ticket(uuid, text) to authenticated;

create or replace function public.toggle_menu_item_availability(
  p_menu_item_id uuid,
  p_available boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.menu_items%rowtype;
begin
  select * into strict v_item from public.menu_items where id = p_menu_item_id for update;
  perform private.require_permission('menu.toggle_availability', v_item.organization_id, v_item.location_id, false);
  update public.menu_items set is_available = p_available where id = p_menu_item_id;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Menu item was not found';
end;
$$;

create or replace function public.change_restaurant_table_status(
  p_table_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_table public.restaurant_tables%rowtype;
begin
  select * into strict v_table from public.restaurant_tables where id = p_table_id for update;
  perform private.require_permission('tables.change_status', v_table.organization_id, v_table.location_id, false);
  if p_status not in ('AVAILABLE', 'OCCUPIED', 'RESERVED', 'CLEANING', 'UNAVAILABLE') then
    raise exception using errcode = '22023', message = 'Unsupported table status';
  end if;
  update public.restaurant_tables
  set status = p_status,
      occupied_since = case when p_status = 'OCCUPIED' then coalesce(occupied_since, now()) else null end
  where id = p_table_id;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Restaurant table was not found';
end;
$$;

create or replace function public.advance_order(
  p_order_id uuid,
  p_action text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
begin
  select * into strict v_order from public.orders where id = p_order_id for update;

  if p_action = 'CANCEL' then
    perform private.require_permission('orders.cancel_unstarted', v_order.organization_id, v_order.location_id, false);
    if v_order.order_status in ('COMPLETED', 'CANCELLED', 'VOIDED', 'REFUNDED') then
      raise exception using errcode = '55000', message = 'This order can no longer be cancelled';
    end if;
    if length(btrim(coalesce(p_reason, ''))) < 3 then
      raise exception using errcode = '22023', message = 'A cancellation reason is required';
    end if;
    update public.orders
      set order_status = 'CANCELLED', kitchen_status = 'CANCELLED',
          fulfillment_status = 'CANCELLED', notes = concat_ws(E'\n', notes, 'Cancellation: ' || btrim(p_reason))
      where id = p_order_id;
    update public.kitchen_tickets set status = 'CANCELLED' where order_id = p_order_id and status <> 'SERVED';
    if v_order.restaurant_table_id is not null then
      update public.restaurant_tables set status = 'CLEANING', occupied_since = null
      where id = v_order.restaurant_table_id;
    end if;
  elsif p_action in ('SERVE', 'COLLECT', 'DISPATCH', 'DELIVER', 'COMPLETE') then
    perform private.require_permission('orders.update_draft', v_order.organization_id, v_order.location_id, false);
    if p_action = 'SERVE' then
      update public.orders set fulfillment_status = 'SERVED' where id = p_order_id;
    elsif p_action = 'COLLECT' then
      update public.orders set fulfillment_status = 'COLLECTED' where id = p_order_id;
    elsif p_action = 'DISPATCH' then
      update public.orders set fulfillment_status = 'DISPATCHED' where id = p_order_id;
    elsif p_action = 'DELIVER' then
      update public.orders set fulfillment_status = 'DELIVERED' where id = p_order_id;
    else
      if v_order.payment_status <> 'PAID' then
        raise exception using errcode = '55000', message = 'Order must be paid before completion';
      end if;
      update public.orders set order_status = 'COMPLETED', completed_at = now() where id = p_order_id;
      if v_order.restaurant_table_id is not null then
        update public.restaurant_tables set status = 'CLEANING', occupied_since = null
        where id = v_order.restaurant_table_id;
      end if;
    end if;
  else
    raise exception using errcode = '22023', message = 'Unsupported order action';
  end if;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Order was not found';
end;
$$;

revoke all on function public.toggle_menu_item_availability(uuid, boolean) from public, anon;
revoke all on function public.change_restaurant_table_status(uuid, text) from public, anon;
revoke all on function public.advance_order(uuid, text, text) from public, anon;
grant execute on function public.toggle_menu_item_availability(uuid, boolean) to authenticated;
grant execute on function public.change_restaurant_table_status(uuid, text) to authenticated;
grant execute on function public.advance_order(uuid, text, text) to authenticated;

alter publication supabase_realtime add table public.orders;
alter publication supabase_realtime add table public.kitchen_tickets;
alter publication supabase_realtime add table public.restaurant_tables;

commit;
