-- profiles and staff_employments only ever had SELECT policies for staff —
-- there was no way to fix a mistyped name or employee number after
-- onboarding. This RPC lets a security.manage_users_roles holder edit
-- those fields the same way onboard_staff_member and archive_staff_member
-- already manage the rest of the employment lifecycle.

create or replace function public.update_staff_member(
  p_organization_id uuid,
  p_location_id uuid,
  p_profile_id uuid,
  p_display_name text,
  p_phone text,
  p_employee_number text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
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

  update public.profiles
  set display_name = left(v_display_name, 120), phone = nullif(btrim(p_phone), '')
  where id = p_profile_id;

  if not found then
    raise exception using errcode = '23503', message = 'Staff account was not found';
  end if;

  update public.staff_employments
  set employee_number = v_employee_number
  where organization_id = p_organization_id and profile_id = p_profile_id;

  if not found then
    raise exception using errcode = '22023', message = 'This person has no employment record at this organization';
  end if;
end;
$$;

revoke all on function public.update_staff_member(uuid, uuid, uuid, text, text, text) from public, anon;
grant execute on function public.update_staff_member(uuid, uuid, uuid, text, text, text) to authenticated;

notify pgrst, 'reload schema';
