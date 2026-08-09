-- Secure public website ordering for Adee's Food.
-- Anonymous visitors can read the active catalog and submit a tightly validated
-- order through RPCs only. Direct table access remains protected by RLS.

begin;

alter table public.orders
  alter column created_by drop not null,
  add column order_source text not null default 'STAFF'
    check (order_source in ('STAFF', 'WEBSITE')),
  add column guest_name text
    check (guest_name is null or length(btrim(guest_name)) between 2 and 120),
  add column guest_phone text
    check (guest_phone is null or length(btrim(guest_phone)) between 7 and 30),
  add column guest_phone_normalized text
    check (guest_phone_normalized is null or guest_phone_normalized ~ '^\+[0-9]{9,15}$'),
  add column guest_email text
    check (guest_email is null or (guest_email = lower(guest_email) and length(guest_email) <= 254)),
  add column delivery_address text
    check (delivery_address is null or length(btrim(delivery_address)) between 5 and 500),
  add column source_reference uuid;

create unique index orders_source_reference_key
  on public.orders (location_id, source_reference)
  where source_reference is not null;

create index orders_public_rate_limit_idx
  on public.orders (location_id, guest_phone_normalized, created_at desc)
  where order_source = 'WEBSITE' and guest_phone_normalized is not null;

create or replace function public.get_public_menu(
  p_location_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_location_id uuid;
  v_location_name text;
  v_business_name text;
  v_currency_code text;
  v_categories jsonb;
begin
  select l.id, l.name, o.trading_name, o.default_currency_code
    into v_location_id, v_location_name, v_business_name, v_currency_code
  from public.locations l
  join public.organizations o on o.id = l.organization_id and o.is_active
  where l.is_active
    and (p_location_id is null or l.id = p_location_id)
  order by l.created_at, l.id
  limit 1;

  if v_location_id is null then
    raise exception using errcode = '22023', message = 'Online ordering is not available at this location';
  end if;

  select coalesce(jsonb_agg(category_row.payload order by category_row.sort_order, category_row.name), '[]'::jsonb)
    into v_categories
  from (
    select
      mc.sort_order,
      mc.name,
      jsonb_build_object(
        'id', mc.id,
        'name', mc.name,
        'description', mc.description,
        'items', coalesce((
          select jsonb_agg(item_row.payload order by item_row.name, item_row.id)
          from (
            select
              mi.id,
              mi.name,
              jsonb_build_object(
                'id', mi.id,
                'name', mi.name,
                'description', mi.description,
                'price_minor', mi.price_minor,
                'currency_code', mi.currency_code,
                'image_url', mi.image_url,
                'is_price_from', mi.is_price_from,
                'variants', coalesce((
                  select jsonb_agg(
                    jsonb_build_object(
                      'id', miv.id,
                      'name', miv.name,
                      'price_minor', miv.price_minor,
                      'currency_code', miv.currency_code,
                      'is_default', miv.is_default
                    ) order by miv.sort_order, miv.price_minor, miv.id
                  )
                  from public.menu_item_variants miv
                  where miv.menu_item_id = mi.id
                    and miv.location_id = v_location_id
                    and miv.is_active
                    and miv.is_available
                ), '[]'::jsonb),
                'modifier_groups', coalesce((
                  select jsonb_agg(
                    jsonb_build_object(
                      'id', mg.id,
                      'name', mg.name,
                      'selection_type', mg.selection_type,
                      'min_selections', mg.min_selections,
                      'max_selections', mg.max_selections,
                      'is_required', mg.is_required,
                      'options', coalesce((
                        select jsonb_agg(
                          jsonb_build_object(
                            'id', mo.id,
                            'name', mo.name,
                            'price_delta_minor', mo.price_delta_minor,
                            'currency_code', mo.currency_code
                          ) order by mo.sort_order, mo.name, mo.id
                        )
                        from public.modifier_options mo
                        where mo.modifier_group_id = mg.id
                          and mo.location_id = v_location_id
                          and mo.is_active
                          and mo.is_available
                      ), '[]'::jsonb)
                    ) order by mimg.sort_order, mg.sort_order, mg.name, mg.id
                  )
                  from public.menu_item_modifier_groups mimg
                  join public.modifier_groups mg
                    on mg.id = mimg.modifier_group_id
                   and mg.location_id = v_location_id
                   and mg.is_active
                  where mimg.menu_item_id = mi.id
                    and mimg.location_id = v_location_id
                ), '[]'::jsonb)
              ) as payload
            from public.menu_item_categories mic
            join public.menu_items mi
              on mi.id = mic.menu_item_id
             and mi.location_id = v_location_id
             and mi.is_active
             and mi.is_available
            where mic.category_id = mc.id
              and mic.location_id = v_location_id
          ) item_row
        ), '[]'::jsonb)
      ) as payload
    from public.menu_categories mc
    where mc.location_id = v_location_id
      and mc.is_active
      and exists (
        select 1
        from public.menu_item_categories mic
        join public.menu_items mi on mi.id = mic.menu_item_id
        where mic.category_id = mc.id
          and mi.location_id = v_location_id
          and mi.is_active
          and mi.is_available
      )
  ) category_row;

  return jsonb_build_object(
    'location_id', v_location_id,
    'location_name', v_location_name,
    'business_name', v_business_name,
    'currency_code', v_currency_code,
    'categories', v_categories
  );
end;
$$;

comment on function public.get_public_menu(uuid) is
  'Intentional public RPC exposing only active, available customer-facing menu fields. Internal SKUs, stations, source notes, and staff metadata are omitted.';

create or replace function public.create_online_order(
  p_location_id uuid,
  p_channel text,
  p_guest_name text,
  p_guest_phone text,
  p_items jsonb,
  p_source_reference uuid,
  p_guest_email text default null,
  p_delivery_address text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid;
  v_currency text;
  v_order_id uuid;
  v_order_item_id uuid;
  v_order_number text;
  v_item jsonb;
  v_menu_item public.menu_items%rowtype;
  v_variant public.menu_item_variants%rowtype;
  v_quantity integer;
  v_subtotal bigint := 0;
  v_unit_price bigint;
  v_line_total bigint;
  v_modifier_total bigint;
  v_modifier_count integer;
  v_distinct_modifier_count integer;
  v_group record;
  v_selected_count integer;
  v_guest_name text := btrim(coalesce(p_guest_name, ''));
  v_guest_phone text := btrim(coalesce(p_guest_phone, ''));
  v_phone_digits text;
  v_phone_normalized text;
  v_guest_email text := lower(nullif(btrim(coalesce(p_guest_email, '')), ''));
  v_delivery_address text := nullif(btrim(coalesce(p_delivery_address, '')), '');
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  v_existing record;
begin
  select l.organization_id, o.default_currency_code
    into v_organization_id, v_currency
  from public.locations l
  join public.organizations o on o.id = l.organization_id and o.is_active
  where l.id = p_location_id and l.is_active;

  if v_organization_id is null then
    raise exception using errcode = '22023', message = 'Online ordering is not available at this location';
  end if;

  p_channel := upper(btrim(coalesce(p_channel, '')));
  if p_channel not in ('TAKEAWAY', 'DELIVERY') then
    raise exception using errcode = '22023', message = 'Choose pickup or delivery';
  end if;
  if length(v_guest_name) not between 2 and 120 then
    raise exception using errcode = '22023', message = 'Enter the name for this order';
  end if;

  v_phone_digits := regexp_replace(v_guest_phone, '[^0-9]', '', 'g');
  if left(v_phone_digits, 2) = '00' then
    v_phone_digits := substring(v_phone_digits from 3);
  end if;
  if left(v_phone_digits, 1) = '0' and length(v_phone_digits) = 10 then
    v_phone_digits := '233' || substring(v_phone_digits from 2);
  elsif length(v_phone_digits) = 9 then
    v_phone_digits := '233' || v_phone_digits;
  end if;
  if length(v_phone_digits) not between 9 and 15 then
    raise exception using errcode = '22023', message = 'Enter a valid phone number';
  end if;
  v_phone_normalized := '+' || v_phone_digits;

  if v_guest_email is not null and (
    length(v_guest_email) > 254
    or v_guest_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ) then
    raise exception using errcode = '22023', message = 'Enter a valid email address or leave it blank';
  end if;
  if p_channel = 'DELIVERY' and (v_delivery_address is null or length(v_delivery_address) < 5) then
    raise exception using errcode = '22023', message = 'Enter the delivery address';
  end if;
  if v_delivery_address is not null and length(v_delivery_address) > 500 then
    raise exception using errcode = '22023', message = 'Delivery address is too long';
  end if;
  if v_notes is not null and length(v_notes) > 500 then
    raise exception using errcode = '22023', message = 'Order note is too long';
  end if;
  if p_source_reference is null then
    raise exception using errcode = '22023', message = 'Order reference is required';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception using errcode = '22023', message = 'Add at least one item to your order';
  end if;
  if jsonb_array_length(p_items) > 50 then
    raise exception using errcode = '22023', message = 'This order has too many separate items';
  end if;

  select o.id, o.order_number, o.total_minor, o.currency_code, o.order_status,
         o.guest_phone_normalized
    into v_existing
  from public.orders o
  where o.location_id = p_location_id and o.source_reference = p_source_reference;

  if v_existing.id is not null then
    if v_existing.guest_phone_normalized <> v_phone_normalized then
      raise exception using errcode = '22023', message = 'This order reference has already been used';
    end if;
    return jsonb_build_object(
      'order_id', v_existing.id,
      'order_number', v_existing.order_number,
      'total_minor', v_existing.total_minor,
      'currency_code', v_existing.currency_code,
      'status', v_existing.order_status
    );
  end if;

  if (
    select count(*)
    from public.orders o
    where o.location_id = p_location_id
      and o.order_source = 'WEBSITE'
      and o.guest_phone_normalized = v_phone_normalized
      and o.created_at >= now() - interval '15 minutes'
  ) >= 5 then
    raise exception using errcode = '54000', message = 'Too many recent orders. Please wait a few minutes or call the restaurant.';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception using errcode = '22023', message = 'An order item is invalid';
    end if;
    v_quantity := coalesce((v_item ->> 'quantity')::integer, 0);
    if v_quantity < 1 or v_quantity > 20 then
      raise exception using errcode = '22023', message = 'Each item quantity must be between 1 and 20';
    end if;
    if nullif(btrim(v_item ->> 'notes'), '') is not null and length(btrim(v_item ->> 'notes')) > 250 then
      raise exception using errcode = '22023', message = 'An item note is too long';
    end if;

    select * into strict v_menu_item
    from public.menu_items mi
    where mi.id = (v_item ->> 'menu_item_id')::uuid
      and mi.organization_id = v_organization_id
      and mi.location_id = p_location_id
      and mi.is_active and mi.is_available
    for share;

    v_variant := null;
    if nullif(v_item ->> 'menu_item_variant_id', '') is not null then
      select * into strict v_variant
      from public.menu_item_variants miv
      where miv.id = (v_item ->> 'menu_item_variant_id')::uuid
        and miv.menu_item_id = v_menu_item.id
        and miv.organization_id = v_organization_id
        and miv.location_id = p_location_id
        and miv.is_active and miv.is_available
      for share;
    else
      select * into v_variant
      from public.menu_item_variants miv
      where miv.menu_item_id = v_menu_item.id
        and miv.organization_id = v_organization_id
        and miv.location_id = p_location_id
        and miv.is_default and miv.is_active and miv.is_available
      order by miv.sort_order, miv.id
      limit 1;
    end if;

    if exists (
      select 1 from public.menu_item_variants miv
      where miv.menu_item_id = v_menu_item.id and miv.is_active and miv.is_available
    ) and v_variant.id is null then
      raise exception using errcode = '22023', message = 'Choose an available size or portion';
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
      raise exception using errcode = '22023', message = 'A choice cannot be selected twice';
    end if;

    select count(*), coalesce(sum(mo.price_delta_minor), 0)
      into v_selected_count, v_modifier_total
    from jsonb_array_elements_text(coalesce(v_item -> 'modifier_option_ids', '[]'::jsonb)) selected(value)
    join public.modifier_options mo on mo.id = selected.value::uuid
    join public.menu_item_modifier_groups link
      on link.modifier_group_id = mo.modifier_group_id
     and link.menu_item_id = v_menu_item.id
    join public.modifier_groups mg on mg.id = mo.modifier_group_id
    where mo.organization_id = v_organization_id
      and mo.location_id = p_location_id
      and mo.is_active and mo.is_available and mg.is_active;
    if v_selected_count <> v_modifier_count then
      raise exception using errcode = '22023', message = 'A selected choice is unavailable for this item';
    end if;

    for v_group in
      select mg.id, mg.name, mg.min_selections, mg.max_selections
      from public.menu_item_modifier_groups link
      join public.modifier_groups mg on mg.id = link.modifier_group_id
      where link.menu_item_id = v_menu_item.id
        and link.location_id = p_location_id
        and mg.is_active
    loop
      select count(*) into v_selected_count
      from jsonb_array_elements_text(coalesce(v_item -> 'modifier_option_ids', '[]'::jsonb)) selected(value)
      join public.modifier_options mo on mo.id = selected.value::uuid
      where mo.modifier_group_id = v_group.id;
      if v_selected_count < v_group.min_selections or v_selected_count > v_group.max_selections then
        raise exception using errcode = '22023',
          message = format('%s requires between %s and %s choices', v_group.name, v_group.min_selections, v_group.max_selections);
      end if;
    end loop;

    v_unit_price := coalesce(v_variant.price_minor, v_menu_item.price_minor) + v_modifier_total;
    v_line_total := v_unit_price * v_quantity;
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  v_order_number := 'AF-' || to_char(timezone('Africa/Accra', now()), 'YYYYMMDD') || '-' ||
    lpad(nextval('public.order_number_seq')::text, 6, '0');

  insert into public.orders (
    organization_id, location_id, order_number, channel, order_source,
    guest_name, guest_phone, guest_phone_normalized, guest_email,
    delivery_address, source_reference, order_status, kitchen_status,
    currency_code, subtotal_minor, total_minor, notes, created_by
  ) values (
    v_organization_id, p_location_id, v_order_number, p_channel, 'WEBSITE',
    v_guest_name, v_guest_phone, v_phone_normalized, v_guest_email,
    case when p_channel = 'DELIVERY' then v_delivery_address else null end,
    p_source_reference, 'CONFIRMED', 'NOT_SENT', v_currency,
    v_subtotal, v_subtotal, v_notes, null
  ) returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_quantity := (v_item ->> 'quantity')::integer;
    select * into strict v_menu_item
    from public.menu_items
    where id = (v_item ->> 'menu_item_id')::uuid
      and organization_id = v_organization_id
      and location_id = p_location_id;

    v_variant := null;
    if nullif(v_item ->> 'menu_item_variant_id', '') is not null then
      select * into strict v_variant
      from public.menu_item_variants
      where id = (v_item ->> 'menu_item_variant_id')::uuid
        and menu_item_id = v_menu_item.id;
    else
      select * into v_variant
      from public.menu_item_variants
      where menu_item_id = v_menu_item.id
        and is_default and is_active and is_available
      order by sort_order, id
      limit 1;
    end if;

    select coalesce(sum(mo.price_delta_minor), 0) into v_modifier_total
    from jsonb_array_elements_text(coalesce(v_item -> 'modifier_option_ids', '[]'::jsonb)) selected(value)
    join public.modifier_options mo on mo.id = selected.value::uuid;
    v_unit_price := coalesce(v_variant.price_minor, v_menu_item.price_minor) + v_modifier_total;
    v_line_total := v_unit_price * v_quantity;

    insert into public.order_items (
      organization_id, location_id, order_id, menu_item_id, menu_item_variant_id,
      item_name, variant_name, sku, station, quantity, unit_price_minor,
      line_total_minor, notes
    ) values (
      v_organization_id, p_location_id, v_order_id, v_menu_item.id, v_variant.id,
      v_menu_item.name, v_variant.name, v_menu_item.sku, v_menu_item.station,
      v_quantity, v_unit_price, v_line_total, nullif(btrim(v_item ->> 'notes'), '')
    ) returning id into v_order_item_id;

    insert into public.order_item_modifiers (
      organization_id, location_id, order_item_id, modifier_group_id,
      modifier_option_id, group_name, option_name, price_delta_minor
    )
    select
      v_organization_id, p_location_id, v_order_item_id, mg.id,
      mo.id, mg.name, mo.name, mo.price_delta_minor
    from jsonb_array_elements_text(coalesce(v_item -> 'modifier_option_ids', '[]'::jsonb)) selected(value)
    join public.modifier_options mo on mo.id = selected.value::uuid
    join public.modifier_groups mg on mg.id = mo.modifier_group_id;
  end loop;

  return jsonb_build_object(
    'order_id', v_order_id,
    'order_number', v_order_number,
    'total_minor', v_subtotal,
    'currency_code', v_currency,
    'status', 'CONFIRMED'
  );
exception
  when no_data_found or invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '22023', message = 'An order item, size, or choice is unavailable or invalid';
  when unique_violation then
    select o.id, o.order_number, o.total_minor, o.currency_code, o.order_status,
           o.guest_phone_normalized
      into v_existing
    from public.orders o
    where o.location_id = p_location_id and o.source_reference = p_source_reference;
    if v_existing.id is not null and v_existing.guest_phone_normalized = v_phone_normalized then
      return jsonb_build_object(
        'order_id', v_existing.id,
        'order_number', v_existing.order_number,
        'total_minor', v_existing.total_minor,
        'currency_code', v_existing.currency_code,
        'status', v_existing.order_status
      );
    end if;
    raise exception using errcode = '22023', message = 'This order could not be submitted. Please refresh and try again.';
end;
$$;

comment on function public.create_online_order(uuid, text, text, text, jsonb, uuid, text, text, text) is
  'Intentional anonymous website-order RPC. It validates and reprices every item server-side, enforces modifier rules, limits request volume, and uses a UUID idempotency key.';

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

  if p_action = 'SEND_KITCHEN' then
    perform private.require_permission('orders.send_kitchen', v_order.organization_id, v_order.location_id, false);
    if v_order.order_status <> 'CONFIRMED' or v_order.kitchen_status <> 'NOT_SENT' then
      raise exception using errcode = '55000', message = 'Only a new confirmed order can be accepted';
    end if;
    if not exists (select 1 from public.order_items where order_id = p_order_id) then
      raise exception using errcode = '55000', message = 'This order has no items';
    end if;

    insert into public.kitchen_tickets (
      organization_id, location_id, order_id, ticket_number, station
    )
    select
      v_order.organization_id,
      v_order.location_id,
      p_order_id,
      'K-' || v_order.order_number || '-' || row_number() over (order by item_stations.station),
      item_stations.station
    from (
      select distinct oi.station
      from public.order_items oi
      where oi.order_id = p_order_id
    ) item_stations
    on conflict (order_id, station) do nothing;

    update public.orders
    set order_status = 'IN_PROGRESS', kitchen_status = 'QUEUED'
    where id = p_order_id;
  elsif p_action = 'CANCEL' then
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

revoke all on function public.get_public_menu(uuid) from public, anon, authenticated;
revoke all on function public.create_online_order(uuid, text, text, text, jsonb, uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.advance_order(uuid, text, text) from public, anon, authenticated;

grant execute on function public.get_public_menu(uuid) to anon, authenticated;
grant execute on function public.create_online_order(uuid, text, text, text, jsonb, uuid, text, text, text) to anon, authenticated;
grant execute on function public.advance_order(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
