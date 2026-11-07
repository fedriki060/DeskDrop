-- Pruebas de la publicación de pedidos en Supabase Realtime (T-046).
-- Que cada usuario reciba solo sus eventos se prueba de punta a punta en
-- tests/integration/realtime.test.ts; aquí se revisa la configuración en la base.
begin;
create extension if not exists pgtap with schema extensions;

select plan(7);

select ok(
  exists (select 1 from pg_publication where pubname = 'supabase_realtime'),
  'existe la publicación supabase_realtime');
select ok(
  exists (select 1 from pg_publication_tables
          where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pedidos'),
  'pedidos está publicada en Realtime');
select ok(
  not exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'public'
                and tablename in ('items_pedido', 'pagos', 'perfiles', 'configuracion')),
  'items_pedido, pagos, perfiles y configuracion no están publicadas');

-- Realtime filtra con la RLS de pedidos: tiene que estar activa y con la política de lectura
select ok(
  (select relrowsecurity from pg_class where oid = 'public.pedidos'::regclass),
  'pedidos tiene RLS activa');
select policies_are('public', 'pedidos', array['ver_pedidos_por_rol'],
  'pedidos solo tiene la política de lectura ver_pedidos_por_rol');
select table_privs_are('public', 'pedidos', 'anon', array[]::text[],
  'anon no tiene privilegios en pedidos (no recibe eventos)');
select table_privs_are('public', 'pedidos', 'authenticated', array['SELECT'],
  'authenticated solo puede leer pedidos (los eventos pasan por la RLS)');

select * from finish();
rollback;
