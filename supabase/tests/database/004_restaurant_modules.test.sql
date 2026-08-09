begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(25);

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = any(array[
        'menu_categories', 'menu_items', 'customers', 'restaurant_tables',
        'reservations', 'orders', 'order_items', 'payments', 'kitchen_tickets',
        'inventory_categories', 'inventory_items', 'stock_movements', 'recipes',
        'recipe_ingredients', 'suppliers', 'purchase_orders', 'purchase_order_lines',
        'expenses', 'daily_closes', 'staff_shifts', 'operational_settings'
      ])
  ),
  21,
  'all restaurant management module tables exist'
);

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = any(array[
        'menu_categories', 'menu_items', 'customers', 'restaurant_tables',
        'reservations', 'orders', 'order_items', 'payments', 'kitchen_tickets',
        'inventory_categories', 'inventory_items', 'stock_movements', 'recipes',
        'recipe_ingredients', 'suppliers', 'purchase_orders', 'purchase_order_lines',
        'expenses', 'daily_closes', 'staff_shifts', 'operational_settings'
      ])
      and c.relrowsecurity
      and c.relforcerowsecurity
  ),
  21,
  'every module table enables and forces row-level security'
);

select ok(
  to_regprocedure('public.create_order(uuid,uuid,text,jsonb,uuid,uuid,text,boolean)') is not null
  and to_regprocedure('public.record_order_payment(uuid,text,bigint,text)') is not null
  and to_regprocedure('public.advance_kitchen_ticket(uuid,text)') is not null
  and to_regprocedure('public.post_stock_movement(uuid,text,numeric,bigint,text,text,uuid)') is not null
  and to_regprocedure('public.create_purchase_order(uuid,uuid,uuid,uuid,numeric,bigint,date,text)') is not null
  and to_regprocedure('public.get_dashboard_metrics(uuid,uuid,date)') is not null
  and to_regprocedure('public.get_report_summary(uuid,uuid,date,date)') is not null,
  'critical command and reporting functions exist'
);

select ok(
  not has_function_privilege('anon', 'public.rls_auto_enable()', 'execute'),
  'anonymous clients cannot execute the RLS event-trigger helper'
);

insert into public.organizations (id, legal_name, trading_name, default_currency_code)
values (
  '11000000-0000-4000-8000-000000000021',
  'Adee Module Test Limited',
  'Adee Module Test',
  'GHS'
);

insert into public.locations (id, organization_id, code, name, timezone)
values (
  '21000000-0000-4000-8000-000000000021',
  '11000000-0000-4000-8000-000000000021',
  'MODULE_TEST',
  'Module Test Location',
  'Africa/Accra'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  '31000000-0000-4000-8000-000000000021',
  'module-owner@adee.test',
  '{"display_name":"Module Test Owner"}'::jsonb
);

update public.profiles
set is_active = true
where id = '31000000-0000-4000-8000-000000000021';

insert into public.staff_employments (organization_id, profile_id, employee_number)
values (
  '11000000-0000-4000-8000-000000000021',
  '31000000-0000-4000-8000-000000000021',
  'MODULE-OWNER'
);

insert into public.user_role_assignments (organization_id, profile_id, role_id)
select
  '11000000-0000-4000-8000-000000000021',
  '31000000-0000-4000-8000-000000000021',
  id
from public.roles
where code = 'OWNER';

select set_config(
  'request.jwt.claims',
  '{"sub":"31000000-0000-4000-8000-000000000021","role":"authenticated","aal":"aal2"}',
  true
);

insert into public.menu_categories (
  id, organization_id, location_id, name
) values (
  '41000000-0000-4000-8000-000000000021',
  '11000000-0000-4000-8000-000000000021',
  '21000000-0000-4000-8000-000000000021',
  'Test Mains'
);

insert into public.menu_items (
  id, organization_id, location_id, category_id, sku, name, price_minor, station
) values (
  '51000000-0000-4000-8000-000000000021',
  '11000000-0000-4000-8000-000000000021',
  '21000000-0000-4000-8000-000000000021',
  '41000000-0000-4000-8000-000000000021',
  'TEST-MAIN-1',
  'Test Main',
  5000,
  'MAIN KITCHEN'
);

insert into public.restaurant_tables (
  id, organization_id, location_id, code, capacity
) values (
  '61000000-0000-4000-8000-000000000021',
  '11000000-0000-4000-8000-000000000021',
  '21000000-0000-4000-8000-000000000021',
  'T21',
  4
);

insert into public.inventory_categories (
  id, organization_id, location_id, name
) values (
  '71000000-0000-4000-8000-000000000021',
  '11000000-0000-4000-8000-000000000021',
  '21000000-0000-4000-8000-000000000021',
  'Test Ingredients'
);

insert into public.inventory_items (
  id, organization_id, location_id, category_id, sku, name, unit
) values (
  '81000000-0000-4000-8000-000000000021',
  '11000000-0000-4000-8000-000000000021',
  '21000000-0000-4000-8000-000000000021',
  '71000000-0000-4000-8000-000000000021',
  'TEST-ING-1',
  'Test Ingredient',
  'kg'
);

insert into public.suppliers (
  id, organization_id, location_id, code, name
) values (
  '91000000-0000-4000-8000-000000000021',
  '11000000-0000-4000-8000-000000000021',
  '21000000-0000-4000-8000-000000000021',
  'SUP-21',
  'Test Supplier'
);

create temporary table created_order as
select public.create_order(
  '11000000-0000-4000-8000-000000000021',
  '21000000-0000-4000-8000-000000000021',
  'DINE_IN',
  '[{"menu_item_id":"51000000-0000-4000-8000-000000000021","quantity":2}]'::jsonb,
  null,
  '61000000-0000-4000-8000-000000000021',
  'Module workflow test',
  true
) as id;

select ok((select id is not null from created_order), 'POS creates an order atomically');
select is(
  (select total_minor from public.orders where id = (select id from created_order)),
  10000::bigint,
  'order total is calculated from the trusted menu price'
);
select is(
  (select status from public.kitchen_tickets where order_id = (select id from created_order)),
  'QUEUED',
  'sending an order creates a queued kitchen ticket'
);
select is(
  (select status from public.restaurant_tables where id = '61000000-0000-4000-8000-000000000021'),
  'OCCUPIED',
  'dine-in order marks its table occupied'
);

select lives_ok(
  format(
    'select public.advance_kitchen_ticket(%L::uuid, ''PREPARING'')',
    (select id from public.kitchen_tickets where order_id = (select id from created_order))
  ),
  'kitchen can start a queued ticket'
);
select is(
  (select status from public.kitchen_tickets where order_id = (select id from created_order)),
  'PREPARING',
  'ticket status advances to preparing'
);
select lives_ok(
  format(
    'select public.advance_kitchen_ticket(%L::uuid, ''READY'')',
    (select id from public.kitchen_tickets where order_id = (select id from created_order))
  ),
  'kitchen can mark a preparing ticket ready'
);
select lives_ok(
  format(
    'select public.advance_kitchen_ticket(%L::uuid, ''SERVED'')',
    (select id from public.kitchen_tickets where order_id = (select id from created_order))
  ),
  'service can mark a ready ticket served'
);
select is(
  (select kitchen_status from public.orders where id = (select id from created_order)),
  'SERVED',
  'order kitchen projection follows its ticket state'
);

select lives_ok(
  format(
    'select public.record_order_payment(%L::uuid, ''CASH'', 10000, null)',
    (select id from created_order)
  ),
  'cashier can record the exact outstanding payment'
);
select ok(
  (select payment_status = 'PAID' and order_status = 'COMPLETED'
   from public.orders where id = (select id from created_order)),
  'paid and served order completes'
);

select lives_ok(
  $$select public.post_stock_movement(
    '81000000-0000-4000-8000-000000000021',
    'ADJUSTMENT_IN', 5, 200, 'Opening test stock', null, null
  )$$,
  'inventory command posts an opening stock movement'
);
select ok(
  (select current_stock = 5 and average_cost_minor = 200
   from public.inventory_items where id = '81000000-0000-4000-8000-000000000021'),
  'stock projection and average cost update together'
);

create temporary table created_purchase as
select public.create_purchase_order(
  '11000000-0000-4000-8000-000000000021',
  '21000000-0000-4000-8000-000000000021',
  '91000000-0000-4000-8000-000000000021',
  '81000000-0000-4000-8000-000000000021',
  3,
  250,
  current_date + 1,
  'Module workflow test'
) as id;

select ok((select id is not null from created_purchase), 'purchasing creates an issued purchase order');
select is(
  (select status from public.purchase_orders where id = (select id from created_purchase)),
  'ORDERED',
  'new purchase order is ready for receiving'
);
select lives_ok(
  format('select public.receive_purchase_order(%L::uuid)', (select id from created_purchase)),
  'receiving posts the goods into inventory'
);
select ok(
  (select po.status = 'RECEIVED' and ii.current_stock = 8
   from public.purchase_orders po
   cross join public.inventory_items ii
   where po.id = (select id from created_purchase)
     and ii.id = '81000000-0000-4000-8000-000000000021'),
  'received purchase and on-hand stock remain consistent'
);

select is(
  (public.get_dashboard_metrics(
    '11000000-0000-4000-8000-000000000021',
    '21000000-0000-4000-8000-000000000021',
    (timezone('Africa/Accra', now()))::date
  ) ->> 'sales_minor')::bigint,
  10000::bigint,
  'dashboard metrics use recorded payments'
);
select is(
  (public.get_report_summary(
    '11000000-0000-4000-8000-000000000021',
    '21000000-0000-4000-8000-000000000021',
    (timezone('Africa/Accra', now()))::date,
    (timezone('Africa/Accra', now()))::date
  ) ->> 'payments_minor')::bigint,
  10000::bigint,
  'report summary reconciles to payment records'
);

set local role authenticated;
select throws_ok(
  $$update public.inventory_items
    set current_stock = 99
    where id = '81000000-0000-4000-8000-000000000021'$$,
  '55000',
  'Inventory balances may change only through stock movements',
  'direct inventory balance edits are blocked'
);
update public.stock_movements
set reason = 'Edited history'
where inventory_item_id = '81000000-0000-4000-8000-000000000021';
select ok(
  not exists (
    select 1 from public.stock_movements
    where inventory_item_id = '81000000-0000-4000-8000-000000000021'
      and reason = 'Edited history'
  ),
  'authenticated clients cannot mutate immutable stock history'
);

select * from finish();
rollback;
