-- Staff POS orders (walk-in, phone, whatsapp, delivery) had no way to record a
-- guest's name, phone, or delivery address unless a full customer profile was
-- created first. This extends create_order with the same optional guest
-- fields already used by the public ordering RPC, so front-of-house staff can
-- take an order for anyone without leaving the POS.

create or replace function public.create_order(
  p_organization_id uuid,
  p_location_id uuid,
  p_channel text,
  p_items jsonb,
  p_customer_id uuid default null,
  p_table_id uuid default null,
  p_notes text default null,
  p_send_to_kitchen boolean default true,
  p_guest_name text default null,
  p_guest_phone text default null,
  p_guest_email text default null,
  p_delivery_address text default null
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
  v_guest_name text := nullif(btrim(coalesce(p_guest_name, '')), '');
  v_guest_phone text := nullif(btrim(coalesce(p_guest_phone, '')), '');
  v_guest_email text := lower(nullif(btrim(coalesce(p_guest_email, '')), ''));
  v_delivery_address text := nullif(btrim(coalesce(p_delivery_address, '')), '');
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
  if v_guest_name is not null and length(v_guest_name) not between 2 and 120 then
    raise exception using errcode = '22023', message = 'Guest name must be between 2 and 120 characters';
  end if;
  if v_guest_phone is not null and length(v_guest_phone) not between 6 and 30 then
    raise exception using errcode = '22023', message = 'Enter a valid guest phone number';
  end if;
  if v_guest_email is not null and (
    length(v_guest_email) > 254
    or v_guest_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ) then
    raise exception using errcode = '22023', message = 'Enter a valid guest email or leave it blank';
  end if;
  if p_channel = 'DELIVERY' and (v_delivery_address is null or length(v_delivery_address) < 5) then
    raise exception using errcode = '22023', message = 'Enter the delivery address';
  end if;
  if v_delivery_address is not null and length(v_delivery_address) > 500 then
    raise exception using errcode = '22023', message = 'Delivery address is too long';
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
    subtotal_minor, total_minor, notes,
    guest_name, guest_phone, guest_email, delivery_address
  ) values (
    p_organization_id, p_location_id, v_order_number, p_channel, p_customer_id,
    p_table_id, case when p_send_to_kitchen then 'IN_PROGRESS' else 'CONFIRMED' end,
    case when p_send_to_kitchen then 'QUEUED' else 'NOT_SENT' end,
    v_currency, v_subtotal, v_subtotal, nullif(btrim(p_notes), ''),
    v_guest_name, v_guest_phone, v_guest_email, v_delivery_address
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

revoke all on function public.create_order(uuid, uuid, text, jsonb, uuid, uuid, text, boolean, text, text, text, text) from public, anon;
grant execute on function public.create_order(uuid, uuid, text, jsonb, uuid, uuid, text, boolean, text, text, text, text) to authenticated;

drop function if exists public.create_order(uuid, uuid, text, jsonb, uuid, uuid, text, boolean);

notify pgrst, 'reload schema';
