begin;

revoke all privileges on all tables in schema public from anon;
revoke all privileges on all sequences in schema public from anon;

revoke all on function public.create_online_order(uuid, text, text, text, jsonb, uuid, text, text, text)
  from public, anon, authenticated;

revoke all on function private.protect_inventory_balance()
  from public, anon, authenticated;

grant usage on schema public to anon;
grant execute on function public.get_public_menu(uuid) to anon;
grant execute on function public.create_online_order_v2(uuid, text, text, text, jsonb, uuid, timestamptz, text, text, text)
  to anon;
grant execute on function public.get_online_order_status(uuid, text)
  to anon;

notify pgrst, 'reload schema';

commit;
