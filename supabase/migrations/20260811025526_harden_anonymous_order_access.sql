-- Public ordering is RPC-only. Anonymous visitors must never query order or
-- customer tables directly, even if a future RLS policy is misconfigured.

begin;

revoke all on table public.orders from anon;
revoke all on table public.order_items from anon;
revoke all on table public.order_item_modifiers from anon;
revoke all on table public.customers from anon;

commit;
