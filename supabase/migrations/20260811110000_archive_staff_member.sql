-- Owner-only staff offboarding. This never hard-deletes a person: their
-- orders, kitchen tickets, payments, and audit trail all reference their
-- profile and must stay intact. "Archive" ends their employment record,
-- revokes every active role grant, and deactivates their profile so they
-- can no longer sign in or be assigned new work — matching the same
-- preserve-history philosophy used everywhere else in this system.

create or replace function public.archive_staff_member(
  p_organization_id uuid,
  p_location_id uuid,
  p_profile_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_active_owner_count integer;
begin
  perform private.require_permission('security.manage_users_roles', p_organization_id, p_location_id, false);

  if exists (
    select 1 from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id and r.code = 'OWNER'
    where ura.organization_id = p_organization_id and ura.profile_id = p_profile_id
      and ura.revoked_at is null and (ura.valid_until is null or ura.valid_until > now())
  ) then
    select count(*)::integer into v_active_owner_count
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id and r.code = 'OWNER'
    where ura.organization_id = p_organization_id
      and ura.profile_id <> p_profile_id
      and ura.revoked_at is null and (ura.valid_until is null or ura.valid_until > now());
    if v_active_owner_count = 0 then
      raise exception using errcode = '55000', message = 'The last active owner cannot be archived';
    end if;
  end if;

  update public.staff_employments
  set is_active = false, end_date = current_date
  where organization_id = p_organization_id and profile_id = p_profile_id and is_active;

  if not found then
    raise exception using errcode = '22023', message = 'This person is not an active staff member';
  end if;

  update public.user_role_assignments
  set revoked_at = now(), revoked_by = auth.uid(),
      revocation_reason = coalesce(nullif(btrim(p_reason), ''), 'Staff archived')
  where organization_id = p_organization_id and profile_id = p_profile_id and revoked_at is null;

  update public.profiles set is_active = false where id = p_profile_id;
end;
$$;

revoke all on function public.archive_staff_member(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.archive_staff_member(uuid, uuid, uuid, text) to authenticated;

notify pgrst, 'reload schema';
