-- There was no way to add a brand-new staff member from the app at all —
-- the Staff module could only change the role of someone who already had a
-- profile and an active employment record. This RPC finishes onboarding a
-- staff member whose auth account has already been created server-side
-- (via the Supabase Admin API, using the service-role key) by a
-- security.manage_users_roles holder: it activates their profile, opens
-- their employment record, and grants their first role.

create or replace function public.onboard_staff_member(
  p_organization_id uuid,
  p_location_id uuid,
  p_profile_id uuid,
  p_display_name text,
  p_phone text,
  p_employee_number text,
  p_role_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role_id uuid;
  v_employment_id uuid;
  v_display_name text := btrim(coalesce(p_display_name, ''));
  v_employee_number text := btrim(coalesce(p_employee_number, ''));
begin
  perform private.require_permission('security.manage_users_roles', p_organization_id, p_location_id, false);

  if length(v_display_name) not between 2 and 120 then
    raise exception using errcode = '22023', message = 'Enter the staff member''s full name';
  end if;
  if length(v_employee_number) not between 1 and 40 then
    raise exception using errcode = '22023', message = 'Enter an employee number';
  end if;
  if not exists (select 1 from public.profiles where id = p_profile_id) then
    raise exception using errcode = '23503', message = 'Staff account was not found';
  end if;
  if exists (
    select 1 from public.staff_employments
    where organization_id = p_organization_id and profile_id = p_profile_id
  ) then
    raise exception using errcode = '23505', message = 'This person is already on the team';
  end if;

  select id into strict v_role_id from public.roles where code = p_role_code;

  update public.profiles
  set display_name = left(v_display_name, 120),
      phone = nullif(btrim(p_phone), ''),
      is_active = true
  where id = p_profile_id;

  insert into public.staff_employments (
    organization_id, profile_id, employee_number, start_date, is_active
  ) values (
    p_organization_id, p_profile_id, v_employee_number, current_date, true
  ) returning id into v_employment_id;

  insert into public.user_role_assignments (
    organization_id, location_id, profile_id, role_id, assigned_by
  ) values (
    p_organization_id, p_location_id, p_profile_id, v_role_id, auth.uid()
  );

  return v_employment_id;
exception
  when no_data_found then
    raise exception using errcode = '22023', message = 'Role was not found';
end;
$$;

revoke all on function public.onboard_staff_member(uuid, uuid, uuid, text, text, text, text) from public, anon;
grant execute on function public.onboard_staff_member(uuid, uuid, uuid, text, text, text, text) to authenticated;

notify pgrst, 'reload schema';
