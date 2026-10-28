-- Regla del equipo: toda tabla del esquema public debe tener RLS activo.
-- Hoy no hay tablas y la prueba pasa; falla en cuanto alguien cree una tabla sin RLS.
begin;
create extension if not exists pgtap with schema extensions;

select plan(1);

select is_empty(
  $$
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity
  $$,
  'todas las tablas de public tienen RLS activo'
);

select * from finish();
rollback;