-- Event-trigger functions are invoked by PostgreSQL, never by Data API clients.
-- Remove the default function EXECUTE grant to keep this security-definer helper
-- outside the public API surface.
revoke execute on function public.rls_auto_enable() from public;
revoke execute on function public.rls_auto_enable() from anon;
revoke execute on function public.rls_auto_enable() from authenticated;
