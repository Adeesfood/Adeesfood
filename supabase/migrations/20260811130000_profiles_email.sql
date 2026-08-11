-- Staff email was never stored anywhere the app could read: auth.users is
-- not queryable through the RLS-scoped client, so the Staff page had no way
-- to show it. Denormalize email onto profiles at signup time (same trigger
-- that already sets display_name) instead of calling the admin API on every
-- page render.

alter table public.profiles
  add column if not exists email text;

update public.profiles p
set email = u.email
from auth.users u
where u.id = p.id and p.email is null;

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

  insert into public.profiles (id, display_name, email, is_active)
  values (new.id, left(v_display_name, 120), new.email, false)
  on conflict (id) do update set email = excluded.email;

  return new;
end;
$$;

notify pgrst, 'reload schema';
