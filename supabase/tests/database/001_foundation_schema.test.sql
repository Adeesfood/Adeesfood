begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(27);

select has_table('public', 'organizations', 'organizations table exists');
select has_table('public', 'locations', 'locations table exists');
select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'staff_employments', 'staff employments table exists');
select has_table('public', 'roles', 'roles table exists');
select has_table('public', 'permissions', 'permissions table exists');
select has_table('public', 'role_permissions', 'role permissions table exists');
select has_table('public', 'user_role_assignments', 'role assignments table exists');
select has_table('public', 'approval_policies', 'approval policies table exists');
select has_table('public', 'approval_requests', 'approval requests table exists');
select has_table('public', 'approval_decisions', 'approval decisions table exists');
select has_table('public', 'audit_events', 'audit events table exists');
select has_table('private', 'idempotency_keys', 'private idempotency table exists');
select has_table('private', 'outbox_events', 'private outbox table exists');

select has_function(
  'private',
  'has_permission',
  array['text', 'uuid', 'uuid'],
  'permission helper exists with scoped signature'
);
select has_function(
  'private',
  'begin_idempotent_command',
  array['uuid', 'uuid', 'text', 'text', 'jsonb'],
  'idempotency command helper exists'
);
select has_function(
  'public',
  'get_my_access_context',
  array[]::text[],
  'access context RPC exists'
);

select results_eq(
  $$select count(*) from public.roles$$,
  $$values (3::bigint)$$,
  'exactly the three approved primary roles are seeded'
);

select cmp_ok(
  (select count(*) from public.permissions),
  '>=',
  80::bigint,
  'the permission catalog covers core and later operational modules'
);

select is(
  (
    select count(*)
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    where r.code = 'OWNER'
  ),
  (select count(*) from public.permissions),
  'owner maps to the complete permission catalog'
);

select is(
  (
    select count(*)
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.code = 'RECEPTIONIST'
      and p.code = 'security.manage_users_roles'
  ),
  0::bigint,
  'receptionist is not granted security administration'
);

select is(
  (
    select count(*)
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    join public.permissions p on p.id = rp.permission_id
    where r.code = 'MANAGER'
      and p.code = 'security.manage_users_roles'
  ),
  0::bigint,
  'manager is not granted owner security administration'
);

select ok(
  (
    select bool_and(c.relrowsecurity and c.relforcerowsecurity)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = any (array[
        'organizations',
        'locations',
        'profiles',
        'staff_employments',
        'roles',
        'permissions',
        'role_permissions',
        'user_role_assignments',
        'approval_policies',
        'approval_requests',
        'approval_decisions',
        'audit_events'
      ])
  ),
  'every exposed foundation table enables and forces RLS'
);

select ok(
  not has_table_privilege('anon', 'public.organizations', 'SELECT'),
  'anonymous callers have no organization table privilege'
);

select ok(
  has_table_privilege('authenticated', 'public.organizations', 'SELECT'),
  'authenticated callers receive read privilege subject to RLS'
);

select throws_ok(
  $$
    insert into public.organizations (legal_name, trading_name, default_currency_code)
    values ('Invalid Currency Ltd', 'Invalid Currency', 'CEDIS')
  $$,
  '23514',
  null,
  'invalid ISO currency code is rejected by the database'
);

select throws_ok(
  $$
    insert into public.permissions (code, module, description, risk_level)
    values ('INVALID CODE', 'test', 'Invalid code test', 'LOW')
  $$,
  '23514',
  null,
  'invalid permission code is rejected by the database'
);

select * from finish();
rollback;
