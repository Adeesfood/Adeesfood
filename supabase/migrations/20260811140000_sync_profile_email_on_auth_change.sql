-- profiles.email is a denormalized copy of auth.users.email, set at signup
-- by handle_new_auth_user(). If it's ever changed afterward — through the
-- staff edit form, the Supabase dashboard, or anywhere else — this keeps
-- the copy in sync instead of letting it silently go stale.

create or replace function private.handle_auth_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is distinct from old.email then
    update public.profiles set email = new.email where id = new.id;
  end if;
  return new;
end;
$$;

create trigger on_auth_user_email_change
after update of email on auth.users
for each row execute function private.handle_auth_user_email_change();

notify pgrst, 'reload schema';
