-- Adee's Food delivery + rider operations.
-- Adds the delivery/rider domain (zones, deliveries, cash-on-delivery
-- settlement, rider profiles, structured customer addresses) as a first-class
-- fulfillment concept alongside the existing dine-in schema, plus the
-- DELIVERY_RIDER role. Nothing dine-in is dropped or destructively altered;
-- see settings.dine_in_enabled (an operational_settings flag, app-defaulted
-- to disabled when absent) for how the existing tables/reservations modules
-- are hidden rather than removed.

begin;

-- ---------------------------------------------------------------------------
-- Delivery zones
-- ---------------------------------------------------------------------------

create table public.delivery_zones (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  name text not null check (length(btrim(name)) between 2 and 80),
  description text,
  base_fee_minor bigint not null default 0 check (base_fee_minor >= 0),
  minimum_order_minor bigint check (minimum_order_minor is null or minimum_order_minor >= 0),
  currency_code text not null default 'GHS' check (currency_code ~ '^[A-Z]{3}$'),
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (location_id, name)
);

-- ---------------------------------------------------------------------------
-- Structured customer delivery addresses (multiple saved addresses/customer)
-- ---------------------------------------------------------------------------

create table public.customer_addresses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  customer_id uuid not null references public.customers(id) on delete restrict,
  label text not null default 'Home' check (length(btrim(label)) between 2 and 40),
  address_line text not null check (length(btrim(address_line)) between 3 and 300),
  area text,
  city text,
  landmark text,
  latitude numeric(9,6) check (latitude is null or latitude between -90 and 90),
  longitude numeric(9,6) check (longitude is null or longitude between -180 and 180),
  delivery_notes text,
  is_default boolean not null default false,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict
);

create unique index customer_addresses_one_default_idx
  on public.customer_addresses (customer_id)
  where is_default and is_active;

-- ---------------------------------------------------------------------------
-- Rider operational profile (one per staff member acting as a rider)
-- ---------------------------------------------------------------------------

create table public.rider_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  vehicle_type text,
  status text not null default 'OFFLINE'
    check (status in ('AVAILABLE', 'ON_DELIVERY', 'OFFLINE', 'UNAVAILABLE')),
  cash_outstanding_minor bigint not null default 0 check (cash_outstanding_minor >= 0),
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (organization_id, profile_id)
);

-- ---------------------------------------------------------------------------
-- Rider cash settlements (created before deliveries so deliveries.settlement_id
-- can reference it directly; a settlement covers many deliveries)
-- ---------------------------------------------------------------------------

create table public.rider_settlements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  rider_id uuid not null references public.profiles(id) on delete restrict,
  expected_amount_minor bigint not null check (expected_amount_minor >= 0),
  actual_amount_minor bigint not null check (actual_amount_minor >= 0),
  variance_minor bigint generated always as (actual_amount_minor - expected_amount_minor) stored,
  currency_code text not null default 'GHS' check (currency_code ~ '^[A-Z]{3}$'),
  handover_reference text,
  notes text,
  received_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  settled_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  check (
    (expected_amount_minor = actual_amount_minor)
    or length(btrim(coalesce(notes, ''))) >= 3
  )
);

create index rider_settlements_rider_idx
  on public.rider_settlements (rider_id, settled_at desc);

-- ---------------------------------------------------------------------------
-- Deliveries — one row per order being dispatched
-- ---------------------------------------------------------------------------

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  order_id uuid not null references public.orders(id) on delete restrict,
  customer_id uuid references public.customers(id) on delete set null,
  rider_id uuid references public.profiles(id) on delete restrict,
  delivery_zone_id uuid references public.delivery_zones(id) on delete set null,

  -- The address is snapshotted onto the delivery so a later edit to a saved
  -- customer address never rewrites delivery history.
  address_line text not null check (length(btrim(address_line)) between 3 and 300),
  area text,
  city text,
  landmark text,
  latitude numeric(9,6) check (latitude is null or latitude between -90 and 90),
  longitude numeric(9,6) check (longitude is null or longitude between -180 and 180),
  delivery_notes text,
  package_count integer not null default 1 check (package_count between 1 and 50),

  delivery_fee_minor bigint not null default 0 check (delivery_fee_minor >= 0),
  currency_code text not null default 'GHS' check (currency_code ~ '^[A-Z]{3}$'),

  payment_method text check (payment_method in ('CASH', 'MOMO', 'CARD', 'ONLINE', 'CASH_ON_DELIVERY', 'OTHER')),
  amount_due_minor bigint not null default 0 check (amount_due_minor >= 0),
  amount_collected_minor bigint not null default 0 check (amount_collected_minor >= 0),
  collected_at timestamptz,
  settlement_status text not null default 'NOT_APPLICABLE'
    check (settlement_status in (
      'NOT_APPLICABLE', 'AWAITING_COLLECTION', 'COLLECTED_BY_RIDER',
      'SETTLEMENT_PENDING', 'SETTLED', 'SHORT', 'OVER'
    )),
  settlement_id uuid references public.rider_settlements(id) on delete set null,

  delivery_status text not null default 'AWAITING_RIDER'
    check (delivery_status in (
      'AWAITING_RIDER', 'ASSIGNED', 'ACCEPTED', 'PICKED_UP', 'ON_THE_WAY',
      'DELIVERED', 'FAILED', 'RETURNED', 'CANCELLED'
    )),
  failure_reason text,
  reassignment_reason text,

  assigned_at timestamptz,
  assigned_by uuid references public.profiles(id) on delete restrict,
  accepted_at timestamptz,
  picked_up_at timestamptz,
  on_the_way_at timestamptz,
  delivered_at timestamptz,
  failed_at timestamptz,

  version integer not null default 1 check (version > 0),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  unique (order_id),
  check (
    delivery_status <> 'FAILED' or length(btrim(coalesce(failure_reason, ''))) >= 3
  )
);

create index deliveries_location_status_idx
  on public.deliveries (location_id, delivery_status, assigned_at);
create index deliveries_rider_active_idx
  on public.deliveries (rider_id, delivery_status)
  where delivery_status not in ('DELIVERED', 'CANCELLED', 'RETURNED');
create index deliveries_settlement_idx
  on public.deliveries (settlement_id)
  where settlement_id is not null;

-- ---------------------------------------------------------------------------
-- Triggers: version/updated_at bookkeeping + audit trail, matching every
-- other operational table in this system.
-- ---------------------------------------------------------------------------

create trigger delivery_zones_touch before update on public.delivery_zones
for each row execute function private.touch_versioned_row();
create trigger customer_addresses_touch before update on public.customer_addresses
for each row execute function private.touch_versioned_row();
create trigger rider_profiles_touch before update on public.rider_profiles
for each row execute function private.touch_versioned_row();
create trigger deliveries_touch before update on public.deliveries
for each row execute function private.touch_versioned_row();

create trigger delivery_zones_audit after insert or update or delete on public.delivery_zones
for each row execute function private.audit_row_change();
create trigger customer_addresses_audit after insert or update or delete on public.customer_addresses
for each row execute function private.audit_row_change();
create trigger rider_profiles_audit after insert or update or delete on public.rider_profiles
for each row execute function private.audit_row_change();
create trigger deliveries_audit after insert or update on public.deliveries
for each row execute function private.audit_row_change();
create trigger rider_settlements_audit after insert on public.rider_settlements
for each row execute function private.audit_row_change();

create trigger rider_settlements_are_append_only
before update or delete on public.rider_settlements
for each row execute function private.block_immutable_mutation();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.delivery_zones enable row level security;
alter table public.customer_addresses enable row level security;
alter table public.rider_profiles enable row level security;
alter table public.rider_settlements enable row level security;
alter table public.deliveries enable row level security;

alter table public.delivery_zones force row level security;
alter table public.customer_addresses force row level security;
alter table public.rider_profiles force row level security;
alter table public.rider_settlements force row level security;
alter table public.deliveries force row level security;

create policy delivery_zones_select on public.delivery_zones for select to authenticated
using (private.has_permission('deliveries.view', organization_id, location_id));
create policy delivery_zones_insert on public.delivery_zones for insert to authenticated
with check (private.has_permission('deliveries.manage_zones', organization_id, location_id));
create policy delivery_zones_update on public.delivery_zones for update to authenticated
using (private.has_permission('deliveries.manage_zones', organization_id, location_id))
with check (private.has_permission('deliveries.manage_zones', organization_id, location_id));

create policy customer_addresses_select on public.customer_addresses for select to authenticated
using (private.has_permission('customers.lookup', organization_id, location_id));
create policy customer_addresses_insert on public.customer_addresses for insert to authenticated
with check (private.has_permission('customers.create_update_basic', organization_id, location_id));
create policy customer_addresses_update on public.customer_addresses for update to authenticated
using (private.has_permission('customers.create_update_basic', organization_id, location_id))
with check (private.has_permission('customers.create_update_basic', organization_id, location_id));

-- Riders may see and update only their own operational profile; staff with
-- deliveries.manage_rider_status can see/update every rider at their location.
create policy rider_profiles_select on public.rider_profiles for select to authenticated
using (
  profile_id = (select auth.uid())
  or private.has_permission('deliveries.view', organization_id, location_id)
);
create policy rider_profiles_insert on public.rider_profiles for insert to authenticated
with check (private.has_permission('deliveries.manage_rider_status', organization_id, location_id));
create policy rider_profiles_update on public.rider_profiles for update to authenticated
using (
  profile_id = (select auth.uid())
  or private.has_permission('deliveries.manage_rider_status', organization_id, location_id)
)
with check (
  profile_id = (select auth.uid())
  or private.has_permission('deliveries.manage_rider_status', organization_id, location_id)
);

-- A rider may only ever see their own settlement history; staff with
-- deliveries.view_settlements sees everyone's, matching "owner can view full
-- settlement history".
create policy rider_settlements_select on public.rider_settlements for select to authenticated
using (
  rider_id = (select auth.uid())
  or private.has_permission('deliveries.view_settlements', organization_id, location_id)
);

-- The core rider-scoping boundary: a rider can only ever read/update the
-- deliveries assigned to them, never the full location queue, never other
-- riders' assignments, and never orders/customers outside those deliveries
-- (enforced separately below by extending the orders/customers policies).
create policy deliveries_select on public.deliveries for select to authenticated
using (
  rider_id = (select auth.uid())
  or private.has_permission('deliveries.view', organization_id, location_id)
);
create policy deliveries_insert on public.deliveries for insert to authenticated
with check (private.has_permission('deliveries.assign', organization_id, location_id));
create policy deliveries_update on public.deliveries for update to authenticated
using (
  rider_id = (select auth.uid())
  or private.has_permission('deliveries.assign', organization_id, location_id)
)
with check (
  rider_id = (select auth.uid())
  or private.has_permission('deliveries.assign', organization_id, location_id)
);

grant select, insert, update on public.delivery_zones to authenticated;
grant select, insert, update on public.customer_addresses to authenticated;
grant select, insert, update on public.rider_profiles to authenticated;
grant select on public.rider_settlements to authenticated;
grant select, insert, update on public.deliveries to authenticated;

-- A rider must be able to read the order/customer summary linked to *their*
-- deliveries (name, phone, items) without gaining the general orders.view /
-- customers.lookup permission that would expose every order at the location.
create policy orders_select_own_delivery on public.orders for select to authenticated
using (
  exists (
    select 1 from public.deliveries d
    where d.order_id = orders.id and d.rider_id = (select auth.uid())
  )
);
create policy order_items_select_own_delivery on public.order_items for select to authenticated
using (
  exists (
    select 1 from public.deliveries d
    where d.order_id = order_items.order_id and d.rider_id = (select auth.uid())
  )
);
create policy customers_select_own_delivery on public.customers for select to authenticated
using (
  exists (
    select 1 from public.deliveries d
    where d.customer_id = customers.id and d.rider_id = (select auth.uid())
  )
);

comment on table public.deliveries is
  'One row per order being fulfilled by pickup dispatch or rider delivery. Cash-on-delivery liability is tracked here until a rider_settlements row closes it out.';
comment on table public.rider_settlements is
  'Append-only record of cash handed over by a rider. Corrections are new settlement rows, never edits.';
comment on table public.rider_profiles is
  'Operational status (available/on delivery/offline) for a staff member acting as a delivery rider, separate from their staff_employments record.';

-- ---------------------------------------------------------------------------
-- RBAC catalog additions — DELIVERY_RIDER role + deliveries.*/rider.* module
-- ---------------------------------------------------------------------------

insert into public.roles (id, code, name, description, risk_level, is_system)
values (
  '00000000-0000-4000-8000-000000000104',
  'DELIVERY_RIDER',
  'Delivery Rider',
  'Mobile-only access to the rider''s own assigned deliveries, status updates, and cash settlement history.',
  'MEDIUM',
  true
);

insert into public.permissions (code, module, description, risk_level)
values
  ('deliveries.view', 'deliveries', 'View the delivery queue for assigned locations.', 'MEDIUM'),
  ('deliveries.assign', 'deliveries', 'Assign or reassign a rider to a delivery.', 'HIGH'),
  ('deliveries.manage_zones', 'deliveries', 'Create and edit delivery zones and fees.', 'HIGH'),
  ('deliveries.record_settlement', 'deliveries', 'Record cash handed over by a rider.', 'CRITICAL'),
  ('deliveries.view_settlements', 'deliveries', 'View rider cash settlement history.', 'HIGH'),
  ('deliveries.manage_rider_status', 'deliveries', 'Override a rider''s operational availability status.', 'MEDIUM'),
  ('rider.view_own_deliveries', 'deliveries', 'View only the authenticated rider''s assigned deliveries.', 'LOW'),
  ('rider.update_own_delivery', 'deliveries', 'Advance the status of the authenticated rider''s own delivery.', 'MEDIUM'),
  ('rider.view_own_settlements', 'deliveries', 'View the authenticated rider''s own settlement history.', 'LOW'),
  ('rider.update_own_status', 'deliveries', 'Set the authenticated rider''s own availability status.', 'LOW');

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = any (array[
  'deliveries.view',
  'deliveries.assign',
  'deliveries.record_settlement'
])
where r.code = 'RECEPTIONIST';

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = any (array[
  'deliveries.view',
  'deliveries.assign',
  'deliveries.manage_zones',
  'deliveries.record_settlement',
  'deliveries.view_settlements',
  'deliveries.manage_rider_status'
])
where r.code = 'MANAGER';

-- OWNER's role_permissions were originally seeded with a one-time cross join
-- against every permission that existed at the time; new permission codes
-- added by later migrations (like this one) must be granted explicitly.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = any (array[
  'deliveries.view',
  'deliveries.assign',
  'deliveries.manage_zones',
  'deliveries.record_settlement',
  'deliveries.view_settlements',
  'deliveries.manage_rider_status',
  'rider.view_own_deliveries',
  'rider.update_own_delivery',
  'rider.view_own_settlements',
  'rider.update_own_status'
])
where r.code = 'OWNER';

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = any (array[
  'rider.view_own_deliveries',
  'rider.update_own_delivery',
  'rider.view_own_settlements',
  'rider.update_own_status'
])
where r.code = 'DELIVERY_RIDER';

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

create or replace function public.assign_delivery_rider(
  p_order_id uuid,
  p_rider_id uuid,
  p_delivery_fee_minor bigint default 0,
  p_delivery_zone_id uuid default null,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_existing public.deliveries%rowtype;
  v_rider_status text;
  v_delivery_id uuid;
  v_amount_due bigint;
begin
  select * into strict v_order from public.orders where id = p_order_id for update;
  perform private.require_permission('deliveries.assign', v_order.organization_id, v_order.location_id, false);

  if v_order.channel <> 'DELIVERY' then
    raise exception using errcode = '22023', message = 'Only delivery orders can have a rider assigned';
  end if;

  if not exists (
    select 1
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id and r.code = 'DELIVERY_RIDER'
    where ura.profile_id = p_rider_id
      and ura.organization_id = v_order.organization_id
      and ura.revoked_at is null
      and ura.valid_from <= now()
      and (ura.valid_until is null or ura.valid_until > now())
  ) then
    raise exception using errcode = '22023', message = 'This person does not hold the delivery rider role';
  end if;

  select status into v_rider_status
  from public.rider_profiles where profile_id = p_rider_id and organization_id = v_order.organization_id;
  if v_rider_status = 'UNAVAILABLE' then
    raise exception using errcode = '55000', message = 'This rider is marked unavailable';
  end if;

  select * into v_existing from public.deliveries where order_id = p_order_id for update;
  v_amount_due := v_order.total_minor - v_order.amount_paid_minor;
  if v_amount_due < 0 then
    v_amount_due := 0;
  end if;

  if v_existing.id is null then
    insert into public.deliveries (
      organization_id, location_id, order_id, customer_id, rider_id, delivery_zone_id,
      address_line, delivery_notes, delivery_fee_minor, currency_code,
      payment_method, amount_due_minor, settlement_status,
      delivery_status, assigned_at, assigned_by
    ) values (
      v_order.organization_id, v_order.location_id, p_order_id, v_order.customer_id, p_rider_id, p_delivery_zone_id,
      coalesce(nullif(btrim(v_order.delivery_address), ''), 'See order notes'), v_order.notes,
      coalesce(p_delivery_fee_minor, 0), v_order.currency_code,
      case when v_order.payment_status = 'UNPAID' then 'CASH_ON_DELIVERY' else null end,
      v_amount_due,
      case when v_order.payment_status = 'UNPAID' then 'AWAITING_COLLECTION' else 'NOT_APPLICABLE' end,
      'ASSIGNED', now(), (select auth.uid())
    ) returning id into v_delivery_id;
  else
    if v_existing.rider_id is not null and v_existing.rider_id <> p_rider_id
      and length(btrim(coalesce(p_reason, ''))) < 3 then
      raise exception using errcode = '22023', message = 'A reason is required to reassign this delivery';
    end if;
    update public.deliveries
    set rider_id = p_rider_id,
        delivery_zone_id = coalesce(p_delivery_zone_id, delivery_zone_id),
        delivery_fee_minor = coalesce(p_delivery_fee_minor, delivery_fee_minor),
        delivery_status = 'ASSIGNED',
        assigned_at = now(),
        assigned_by = (select auth.uid()),
        reassignment_reason = nullif(btrim(p_reason), ''),
        accepted_at = null, picked_up_at = null, on_the_way_at = null
    where id = v_existing.id
    returning id into v_delivery_id;
  end if;

  update public.orders set fulfillment_status = 'NOT_STARTED' where id = p_order_id and fulfillment_status = 'READY_FOR_HANDOFF';

  return v_delivery_id;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Order was not found';
end;
$$;

create or replace function public.advance_delivery_status(
  p_delivery_id uuid,
  p_action text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delivery public.deliveries%rowtype;
  v_is_own_rider boolean;
begin
  select * into strict v_delivery from public.deliveries where id = p_delivery_id for update;
  v_is_own_rider := v_delivery.rider_id = (select auth.uid());

  if not v_is_own_rider then
    perform private.require_permission('deliveries.assign', v_delivery.organization_id, v_delivery.location_id, false);
  else
    perform private.require_permission('rider.update_own_delivery', v_delivery.organization_id, v_delivery.location_id, false);
  end if;

  if p_action = 'ACCEPT' then
    if v_delivery.delivery_status <> 'ASSIGNED' then
      raise exception using errcode = '55000', message = 'Only an assigned delivery can be accepted';
    end if;
    update public.deliveries set delivery_status = 'ACCEPTED', accepted_at = now() where id = p_delivery_id;
    update public.rider_profiles set status = 'ON_DELIVERY'
      where profile_id = v_delivery.rider_id and organization_id = v_delivery.organization_id;

  elsif p_action = 'PICKED_UP' then
    if v_delivery.delivery_status <> 'ACCEPTED' then
      raise exception using errcode = '55000', message = 'Only an accepted delivery can be marked picked up';
    end if;
    update public.deliveries set delivery_status = 'PICKED_UP', picked_up_at = now() where id = p_delivery_id;
    update public.orders set fulfillment_status = 'DISPATCHED' where id = v_delivery.order_id;

  elsif p_action = 'ON_THE_WAY' then
    if v_delivery.delivery_status <> 'PICKED_UP' then
      raise exception using errcode = '55000', message = 'Only a picked-up delivery can be marked on the way';
    end if;
    update public.deliveries set delivery_status = 'ON_THE_WAY', on_the_way_at = now() where id = p_delivery_id;

  elsif p_action = 'DELIVERED' then
    if v_delivery.delivery_status not in ('PICKED_UP', 'ON_THE_WAY') then
      raise exception using errcode = '55000', message = 'Only a dispatched delivery can be marked delivered';
    end if;
    update public.deliveries
      set delivery_status = 'DELIVERED', delivered_at = now(),
          settlement_status = case
            when payment_method = 'CASH_ON_DELIVERY' then 'COLLECTED_BY_RIDER'
            else settlement_status
          end,
          amount_collected_minor = case
            when payment_method = 'CASH_ON_DELIVERY' then amount_due_minor
            else amount_collected_minor
          end,
          collected_at = case when payment_method = 'CASH_ON_DELIVERY' then now() else collected_at end
      where id = p_delivery_id;
    update public.orders set fulfillment_status = 'DELIVERED', order_status = 'COMPLETED', completed_at = now()
      where id = v_delivery.order_id;
    if v_delivery.payment_method = 'CASH_ON_DELIVERY' then
      update public.rider_profiles
        set cash_outstanding_minor = cash_outstanding_minor + v_delivery.amount_due_minor
        where profile_id = v_delivery.rider_id and organization_id = v_delivery.organization_id;
    end if;
    if not exists (
      select 1 from public.deliveries d
      where d.rider_id = v_delivery.rider_id and d.delivery_status in ('ASSIGNED', 'ACCEPTED', 'PICKED_UP', 'ON_THE_WAY')
    ) then
      update public.rider_profiles set status = 'AVAILABLE'
        where profile_id = v_delivery.rider_id and organization_id = v_delivery.organization_id;
    end if;

  elsif p_action in ('FAILED', 'RETURNED') then
    if length(btrim(coalesce(p_reason, ''))) < 3 then
      raise exception using errcode = '22023', message = 'A reason is required';
    end if;
    update public.deliveries
      set delivery_status = p_action,
          failed_at = case when p_action = 'FAILED' then now() else failed_at end,
          failure_reason = btrim(p_reason)
      where id = p_delivery_id;
    if not exists (
      select 1 from public.deliveries d
      where d.rider_id = v_delivery.rider_id and d.delivery_status in ('ASSIGNED', 'ACCEPTED', 'PICKED_UP', 'ON_THE_WAY')
    ) then
      update public.rider_profiles set status = 'AVAILABLE'
        where profile_id = v_delivery.rider_id and organization_id = v_delivery.organization_id;
    end if;

  elsif p_action = 'CANCEL' then
    perform private.require_permission('deliveries.assign', v_delivery.organization_id, v_delivery.location_id, false);
    update public.deliveries set delivery_status = 'CANCELLED' where id = p_delivery_id;

  else
    raise exception using errcode = '22023', message = 'Unsupported delivery action';
  end if;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Delivery was not found';
end;
$$;

create or replace function public.set_rider_status(
  p_rider_profile_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rider public.rider_profiles%rowtype;
  v_is_self boolean;
begin
  select * into strict v_rider from public.rider_profiles where id = p_rider_profile_id for update;
  v_is_self := v_rider.profile_id = (select auth.uid());

  if not v_is_self then
    perform private.require_permission('deliveries.manage_rider_status', v_rider.organization_id, v_rider.location_id, false);
  else
    perform private.require_permission('rider.update_own_status', v_rider.organization_id, v_rider.location_id, false);
  end if;

  if p_status not in ('AVAILABLE', 'ON_DELIVERY', 'OFFLINE', 'UNAVAILABLE') then
    raise exception using errcode = '22023', message = 'Unsupported rider status';
  end if;

  update public.rider_profiles set status = p_status where id = p_rider_profile_id;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Rider profile was not found';
end;
$$;

create or replace function public.record_rider_settlement(
  p_organization_id uuid,
  p_location_id uuid,
  p_rider_id uuid,
  p_actual_amount_minor bigint,
  p_delivery_ids uuid[],
  p_handover_reference text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expected bigint;
  v_settlement_id uuid;
  v_currency text;
begin
  perform private.require_permission('deliveries.record_settlement', p_organization_id, p_location_id, false);

  if p_actual_amount_minor < 0 then
    raise exception using errcode = '22023', message = 'Settlement amount cannot be negative';
  end if;
  if p_delivery_ids is null or array_length(p_delivery_ids, 1) is null then
    raise exception using errcode = '22023', message = 'Select at least one delivery to settle';
  end if;

  select coalesce(sum(amount_collected_minor), 0), max(currency_code)
    into v_expected, v_currency
  from public.deliveries
  where id = any(p_delivery_ids)
    and organization_id = p_organization_id
    and location_id = p_location_id
    and rider_id = p_rider_id
    and settlement_status = 'COLLECTED_BY_RIDER'
    and settlement_id is null
  for update;

  if v_expected is null or v_expected = 0 then
    raise exception using errcode = '22023', message = 'No unsettled cash-on-delivery deliveries match this rider';
  end if;

  if p_actual_amount_minor <> v_expected and length(btrim(coalesce(p_notes, ''))) < 3 then
    raise exception using errcode = '22023', message = 'A reason is required when the settlement amount does not match';
  end if;

  insert into public.rider_settlements (
    organization_id, location_id, rider_id, expected_amount_minor, actual_amount_minor,
    currency_code, handover_reference, notes, received_by
  ) values (
    p_organization_id, p_location_id, p_rider_id, v_expected, p_actual_amount_minor,
    coalesce(v_currency, 'GHS'), nullif(btrim(p_handover_reference), ''), nullif(btrim(p_notes), ''), (select auth.uid())
  ) returning id into v_settlement_id;

  update public.deliveries
  set settlement_id = v_settlement_id,
      settlement_status = case
        when p_actual_amount_minor = v_expected then 'SETTLED'
        when p_actual_amount_minor < v_expected then 'SHORT'
        else 'OVER'
      end
  where id = any(p_delivery_ids)
    and organization_id = p_organization_id
    and location_id = p_location_id
    and rider_id = p_rider_id
    and settlement_status = 'COLLECTED_BY_RIDER'
    and settlement_id is null;

  update public.rider_profiles
  set cash_outstanding_minor = greatest(0, cash_outstanding_minor - v_expected)
  where profile_id = p_rider_id and organization_id = p_organization_id;

  return v_settlement_id;
end;
$$;

revoke all on function public.assign_delivery_rider(uuid, uuid, bigint, uuid, text) from public, anon;
revoke all on function public.advance_delivery_status(uuid, text, text) from public, anon;
revoke all on function public.set_rider_status(uuid, text) from public, anon;
revoke all on function public.record_rider_settlement(uuid, uuid, uuid, bigint, uuid[], text, text) from public, anon;
grant execute on function public.assign_delivery_rider(uuid, uuid, bigint, uuid, text) to authenticated;
grant execute on function public.advance_delivery_status(uuid, text, text) to authenticated;
grant execute on function public.set_rider_status(uuid, text) to authenticated;
grant execute on function public.record_rider_settlement(uuid, uuid, uuid, bigint, uuid[], text, text) to authenticated;

alter publication supabase_realtime add table public.deliveries;
alter publication supabase_realtime add table public.rider_profiles;

notify pgrst, 'reload schema';

commit;
