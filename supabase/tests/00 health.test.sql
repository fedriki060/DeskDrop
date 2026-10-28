-- Prueba pgTAP de ejemplo (T-010): la función health() de T-004.
-- Se ejecuta con: npx supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(4);

select has_function('public', 'health', array[]::name[], 'existe public.health()');

select is(public.health(), 'ok', 'health() devuelve ok');

select function_privs_are('public', 'health', array[]::name[], 'anon',
  array['EXECUTE'], 'anon puede ejecutar health()');

select function_privs_are('public', 'health', array[]::name[], 'authenticated',
  array['EXECUTE'], 'authenticated puede ejecutar health()');

select * from finish();
rollback;