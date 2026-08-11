-- Adee's Food has no dine-in service, so a separate multi-station Kitchen
-- Display System screen is unneeded overhead. Preparation is still tracked
-- (food still has to be cooked before pickup/dispatch), but staff now
-- advance it with one button directly on the Orders board instead of a
-- separate page. This RPC advances every ticket on an order at once instead
-- of requiring a per-ticket call, since most orders here are single-station.

create or replace function public.advance_order_kitchen(
  p_order_id uuid,
  p_next_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_from_status text;
begin
  select * into strict v_order from public.orders where id = p_order_id for update;

  if p_next_status = 'PREPARING' then
    perform private.require_permission('kitchen.start_ticket', v_order.organization_id, v_order.location_id, false);
    v_from_status := 'QUEUED';
    update public.kitchen_tickets set status = 'PREPARING', started_at = now()
    where order_id = p_order_id and status = 'QUEUED';
  elsif p_next_status = 'READY' then
    perform private.require_permission('kitchen.ready_ticket', v_order.organization_id, v_order.location_id, false);
    v_from_status := 'PREPARING';
    update public.kitchen_tickets set status = 'READY', ready_at = now()
    where order_id = p_order_id and status = 'PREPARING';
  else
    raise exception using errcode = '22023', message = 'Unsupported kitchen status';
  end if;

  if not found then
    raise exception using errcode = '55000', message = format('No tickets are %s for this order', v_from_status);
  end if;

  update public.orders o
  set kitchen_status = case
        when exists (select 1 from public.kitchen_tickets kt where kt.order_id = p_order_id and kt.status = 'PREPARING') then 'PREPARING'
        when exists (select 1 from public.kitchen_tickets kt where kt.order_id = p_order_id and kt.status = 'QUEUED') then 'QUEUED'
        when exists (select 1 from public.kitchen_tickets kt where kt.order_id = p_order_id and kt.status = 'READY') then 'READY'
        else 'SERVED'
      end,
      fulfillment_status = case
        when not exists (select 1 from public.kitchen_tickets kt where kt.order_id = p_order_id and kt.status not in ('READY', 'SERVED'))
          then 'READY_FOR_HANDOFF'
        else fulfillment_status
      end
  where o.id = p_order_id;
exception
  when no_data_found then
    raise exception using errcode = '22023', message = 'Order was not found';
end;
$$;

revoke all on function public.advance_order_kitchen(uuid, text) from public, anon;
grant execute on function public.advance_order_kitchen(uuid, text) to authenticated;

notify pgrst, 'reload schema';
