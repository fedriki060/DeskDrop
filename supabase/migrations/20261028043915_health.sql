create or replace function public.health()
returns text
language sql
stable
set search_path = ''
as $$ select 'ok'::text $$;

revoke execute on function public.health() from public;
grant execute on function public.health() to anon, authenticated;