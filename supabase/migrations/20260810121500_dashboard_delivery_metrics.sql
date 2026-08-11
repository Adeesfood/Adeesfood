-- Extend get_dashboard_metrics with pickup/delivery signals, additively.
-- Dine-in fields (reservations_today, occupied_tables, available_tables) are
-- kept for backward compatibility; the app now only renders them when
-- operations.dine_in_enabled is on.

begin;

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
    'ready_for_pickup', (select count(*) from public.orders
      where organization_id = p_organization_id and location_id = p_location_id
        and channel = 'TAKEAWAY' and fulfillment_status = 'READY_FOR_HANDOFF'),
    'awaiting_rider', (select count(*) from public.deliveries
      where organization_id = p_organization_id and location_id = p_location_id
        and delivery_status = 'AWAITING_RIDER'),
    'deliveries_in_progress', (select count(*) from public.deliveries
      where organization_id = p_organization_id and location_id = p_location_id
        and delivery_status in ('ASSIGNED', 'ACCEPTED', 'PICKED_UP', 'ON_THE_WAY')),
    'delivered_today', (select count(*) from public.deliveries
      where organization_id = p_organization_id and location_id = p_location_id
        and delivery_status = 'DELIVERED'
        and (timezone('Africa/Accra', delivered_at))::date = p_business_date),
    'failed_deliveries_today', (select count(*) from public.deliveries
      where organization_id = p_organization_id and location_id = p_location_id
        and delivery_status = 'FAILED'
        and (timezone('Africa/Accra', failed_at))::date = p_business_date),
    'cod_held_minor', coalesce((select sum(cash_outstanding_minor) from public.rider_profiles
      where organization_id = p_organization_id and location_id = p_location_id), 0),
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

notify pgrst, 'reload schema';

commit;
