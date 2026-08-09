-- Inventory projections may only be changed from trusted security-definer
-- commands owned by the database owner. This remains effective even if a
-- custom transaction setting was left behind by an earlier command.
create or replace function private.protect_inventory_balance()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.current_stock <> old.current_stock and current_user <> 'postgres' then
    raise exception using
      errcode = '55000',
      message = 'Inventory balances may change only through stock movements';
  end if;
  return new;
end;
$$;
