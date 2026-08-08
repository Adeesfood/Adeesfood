-- Adee's Food restaurant management system
-- Phase 1A: tenancy, staff identity, authorization, audit, approvals,
-- idempotency, and durable event infrastructure.

begin;

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create type public.risk_level as enum ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
create type public.approval_status as enum (
  'PENDING',
  'APPROVED',
  'REJECTED',
  'CANCELLED',
  'EXPIRED',
  'CONSUMED'
);
create type public.approval_decision_type as enum ('APPROVE', 'REJECT');
create type private.idempotency_status as enum ('IN_PROGRESS', 'COMPLETED', 'FAILED');
create type private.outbox_status as enum ('PENDING', 'PROCESSING', 'PUBLISHED', 'FAILED');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null check (length(btrim(legal_name)) between 2 and 160),
  trading_name text not null check (length(btrim(trading_name)) between 2 and 120),
  default_currency_code text not null default 'GHS'
    check (default_currency_code ~ '^[A-Z]{3}$'),
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, default_currency_code)
);

create unique index organizations_trading_name_active_key
  on public.organizations (lower(trading_name))
  where is_active;

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,15}$'),
  name text not null check (length(btrim(name)) between 2 and 120),
  timezone text not null default 'Africa/Accra',
  country_code text not null default 'GH' check (country_code ~ '^[A-Z]{2}$'),
  address_line_1 text,
  address_line_2 text,
  city text,
  region text,
  phone text,
  email text check (email is null or email = lower(email)),
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, code)
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null check (length(btrim(display_name)) between 2 and 120),
  phone text,
  avatar_path text,
  is_active boolean not null default false,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.staff_employments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  employee_number text not null check (length(btrim(employee_number)) between 1 and 40),
  start_date date not null default current_date,
  end_date date,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date is null or end_date >= start_date),
  unique (organization_id, profile_id),
  unique (organization_id, employee_number)
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z][A-Z0-9_]{1,39}$'),
  name text not null check (length(btrim(name)) between 2 and 80),
  description text not null,
  risk_level public.risk_level not null,
  is_system boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  module text not null check (module ~ '^[a-z][a-z0-9_]{1,39}$'),
  description text not null,
  risk_level public.risk_level not null,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete restrict,
  permission_id uuid not null references public.permissions(id) on delete restrict,
  amount_limit_minor bigint check (amount_limit_minor is null or amount_limit_minor >= 0),
  percentage_limit_basis_points integer
    check (
      percentage_limit_basis_points is null
      or percentage_limit_basis_points between 0 and 10000
    ),
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table public.user_role_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  role_id uuid not null references public.roles(id) on delete restrict,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  revoked_at timestamptz,
  assigned_by uuid references public.profiles(id) on delete restrict,
  revoked_by uuid references public.profiles(id) on delete restrict,
  revocation_reason text,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (valid_until is null or valid_until > valid_from),
  check (revoked_at is null or revoked_at >= valid_from),
  check (
    (revoked_at is null and revoked_by is null and revocation_reason is null)
    or
    (revoked_at is not null and revoked_by is not null and length(btrim(revocation_reason)) >= 3)
  ),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict,
  foreign key (organization_id, profile_id)
    references public.staff_employments(organization_id, profile_id) on delete restrict
);

create index user_role_assignments_authorization_idx
  on public.user_role_assignments (profile_id, organization_id, location_id, valid_from, valid_until)
  where revoked_at is null;

create index role_permissions_permission_idx
  on public.role_permissions (permission_id, role_id);

create table public.approval_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid,
  action_code text not null check (action_code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  required_permission_code text not null references public.permissions(code) on delete restrict,
  currency_code text check (currency_code is null or currency_code ~ '^[A-Z]{3}$'),
  minimum_amount_minor bigint check (minimum_amount_minor is null or minimum_amount_minor >= 0),
  requires_second_approver boolean not null default false,
  requires_aal2 boolean not null default false,
  is_active boolean not null default true,
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_until is null or effective_until > effective_from),
  check (
    (minimum_amount_minor is null and currency_code is null)
    or
    (minimum_amount_minor is not null and currency_code is not null)
  ),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict
);

create unique index approval_policies_active_scope_key
  on public.approval_policies (
    organization_id,
    coalesce(location_id, '00000000-0000-0000-0000-000000000000'::uuid),
    action_code,
    coalesce(minimum_amount_minor, -1)
  )
  where is_active and effective_until is null;

create table public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid,
  policy_id uuid references public.approval_policies(id) on delete restrict,
  action_code text not null,
  entity_type text not null check (entity_type ~ '^[a-z][a-z0-9_]{1,79}$'),
  entity_id text not null check (length(btrim(entity_id)) between 1 and 160),
  requested_by uuid not null references public.profiles(id) on delete restrict,
  request_payload jsonb not null default '{}'::jsonb,
  request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
  reason text not null check (length(btrim(reason)) between 3 and 1000),
  status public.approval_status not null default 'PENDING',
  expires_at timestamptz not null,
  resolved_at timestamptz,
  consumed_at timestamptz,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at > created_at),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict
);

create index approval_requests_pending_idx
  on public.approval_requests (organization_id, location_id, action_code, expires_at)
  where status = 'PENDING';

create table public.approval_decisions (
  id uuid primary key default gen_random_uuid(),
  approval_request_id uuid not null references public.approval_requests(id) on delete restrict,
  decided_by uuid not null references public.profiles(id) on delete restrict,
  decision public.approval_decision_type not null,
  reason text not null check (length(btrim(reason)) between 3 and 1000),
  decided_at timestamptz not null default now(),
  unique (approval_request_id, decided_by)
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  organization_id uuid references public.organizations(id) on delete restrict,
  location_id uuid,
  actor_user_id uuid references public.profiles(id) on delete restrict,
  actor_role_codes text[] not null default '{}',
  action text not null check (action ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  entity_type text not null check (entity_type ~ '^[a-z][a-z0-9_]{1,79}$'),
  entity_id text,
  before_data jsonb,
  after_data jsonb,
  reason text,
  request_id text,
  correlation_id uuid,
  occurred_at timestamptz not null default clock_timestamp(),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict
);

create index audit_events_scope_time_idx
  on public.audit_events (organization_id, location_id, occurred_at desc);

create index audit_events_entity_idx
  on public.audit_events (entity_type, entity_id, occurred_at desc);

create table private.idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid,
  actor_user_id uuid not null references public.profiles(id) on delete restrict,
  command_name text not null check (command_name ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  idempotency_key text not null check (length(idempotency_key) between 8 and 200),
  request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
  status private.idempotency_status not null default 'IN_PROGRESS',
  response_body jsonb,
  result_entity_type text,
  result_entity_id text,
  failure_code text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '7 days'),
  unique (actor_user_id, command_name, idempotency_key),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict
);

create index idempotency_keys_expiry_idx on private.idempotency_keys (expires_at);

create table private.outbox_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid,
  aggregate_type text not null check (aggregate_type ~ '^[a-z][a-z0-9_]{1,79}$'),
  aggregate_id text not null,
  aggregate_version integer not null check (aggregate_version > 0),
  event_type text not null check (event_type ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  payload jsonb not null default '{}'::jsonb,
  status private.outbox_status not null default 'PENDING',
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique (aggregate_type, aggregate_id, aggregate_version, event_type),
  foreign key (organization_id, location_id)
    references public.locations(organization_id, id) on delete restrict
);

create index outbox_events_pending_idx
  on private.outbox_events (available_at, id)
  where status in ('PENDING', 'FAILED');

create or replace function private.touch_versioned_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  new.version := old.version + 1;
  return new;
end;
$$;

create trigger organizations_touch_version
before update on public.organizations
for each row execute function private.touch_versioned_row();

create trigger locations_touch_version
before update on public.locations
for each row execute function private.touch_versioned_row();

create trigger profiles_touch_version
before update on public.profiles
for each row execute function private.touch_versioned_row();

create trigger staff_employments_touch_version
before update on public.staff_employments
for each row execute function private.touch_versioned_row();

create trigger roles_touch_version
before update on public.roles
for each row execute function private.touch_versioned_row();

create trigger permissions_touch_version
before update on public.permissions
for each row execute function private.touch_versioned_row();

create trigger user_role_assignments_touch_version
before update on public.user_role_assignments
for each row execute function private.touch_versioned_row();

create trigger approval_policies_touch_version
before update on public.approval_policies
for each row execute function private.touch_versioned_row();

create trigger approval_requests_touch_version
before update on public.approval_requests
for each row execute function private.touch_versioned_row();

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_display_name text;
begin
  v_display_name := nullif(btrim(new.raw_user_meta_data ->> 'display_name'), '');
  v_display_name := coalesce(v_display_name, nullif(split_part(new.email, '@', 1), ''), 'New Staff Member');

  insert into public.profiles (id, display_name, is_active)
  values (new.id, left(v_display_name, 120), false)
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_auth_user();

create or replace function private.has_any_active_assignment(
  p_organization_id uuid default null,
  p_location_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.profiles p on p.id = ura.profile_id and p.is_active
    join public.staff_employments se
      on se.organization_id = ura.organization_id
     and se.profile_id = ura.profile_id
     and se.is_active
     and se.start_date <= current_date
     and (se.end_date is null or se.end_date >= current_date)
    join public.organizations o on o.id = ura.organization_id and o.is_active
    left join public.locations l on l.id = p_location_id and l.organization_id = ura.organization_id
    where ura.profile_id = (select auth.uid())
      and ura.revoked_at is null
      and ura.valid_from <= now()
      and (ura.valid_until is null or ura.valid_until > now())
      and (p_organization_id is null or ura.organization_id = p_organization_id)
      and (p_location_id is null or ura.location_id is null or ura.location_id = p_location_id)
      and (p_location_id is null or (l.id is not null and l.is_active))
  );
$$;

create or replace function private.has_permission(
  p_permission_code text,
  p_organization_id uuid,
  p_location_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.profiles pr on pr.id = ura.profile_id and pr.is_active
    join public.staff_employments se
      on se.organization_id = ura.organization_id
     and se.profile_id = ura.profile_id
     and se.is_active
     and se.start_date <= current_date
     and (se.end_date is null or se.end_date >= current_date)
    join public.organizations o on o.id = ura.organization_id and o.is_active
    join public.roles r on r.id = ura.role_id
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions pe on pe.id = rp.permission_id and pe.is_active
    left join public.locations l on l.id = p_location_id and l.organization_id = ura.organization_id
    where ura.profile_id = (select auth.uid())
      and ura.organization_id = p_organization_id
      and (
        (p_location_id is null and ura.location_id is null)
        or
        (p_location_id is not null and (ura.location_id is null or ura.location_id = p_location_id))
      )
      and (p_location_id is null or (l.id is not null and l.is_active))
      and ura.revoked_at is null
      and ura.valid_from <= now()
      and (ura.valid_until is null or ura.valid_until > now())
      and pe.code = p_permission_code
  );
$$;

create or replace function private.current_role_codes(
  p_organization_id uuid,
  p_location_id uuid default null
)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct r.code order by r.code), '{}'::text[])
  from public.user_role_assignments ura
  join public.profiles p on p.id = ura.profile_id and p.is_active
  join public.staff_employments se
    on se.organization_id = ura.organization_id
   and se.profile_id = ura.profile_id
   and se.is_active
   and se.start_date <= current_date
   and (se.end_date is null or se.end_date >= current_date)
  join public.roles r on r.id = ura.role_id
  where ura.profile_id = (select auth.uid())
    and ura.organization_id = p_organization_id
    and (
      (p_location_id is null and ura.location_id is null)
      or
      (p_location_id is not null and (ura.location_id is null or ura.location_id = p_location_id))
    )
    and ura.revoked_at is null
    and ura.valid_from <= now()
    and (ura.valid_until is null or ura.valid_until > now());
$$;

create or replace function private.has_aal2()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((select auth.jwt() ->> 'aal') = 'aal2', false);
$$;

create or replace function private.can_view_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_profile_id = (select auth.uid())
    or exists (
      select 1
      from public.user_role_assignments target_assignment
      where target_assignment.profile_id = p_profile_id
        and target_assignment.revoked_at is null
        and target_assignment.valid_from <= now()
        and (
          target_assignment.valid_until is null
          or target_assignment.valid_until > now()
        )
        and private.has_permission(
          'staff.view',
          target_assignment.organization_id,
          target_assignment.location_id
        )
    );
$$;

create or replace function private.require_permission(
  p_permission_code text,
  p_organization_id uuid,
  p_location_id uuid default null,
  p_requires_aal2 boolean default false
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if not private.has_permission(p_permission_code, p_organization_id, p_location_id) then
    raise exception using errcode = '42501', message = 'Permission denied';
  end if;

  if p_requires_aal2 and not private.has_aal2() then
    raise exception using errcode = '42501', message = 'Multi-factor authentication required';
  end if;
end;
$$;

create or replace function private.write_audit_event(
  p_organization_id uuid,
  p_location_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id text,
  p_before_data jsonb default null,
  p_after_data jsonb default null,
  p_reason text default null,
  p_correlation_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
  v_headers jsonb;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then
    v_headers := '{}'::jsonb;
  end;

  insert into public.audit_events (
    organization_id,
    location_id,
    actor_user_id,
    actor_role_codes,
    action,
    entity_type,
    entity_id,
    before_data,
    after_data,
    reason,
    request_id,
    correlation_id
  )
  values (
    p_organization_id,
    p_location_id,
    (select auth.uid()),
    case
      when p_organization_id is null then '{}'::text[]
      else private.current_role_codes(p_organization_id, p_location_id)
    end,
    p_action,
    p_entity_type,
    p_entity_id,
    p_before_data,
    p_after_data,
    p_reason,
    coalesce(v_headers ->> 'x-request-id', current_setting('app.request_id', true)),
    p_correlation_id
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before jsonb;
  v_after jsonb;
  v_row jsonb;
  v_organization_id uuid;
  v_location_id uuid;
  v_entity_id text;
  v_reason text;
begin
  v_before := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end;
  v_after := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end;
  v_row := coalesce(v_after, v_before, '{}'::jsonb);

  if nullif(v_row ->> 'organization_id', '') is not null then
    v_organization_id := (v_row ->> 'organization_id')::uuid;
  elsif tg_table_name = 'organizations' then
    v_organization_id := (v_row ->> 'id')::uuid;
  end if;

  if nullif(v_row ->> 'location_id', '') is not null then
    v_location_id := (v_row ->> 'location_id')::uuid;
  elsif tg_table_name = 'locations' then
    v_location_id := (v_row ->> 'id')::uuid;
  end if;

  v_entity_id := v_row ->> 'id';
  v_reason := nullif(current_setting('app.audit_reason', true), '');

  perform private.write_audit_event(
    v_organization_id,
    v_location_id,
    tg_table_name || '.' || lower(tg_op),
    tg_table_name,
    v_entity_id,
    v_before,
    v_after,
    v_reason,
    null
  );

  return coalesce(new, old);
end;
$$;

create or replace function private.block_immutable_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = format('%I is append-only; create a linked correction instead', tg_table_name);
end;
$$;

create trigger audit_events_are_append_only
before update or delete on public.audit_events
for each row execute function private.block_immutable_mutation();

create or replace function private.enforce_approval_separation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_requester uuid;
begin
  select requested_by
  into v_requester
  from public.approval_requests
  where id = new.approval_request_id;

  if v_requester = new.decided_by then
    raise exception using
      errcode = '23514',
      message = 'A requester cannot approve or reject their own approval request';
  end if;

  return new;
end;
$$;

create trigger approval_decisions_require_separate_actor
before insert on public.approval_decisions
for each row execute function private.enforce_approval_separation();

create or replace function private.begin_idempotent_command(
  p_organization_id uuid,
  p_location_id uuid,
  p_command_name text,
  p_idempotency_key text,
  p_request_payload jsonb
)
returns table (
  idempotency_id uuid,
  is_replay boolean,
  replay_response jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_request_hash text;
  v_existing private.idempotency_keys%rowtype;
  v_new_id uuid;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if not private.has_any_active_assignment(p_organization_id, p_location_id) then
    raise exception using errcode = '42501', message = 'Active staff assignment required';
  end if;

  if length(p_idempotency_key) not between 8 and 200 then
    raise exception using errcode = '22023', message = 'Invalid idempotency key';
  end if;

  v_request_hash := encode(
    extensions.digest(convert_to(coalesce(p_request_payload, '{}'::jsonb)::text, 'UTF8'), 'sha256'),
    'hex'
  );

  insert into private.idempotency_keys (
    organization_id,
    location_id,
    actor_user_id,
    command_name,
    idempotency_key,
    request_hash
  )
  values (
    p_organization_id,
    p_location_id,
    v_actor,
    p_command_name,
    p_idempotency_key,
    v_request_hash
  )
  on conflict (actor_user_id, command_name, idempotency_key) do nothing
  returning id into v_new_id;

  if v_new_id is not null then
    return query select v_new_id, false, null::jsonb;
    return;
  end if;

  select *
  into v_existing
  from private.idempotency_keys ik
  where ik.actor_user_id = v_actor
    and ik.command_name = p_command_name
    and ik.idempotency_key = p_idempotency_key
  for update;

  if v_existing.request_hash <> v_request_hash then
    raise exception using
      errcode = '22023',
      message = 'Idempotency key was already used with a different request';
  end if;

  if v_existing.status = 'COMPLETED' then
    return query select v_existing.id, true, v_existing.response_body;
    return;
  end if;

  raise exception using
    errcode = '55P03',
    message = 'An identical command is already in progress or previously failed';
end;
$$;

create or replace function private.complete_idempotent_command(
  p_idempotency_id uuid,
  p_response_body jsonb,
  p_result_entity_type text default null,
  p_result_entity_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.idempotency_keys
  set status = 'COMPLETED',
      response_body = p_response_body,
      result_entity_type = p_result_entity_type,
      result_entity_id = p_result_entity_id,
      completed_at = clock_timestamp()
  where id = p_idempotency_id
    and actor_user_id = (select auth.uid())
    and status = 'IN_PROGRESS';

  if not found then
    raise exception using errcode = '55000', message = 'Idempotent command cannot be completed';
  end if;
end;
$$;

create or replace function private.enqueue_outbox_event(
  p_organization_id uuid,
  p_location_id uuid,
  p_aggregate_type text,
  p_aggregate_id text,
  p_aggregate_version integer,
  p_event_type text,
  p_payload jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  insert into private.outbox_events (
    organization_id,
    location_id,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    payload
  )
  values (
    p_organization_id,
    p_location_id,
    p_aggregate_type,
    p_aggregate_id,
    p_aggregate_version,
    p_event_type,
    coalesce(p_payload, '{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.get_my_access_context()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with active_assignments as (
    select
      ura.id,
      ura.organization_id,
      o.trading_name as organization_name,
      ura.location_id,
      l.name as location_name,
      r.code as role_code,
      r.name as role_name
    from public.user_role_assignments ura
    join public.profiles p on p.id = ura.profile_id and p.is_active
    join public.staff_employments se
      on se.organization_id = ura.organization_id
     and se.profile_id = ura.profile_id
     and se.is_active
     and se.start_date <= current_date
     and (se.end_date is null or se.end_date >= current_date)
    join public.organizations o on o.id = ura.organization_id and o.is_active
    join public.roles r on r.id = ura.role_id
    left join public.locations l
      on l.id = ura.location_id
     and l.organization_id = ura.organization_id
     and l.is_active
    where ura.profile_id = (select auth.uid())
      and ura.revoked_at is null
      and ura.valid_from <= now()
      and (ura.valid_until is null or ura.valid_until > now())
  ), permission_codes as (
    select distinct pe.code
    from active_assignments aa
    join public.roles r on r.code = aa.role_code
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions pe on pe.id = rp.permission_id and pe.is_active
  )
  select jsonb_build_object(
    'user_id', (select auth.uid()),
    'assignments', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'assignment_id', aa.id,
            'organization_id', aa.organization_id,
            'organization_name', aa.organization_name,
            'location_id', aa.location_id,
            'location_name', aa.location_name,
            'role_code', aa.role_code,
            'role_name', aa.role_name
          ) order by aa.organization_name, aa.location_name, aa.role_code
        )
        from active_assignments aa
      ),
      '[]'::jsonb
    ),
    'permissions', coalesce(
      (select jsonb_agg(pc.code order by pc.code) from permission_codes pc),
      '[]'::jsonb
    )
  );
$$;

create trigger organizations_audit_changes
after insert or update or delete on public.organizations
for each row execute function private.audit_row_change();

create trigger locations_audit_changes
after insert or update or delete on public.locations
for each row execute function private.audit_row_change();

create trigger profiles_audit_changes
after update or delete on public.profiles
for each row execute function private.audit_row_change();

create trigger staff_employments_audit_changes
after insert or update or delete on public.staff_employments
for each row execute function private.audit_row_change();

create trigger user_role_assignments_audit_changes
after insert or update or delete on public.user_role_assignments
for each row execute function private.audit_row_change();

create trigger approval_policies_audit_changes
after insert or update or delete on public.approval_policies
for each row execute function private.audit_row_change();

alter table public.organizations enable row level security;
alter table public.locations enable row level security;
alter table public.profiles enable row level security;
alter table public.staff_employments enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_role_assignments enable row level security;
alter table public.approval_policies enable row level security;
alter table public.approval_requests enable row level security;
alter table public.approval_decisions enable row level security;
alter table public.audit_events enable row level security;

alter table public.organizations force row level security;
alter table public.locations force row level security;
alter table public.profiles force row level security;
alter table public.staff_employments force row level security;
alter table public.roles force row level security;
alter table public.permissions force row level security;
alter table public.role_permissions force row level security;
alter table public.user_role_assignments force row level security;
alter table public.approval_policies force row level security;
alter table public.approval_requests force row level security;
alter table public.approval_decisions force row level security;
alter table public.audit_events force row level security;

create policy organizations_select_assigned
on public.organizations for select to authenticated
using (private.has_any_active_assignment(id, null));

create policy locations_select_assigned
on public.locations for select to authenticated
using (private.has_any_active_assignment(organization_id, id));

create policy profiles_select_authorized
on public.profiles for select to authenticated
using (private.can_view_profile(id));

create policy staff_employments_select_authorized
on public.staff_employments for select to authenticated
using (profile_id = (select auth.uid()) or private.can_view_profile(profile_id));

create policy roles_select_active_staff
on public.roles for select to authenticated
using (private.has_any_active_assignment(null, null));

create policy permissions_select_active_staff
on public.permissions for select to authenticated
using (private.has_any_active_assignment(null, null));

create policy role_permissions_select_active_staff
on public.role_permissions for select to authenticated
using (private.has_any_active_assignment(null, null));

create policy user_role_assignments_select_authorized
on public.user_role_assignments for select to authenticated
using (
  (
    profile_id = (select auth.uid())
    and private.has_any_active_assignment(organization_id, location_id)
  )
  or private.can_view_profile(profile_id)
);

create policy approval_policies_select_authorized
on public.approval_policies for select to authenticated
using (
  private.has_permission('approvals.view', organization_id, location_id)
  or private.has_permission('settings.manage_financial_security', organization_id, null)
);

create policy approval_requests_select_authorized
on public.approval_requests for select to authenticated
using (
  requested_by = (select auth.uid())
  or private.has_permission('approvals.view', organization_id, location_id)
);

create policy approval_decisions_select_authorized
on public.approval_decisions for select to authenticated
using (
  exists (
    select 1
    from public.approval_requests ar
    where ar.id = approval_request_id
      and (
        ar.requested_by = (select auth.uid())
        or private.has_permission('approvals.view', ar.organization_id, ar.location_id)
      )
  )
);

create policy audit_events_select_location
on public.audit_events for select to authenticated
using (
  private.has_permission('audit.view_location', organization_id, location_id)
  or private.has_permission('audit.view_all', organization_id, null)
);

revoke all on all tables in schema public from anon, authenticated;
grant usage on schema public to authenticated;

grant select on table
  public.organizations,
  public.locations,
  public.profiles,
  public.staff_employments,
  public.roles,
  public.permissions,
  public.role_permissions,
  public.user_role_assignments,
  public.approval_policies,
  public.approval_requests,
  public.approval_decisions,
  public.audit_events
to authenticated;

revoke all on all functions in schema private from public, anon, authenticated;
grant usage on schema private to authenticated;
grant execute on function private.has_any_active_assignment(uuid, uuid) to authenticated;
grant execute on function private.has_permission(text, uuid, uuid) to authenticated;
grant execute on function private.has_aal2() to authenticated;
grant execute on function private.can_view_profile(uuid) to authenticated;

revoke all on function public.get_my_access_context() from public, anon;
grant execute on function public.get_my_access_context() to authenticated;

comment on schema private is
  'Non-exposed command internals. Do not add private to Supabase API schemas.';
comment on table public.audit_events is
  'Append-only security and business audit evidence. Corrections create new events.';
comment on table private.idempotency_keys is
  'Retry protection for transactional commands; never exposed through the Data API.';
comment on table private.outbox_events is
  'Durable domain events written in the same transaction as business state.';
comment on function public.get_my_access_context() is
  'Returns only the authenticated staff member''s active roles, scopes, and permissions.';

commit;
