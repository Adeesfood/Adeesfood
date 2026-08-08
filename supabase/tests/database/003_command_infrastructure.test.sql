begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(11);

insert into public.organizations (id, legal_name, trading_name)
values (
  '10000000-0000-4000-8000-000000000011',
  'Adee Command Test Limited',
  'Adee Command Test'
);

insert into public.locations (id, organization_id, code, name)
values (
  '20000000-0000-4000-8000-000000000011',
  '10000000-0000-4000-8000-000000000011',
  'CMD_TEST',
  'Command Test Location'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  '30000000-0000-4000-8000-000000000011',
  'command-owner@adee.test',
  '{"display_name":"Command Test Owner"}'::jsonb
);

select ok(
  not (select is_active from public.profiles where id = '30000000-0000-4000-8000-000000000011'),
  'new Auth users are inactive until explicitly provisioned as staff'
);

update public.profiles
set is_active = true
where id = '30000000-0000-4000-8000-000000000011';

insert into public.staff_employments (
  organization_id,
  profile_id,
  employee_number
)
values (
  '10000000-0000-4000-8000-000000000011',
  '30000000-0000-4000-8000-000000000011',
  'CMD-OWNER'
);

insert into public.user_role_assignments (
  organization_id,
  profile_id,
  role_id
)
select
  '10000000-0000-4000-8000-000000000011',
  '30000000-0000-4000-8000-000000000011',
  id
from public.roles
where code = 'OWNER';

select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000011","role":"authenticated","aal":"aal2"}',
  true
);

create temporary table first_claim as
select *
from private.begin_idempotent_command(
  '10000000-0000-4000-8000-000000000011',
  '20000000-0000-4000-8000-000000000011',
  'orders.submit',
  'test-command-key-0001',
  '{"order_id":"test-order-1","version":1}'::jsonb
);

select ok(not (select is_replay from first_claim), 'first command claim is not a replay');
select ok((select idempotency_id is not null from first_claim), 'first command claim returns its durable id');

select lives_ok(
  format(
    $$select private.complete_idempotent_command(%L::uuid, '{"status":"CONFIRMED"}'::jsonb, 'order', 'test-order-1')$$,
    (select idempotency_id from first_claim)
  ),
  'an in-progress command can be completed once'
);

create temporary table replay_claim as
select *
from private.begin_idempotent_command(
  '10000000-0000-4000-8000-000000000011',
  '20000000-0000-4000-8000-000000000011',
  'orders.submit',
  'test-command-key-0001',
  '{"order_id":"test-order-1","version":1}'::jsonb
);

select ok((select is_replay from replay_claim), 'identical retry is returned as a replay');
select is(
  (select replay_response ->> 'status' from replay_claim),
  'CONFIRMED',
  'identical retry returns the original response'
);

select throws_ok(
  $$
    select *
    from private.begin_idempotent_command(
      '10000000-0000-4000-8000-000000000011',
      '20000000-0000-4000-8000-000000000011',
      'orders.submit',
      'test-command-key-0001',
      '{"order_id":"different-order","version":1}'::jsonb
    )
  $$,
  '22023',
  'Idempotency key was already used with a different request',
  'same key with a different request is rejected'
);

select lives_ok(
  $$
    select private.enqueue_outbox_event(
      '10000000-0000-4000-8000-000000000011',
      '20000000-0000-4000-8000-000000000011',
      'order',
      'test-order-1',
      1,
      'order.confirmed',
      '{"order_id":"test-order-1"}'::jsonb
    )
  $$,
  'a durable outbox event can be written with the command transaction'
);

select throws_ok(
  $$
    select private.enqueue_outbox_event(
      '10000000-0000-4000-8000-000000000011',
      '20000000-0000-4000-8000-000000000011',
      'order',
      'test-order-1',
      1,
      'order.confirmed',
      '{"order_id":"test-order-1"}'::jsonb
    )
  $$,
  '23505',
  null,
  'duplicate aggregate event version is rejected'
);

set local role authenticated;
select throws_ok(
  $$select * from private.idempotency_keys$$,
  '42501',
  null,
  'authenticated clients cannot query the private idempotency ledger'
);
select throws_ok(
  $$select * from private.outbox_events$$,
  '42501',
  null,
  'authenticated clients cannot query the private outbox ledger'
);

select * from finish();
rollback;
