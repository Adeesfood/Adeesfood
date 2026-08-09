-- Adee's Food management commands and trusted operational reporting.

begin;

create or replace function public.create_recipe(
  p_organization_id uuid,
  p_location_id uuid,
  p_menu_item_id uuid,
  p_inventory_item_id uuid,
  p_name text,
  p_ingredient_quantity numeric,
  p_yield_quantity numeric default 1
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_menu_item public.menu_items%rowtype;
  v_inventory_item public.inventory_items%rowtype;
  v_recipe_id uuid;
  v_next_version integer;
begin
  perform private.require_permission('recipes.create_draft', p_organization_id, p_location_id, false);
  if p_ingredient_quantity <= 0 or p_yield_quantity <= 0 then
    raise exception using errcode = '22023', message = 'Recipe quantities must be greater than zero';
  end if;
  select * into strict v_menu_item from public.menu_items
    where id = p_menu_item_id and organization_id = p_organization_id and location_id = p_location_id and is_active;
  select * into strict v_inventory_item from public.inventory_items
    where id = p_inventory_item_id and organization_id = p_organization_id and location_id = p_location_id and is_active;
  select coalesce(max(version_number), 0) + 1 into v_next_version
    from public.recipes where menu_item_id = p_menu_item_id;

  insert into public.recipes (
    organization_id, location_id, menu_item_id, name, version_number, yield_quantity
  ) values (
    p_organization_id, p_location_id, v_menu_item.id,
    coalesce(nullif(btrim(p_name), ''), v_menu_item.name), v_next_version, p_yield_quantity
  ) returning id into v_recipe_id;

  insert into public.recipe_ingredients (
    organization_id, location_id, recipe_id, inventory_item_id, quantity, unit
  ) values (
    p_organization_id, p_location_id, v_recipe_id, v_inventory_item.id,
    p_ingredient_quantity, v_inventory_item.unit
  );

  return v_recipe_id;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Menu or inventory item was not found';
end;
$$;

create or replace function public.publish_recipe(p_recipe_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipe public.recipes%rowtype;
begin
  select * into strict v_recipe from public.recipes where id = p_recipe_id for update;
  perform private.require_permission('recipes.publish_version', v_recipe.organization_id, v_recipe.location_id, false);
  if not exists (select 1 from public.recipe_ingredients where recipe_id = p_recipe_id) then
    raise exception using errcode = '55000', message = 'A recipe must contain at least one ingredient';
  end if;
  update public.recipes set status = 'ARCHIVED'
    where menu_item_id = v_recipe.menu_item_id and status = 'PUBLISHED' and id <> p_recipe_id;
  update public.recipes set status = 'PUBLISHED' where id = p_recipe_id;
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Recipe was not found';
end;
$$;

create or replace function public.update_restaurant_profile(
  p_organization_id uuid,
  p_location_id uuid,
  p_trading_name text,
  p_location_name text,
  p_currency_code text,
  p_timezone text,
  p_phone text default null,
  p_email text default null,
  p_address text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('settings.manage_location', p_organization_id, p_location_id, false);
  if length(btrim(p_trading_name)) < 2 or length(btrim(p_location_name)) < 2 then
    raise exception using errcode = '22023', message = 'Business and location names are required';
  end if;
  if p_currency_code !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'Currency code must use three letters';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception using errcode = '22023', message = 'Timezone is invalid';
  end if;
  update public.organizations set trading_name = btrim(p_trading_name), default_currency_code = p_currency_code
    where id = p_organization_id;
  update public.locations
    set name = btrim(p_location_name), timezone = p_timezone,
        phone = nullif(btrim(p_phone), ''), email = nullif(lower(btrim(p_email)), ''),
        address_line_1 = nullif(btrim(p_address), '')
    where id = p_location_id and organization_id = p_organization_id;
end;
$$;

create or replace function public.change_staff_role(
  p_organization_id uuid,
  p_location_id uuid,
  p_profile_id uuid,
  p_role_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role_id uuid;
  v_active_owner_count integer;
begin
  perform private.require_permission('security.manage_users_roles', p_organization_id, p_location_id, false);
  select id into strict v_role_id from public.roles where code = p_role_code;
  if not exists (
    select 1 from public.staff_employments
    where organization_id = p_organization_id and profile_id = p_profile_id and is_active
  ) then
    raise exception using errcode = '22023', message = 'Staff member is not actively employed';
  end if;

  if p_role_code <> 'OWNER' then
    select count(*)::integer into v_active_owner_count
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id and r.code = 'OWNER'
    where ura.organization_id = p_organization_id
      and ura.profile_id <> p_profile_id
      and ura.revoked_at is null
      and (ura.valid_until is null or ura.valid_until > now());
    if v_active_owner_count = 0 then
      raise exception using errcode = '55000', message = 'The last active owner cannot be reassigned';
    end if;
  end if;

  update public.user_role_assignments
    set revoked_at = now(), revoked_by = auth.uid(), revocation_reason = 'Role changed in management system'
    where organization_id = p_organization_id and profile_id = p_profile_id
      and revoked_at is null and (location_id is null or location_id = p_location_id);

  insert into public.user_role_assignments (
    organization_id, location_id, profile_id, role_id, assigned_by
  ) values (
    p_organization_id, p_location_id, p_profile_id, v_role_id, auth.uid()
  );
exception when no_data_found then
  raise exception using errcode = '22023', message = 'Role was not found';
end;
$$;

create or replace function public.get_dashboard_metrics(
  p_organization_id uuid,
  p_location_id uuid,
  p_business_date date default (timezone('Africa/Accra', now()))::date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform private.require_permission('dashboard.view_operational', p_organization_id, p_location_id, false);
  select jsonb_build_object(
    'sales_minor', coalesce((
      select sum(amount_minor) from public.payments
      where organization_id = p_organization_id and location_id = p_location_id
        and status = 'SUCCEEDED' and (timezone('Africa/Accra', received_at))::date = p_business_date
    ), 0),
    'orders_today', (select count(*) from public.orders
      where organization_id = p_organization_id and location_id = p_location_id and business_date = p_business_date),
    'active_orders', (select count(*) from public.orders
      where organization_id = p_organization_id and location_id = p_location_id
        and order_status not in ('COMPLETED', 'CANCELLED', 'VOIDED', 'REFUNDED')),
    'preparing_orders', (select count(*) from public.kitchen_tickets
      where organization_id = p_organization_id and location_id = p_location_id and status = 'PREPARING'),
    'ready_orders', (select count(*) from public.kitchen_tickets
      where organization_id = p_organization_id and location_id = p_location_id and status = 'READY'),
    'reservations_today', (select count(*) from public.reservations
      where organization_id = p_organization_id and location_id = p_location_id
        and (timezone('Africa/Accra', starts_at))::date = p_business_date
        and status not in ('CANCELLED', 'NO_SHOW')),
    'occupied_tables', (select count(*) from public.restaurant_tables
      where organization_id = p_organization_id and location_id = p_location_id and status = 'OCCUPIED'),
    'available_tables', (select count(*) from public.restaurant_tables
      where organization_id = p_organization_id and location_id = p_location_id and status = 'AVAILABLE' and is_active),
    'low_stock_items', (select count(*) from public.inventory_items
      where organization_id = p_organization_id and location_id = p_location_id
        and is_active and current_stock <= reorder_level),
    'expenses_minor', coalesce((select sum(amount_minor) from public.expenses
      where organization_id = p_organization_id and location_id = p_location_id
        and incurred_on = p_business_date and status = 'POSTED'), 0)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.get_report_summary(
  p_organization_id uuid,
  p_location_id uuid,
  p_from_date date,
  p_to_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform private.require_permission('reports.view_operational', p_organization_id, p_location_id, false);
  if p_to_date < p_from_date or p_to_date - p_from_date > 366 then
    raise exception using errcode = '22023', message = 'Report date range must be between one and 367 days';
  end if;

  select jsonb_build_object(
    'from_date', p_from_date,
    'to_date', p_to_date,
    'orders', (select count(*) from public.orders where organization_id = p_organization_id
      and location_id = p_location_id and business_date between p_from_date and p_to_date),
    'gross_sales_minor', coalesce((select sum(total_minor) from public.orders where organization_id = p_organization_id
      and location_id = p_location_id and business_date between p_from_date and p_to_date
      and order_status not in ('CANCELLED', 'VOIDED')), 0),
    'payments_minor', coalesce((select sum(amount_minor) from public.payments where organization_id = p_organization_id
      and location_id = p_location_id and status = 'SUCCEEDED'
      and (timezone('Africa/Accra', received_at))::date between p_from_date and p_to_date), 0),
    'expenses_minor', coalesce((select sum(amount_minor) from public.expenses where organization_id = p_organization_id
      and location_id = p_location_id and status = 'POSTED' and incurred_on between p_from_date and p_to_date), 0),
    'sales_by_channel', coalesce((select jsonb_agg(jsonb_build_object('channel', channel, 'orders', order_count, 'sales_minor', sales_minor))
      from (select channel, count(*) order_count, sum(total_minor) sales_minor from public.orders
        where organization_id = p_organization_id and location_id = p_location_id
          and business_date between p_from_date and p_to_date and order_status not in ('CANCELLED', 'VOIDED')
        group by channel order by sales_minor desc) channel_sales), '[]'::jsonb),
    'payments_by_method', coalesce((select jsonb_agg(jsonb_build_object('method', payment_method, 'amount_minor', amount_minor))
      from (select payment_method, sum(amount_minor) amount_minor from public.payments
        where organization_id = p_organization_id and location_id = p_location_id and status = 'SUCCEEDED'
          and (timezone('Africa/Accra', received_at))::date between p_from_date and p_to_date
        group by payment_method order by amount_minor desc) method_sales), '[]'::jsonb),
    'top_items', coalesce((select jsonb_agg(jsonb_build_object('name', item_name, 'quantity', quantity, 'sales_minor', sales_minor))
      from (select oi.item_name, sum(oi.quantity) quantity, sum(oi.line_total_minor) sales_minor
        from public.order_items oi join public.orders o on o.id = oi.order_id
        where oi.organization_id = p_organization_id and oi.location_id = p_location_id
          and o.business_date between p_from_date and p_to_date and o.order_status not in ('CANCELLED', 'VOIDED')
        group by oi.item_name order by quantity desc limit 10) item_sales), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.create_recipe(uuid, uuid, uuid, uuid, text, numeric, numeric) from public, anon;
revoke all on function public.publish_recipe(uuid) from public, anon;
revoke all on function public.update_restaurant_profile(uuid, uuid, text, text, text, text, text, text, text) from public, anon;
revoke all on function public.change_staff_role(uuid, uuid, uuid, text) from public, anon;
revoke all on function public.get_dashboard_metrics(uuid, uuid, date) from public, anon;
revoke all on function public.get_report_summary(uuid, uuid, date, date) from public, anon;
grant execute on function public.create_recipe(uuid, uuid, uuid, uuid, text, numeric, numeric) to authenticated;
grant execute on function public.publish_recipe(uuid) to authenticated;
grant execute on function public.update_restaurant_profile(uuid, uuid, text, text, text, text, text, text, text) to authenticated;
grant execute on function public.change_staff_role(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.get_dashboard_metrics(uuid, uuid, date) to authenticated;
grant execute on function public.get_report_summary(uuid, uuid, date, date) to authenticated;

comment on function public.create_order(uuid, uuid, text, jsonb, uuid, uuid, text, boolean) is
  'Atomically prices and creates an Adee''s Food order from the current menu catalog.';
comment on function public.post_stock_movement(uuid, text, numeric, bigint, text, text, uuid) is
  'Posts an immutable stock movement and updates the protected on-hand projection.';
comment on function public.get_report_summary(uuid, uuid, date, date) is
  'Returns live operational facts only; no synthetic analytics or typed revenue totals.';

commit;
