begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(22);

insert into public.organizations (id, legal_name, trading_name)
values
  ('10000000-0000-4000-8000-000000000001', 'Adee Test One Limited', 'Adee Test One'),
  ('10000000-0000-4000-8000-000000000002', 'Adee Test Two Limited', 'Adee Test Two');

insert into public.locations (id, organization_id, code, name)
values
  (
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'TEST_A',
    'Test Location A'
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000002',
    'TEST_B',
    'Test Location B'
  );

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '30000000-0000-4000-8000-000000000001',
    'receptionist@adee.test',
    '{"display_name":"Test Receptionist"}'::jsonb
  ),
  (
    '30000000-0000-4000-8000-000000000002',
    'manager@adee.test',
    '{"display_name":"Test Manager"}'::jsonb
  ),
  (
    '30000000-0000-4000-8000-000000000003',
    'owner@adee.test',
    '{"display_name":"Test Owner"}'::jsonb
  ),
  (
    '30000000-0000-4000-8000-000000000004',
    'outsider@adee.test',
    '{"display_name":"Other Location User"}'::jsonb
  );

update public.profiles
set is_active = true
where id in (
  '30000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000003',
  '30000000-0000-4000-8000-000000000004'
);

insert into public.staff_employments (
  organization_id,
  profile_id,
  employee_number
)
values
  (
    '10000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    'TEST-REC'
  ),
  (
    '10000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000002',
    'TEST-MGR'
  ),
  (
    '10000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000003',
    'TEST-OWN'
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000004',
    'TEST-OUT'
  );

insert into public.user_role_assignments (
  organization_id,
  location_id,
  profile_id,
  role_id
)
select
  assignment.organization_id,
  assignment.location_id,
  assignment.profile_id,
  r.id
from (
  values
    (
      '10000000-0000-4000-8000-000000000001'::uuid,
      '20000000-0000-4000-8000-000000000001'::uuid,
      '30000000-0000-4000-8000-000000000001'::uuid,
      'RECEPTIONIST'::text
    ),
    (
      '10000000-0000-4000-8000-000000000001'::uuid,
      '20000000-0000-4000-8000-000000000001'::uuid,
      '30000000-0000-4000-8000-000000000002'::uuid,
      'MANAGER'::text
    ),
    (
      '10000000-0000-4000-8000-000000000001'::uuid,
      null::uuid,
      '30000000-0000-4000-8000-000000000003'::uuid,
      'OWNER'::text
    ),
    (
      '10000000-0000-4000-8000-000000000002'::uuid,
      '20000000-0000-4000-8000-000000000002'::uuid,
      '30000000-0000-4000-8000-000000000004'::uuid,
      'RECEPTIONIST'::text
    )
) as assignment (organization_id, location_id, profile_id, role_code)
join public.roles r on r.code = assignment.role_code;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',
  true
);

select ok(
  private.has_permission(
    'orders.create',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001'
  ),
  'receptionist can create an order in the assigned location'
);
select ok(
  not private.has_permission(
    'security.manage_users_roles',
    '10000000-0000-4000-8000-000000000001',
    null
  ),
  'receptionist cannot manage users or roles'
);
select results_eq(
  $$select count(*) from public.organizations$$,
  $$values (1::bigint)$$,
  'receptionist sees only their assigned organization'
);
select results_eq(
  $$select count(*) from public.locations$$,
  $$values (1::bigint)$$,
  'receptionist sees only their assigned location'
);
select results_eq(
  $$select count(*) from public.profiles$$,
  $$values (1::bigint)$$,
  'receptionist sees only their own staff profile'
);
select is(
  (public.get_my_access_context() -> 'assignments' -> 0 ->> 'role_code'),
  'RECEPTIONIST',
  'access context returns receptionist role'
);
select ok(
  (public.get_my_access_context() -> 'permissions') ? 'orders.create',
  'access context includes granted order permission'
);
select throws_ok(
  $$update public.organizations set trading_name = 'Tampered'$$,
  '42501',
  null,
  'authenticated staff cannot update organization rows directly'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}',
  true
);
select ok(
  private.has_permission(
    'inventory.view_on_hand',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001'
  ),
  'manager can view inventory in the assigned location'
);
select ok(
  not private.has_permission(
    'security.manage_users_roles',
    '10000000-0000-4000-8000-000000000001',
    null
  ),
  'location manager cannot use owner security permissions'
);
select results_eq(
  $$select count(*) from public.profiles$$,
  $$values (2::bigint)$$,
  'manager sees staff assigned to the same location but not organization-wide owner data'
);
select ok(
  private.has_permission(
    'audit.view_location',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001'
  ),
  'manager can view location audit records'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000003","role":"authenticated","aal":"aal1"}',
  true
);
select ok(
  private.has_permission(
    'security.manage_users_roles',
    '10000000-0000-4000-8000-000000000001',
    null
  ),
  'organization-wide owner can manage users and roles'
);
select ok(not private.has_aal2(), 'aal1 owner session does not satisfy MFA requirement');

select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000003","role":"authenticated","aal":"aal2"}',
  true
);
select ok(private.has_aal2(), 'aal2 owner session satisfies MFA requirement');
select results_eq(
  $$select count(*) from public.profiles$$,
  $$values (3::bigint)$$,
  'organization-wide owner sees every staff profile in their organization'
);
select results_eq(
  $$select count(*) from public.organizations$$,
  $$values (1::bigint)$$,
  'owner does not see another organization'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000004","role":"authenticated","aal":"aal1"}',
  true
);
select results_eq(
  $$select id from public.organizations$$,
  $$values ('10000000-0000-4000-8000-000000000002'::uuid)$$,
  'other-organization user sees only their own organization'
);
select ok(
  not private.has_permission(
    'orders.create',
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001'
  ),
  'other-organization user cannot act in Adee Test One'
);

reset role;
select set_config('request.jwt.claims', '{}', true);

select throws_ok(
  $$update public.audit_events set reason = 'changed' where id = (select min(id) from public.audit_events)$$,
  '55000',
  null,
  'audit events cannot be updated even by a privileged maintenance session'
);

set local role anon;
select throws_ok(
  $$select * from public.organizations$$,
  '42501',
  null,
  'anonymous callers cannot query organization data'
);

reset role;
select set_config('request.jwt.claims', '{}', true);
update public.user_role_assignments
set revoked_at = clock_timestamp(),
    revoked_by = '30000000-0000-4000-8000-000000000003',
    revocation_reason = 'Access test revocation'
where profile_id = '30000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',
  true
);
select ok(
  not private.has_any_active_assignment(
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001'
  ),
  'revoked assignment removes access immediately'
);

select * from finish();
rollback;
