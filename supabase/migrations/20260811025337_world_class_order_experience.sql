-- Customer-facing order scheduling and privacy-preserving status tracking.
-- Images and payments remain outside this phase.

begin;

alter table public.orders
  add column if not exists requested_fulfillment_at timestamptz;

comment on column public.orders.requested_fulfillment_at is
  'Optional customer-requested pickup or delivery time. Stored as an absolute timestamp and displayed in Africa/Accra time.';

create index if not exists orders_scheduled_fulfillment_idx
  on public.orders (location_id, requested_fulfillment_at, created_at)
  where requested_fulfillment_at is not null
    and order_status in ('CONFIRMED', 'IN_PROGRESS');

create or replace function public.create_online_order_v2(
  p_location_id uuid,
  p_channel text,
  p_guest_name text,
  p_guest_phone text,
  p_items jsonb,
  p_source_reference uuid,
  p_requested_fulfillment_at timestamptz default null,
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
  v_result jsonb;
  v_order_id uuid;
  v_requested timestamptz;
begin
  if p_requested_fulfillment_at is not null then
    if p_requested_fulfillment_at < now() + interval '15 minutes' then
      raise exception using errcode = '22023', message = 'Choose a requested time at least 15 minutes from now';
    end if;
    if p_requested_fulfillment_at > now() + interval '7 days' then
      raise exception using errcode = '22023', message = 'Choose a requested time within the next 7 days';
    end if;
  end if;

  select public.create_online_order(
    p_location_id,
    p_channel,
    p_guest_name,
    p_guest_phone,
    p_items,
    p_source_reference,
    p_guest_email,
    p_delivery_address,
    p_notes
  ) into v_result;

  v_order_id := nullif(v_result ->> 'order_id', '')::uuid;
  if v_order_id is null then
    raise exception using errcode = '22023', message = 'The order could not be confirmed';
  end if;

  if p_requested_fulfillment_at is not null then
    update public.orders
    set requested_fulfillment_at = coalesce(requested_fulfillment_at, p_requested_fulfillment_at)
    where id = v_order_id
      and order_source = 'WEBSITE';
  end if;

  select o.requested_fulfillment_at into v_requested
  from public.orders o
  where o.id = v_order_id;

  return v_result || jsonb_build_object('requested_fulfillment_at', v_requested);
end;
$$;

comment on function public.create_online_order_v2(uuid, text, text, text, jsonb, uuid, timestamptz, text, text, text) is
  'Versioned anonymous website-order RPC. Delegates validation and server-side repricing to create_online_order, then stores an optional fulfillment request.';

create or replace function public.get_online_order_status(
  p_source_reference uuid,
  p_order_number text
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'order_number', o.order_number,
    'channel', o.channel,
    'order_status', o.order_status,
    'kitchen_status', o.kitchen_status,
    'payment_status', o.payment_status,
    'fulfillment_status', o.fulfillment_status,
    'currency_code', o.currency_code,
    'total_minor', o.total_minor,
    'requested_fulfillment_at', o.requested_fulfillment_at,
    'created_at', o.created_at,
    'updated_at', o.updated_at
  )
  from public.orders o
  where o.source_reference = p_source_reference
    and o.order_number = upper(btrim(p_order_number))
    and o.order_source = 'WEBSITE'
  limit 1;
$$;

comment on function public.get_online_order_status(uuid, text) is
  'Returns a deliberately limited, non-PII order status only when both an unguessable UUID reference and matching order number are supplied.';

revoke all on function public.create_online_order_v2(uuid, text, text, text, jsonb, uuid, timestamptz, text, text, text)
  from public, anon, authenticated;
revoke all on function public.get_online_order_status(uuid, text)
  from public, anon, authenticated;

grant execute on function public.create_online_order_v2(uuid, text, text, text, jsonb, uuid, timestamptz, text, text, text)
  to anon, authenticated;
grant execute on function public.get_online_order_status(uuid, text)
  to anon, authenticated;

notify pgrst, 'reload schema';

commit;
