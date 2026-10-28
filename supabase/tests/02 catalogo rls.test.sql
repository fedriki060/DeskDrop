begin;
create extension if not exists pgtap with schema extensions;

-- ---------------------------------------------------------------------------
-- Datos de prueba (todo se revierte con el rollback final)
-- ---------------------------------------------------------------------------
-- Ids: a1-a3 solicitantes, b1 repartidor, c1-c3 admins de comercio, d1-d2 zonas,
--      e1-e3 comercios, f1-f7 productos, 11-13 puntos de entrega.
-- Correos con dominio institucional por si T-068 agrega el trigger de dominio en auth.users.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'com2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c3', 'com3@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co', 'Solicitante Tres', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',   'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1', 'comercio'),
  ('00000000-0000-0000-0000-0000000000c2', 'com2@eia.edu.co', 'Admin Comercio 2', 'comercio'),
  ('00000000-0000-0000-0000-0000000000c3', 'com3@eia.edu.co', 'Admin Comercio 3', 'comercio')
on conflict (id) do update set rol = excluded.rol;

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test',      true),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c2', 'Comercio Inactivo',   false),
  ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000c3', 'Papelería Test',      true);

insert into public.productos (id, comercio_id, nombre, precio, inventario_disponible, activo) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', 'Hamburguesa',        22000,  5, true),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e1', 'Producto inactivo',   8000, 30, false),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e1', 'Gaseosa agotada',     5000,  0, true),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000e2', 'De comercio inactivo',1000,  3, true),
  ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000e3', 'Cuaderno',            7500, 10, true),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000e1', 'Papas',               3000, 10, true),
  ('00000000-0000-0000-0000-0000000000f7', '00000000-0000-0000-0000-0000000000e1', 'Última unidad',       9000,  1, true);

insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa',   true),
  ('00000000-0000-0000-0000-0000000000d2', 'Zona Test Inactiva', false);

insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Punto activo',            6.1670, -75.5670, true),
  ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-0000000000d1', 'Punto inactivo',          6.1671, -75.5671, false),
  ('00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-0000000000d2', 'Punto en zona inactiva',  6.1672, -75.5672, true);

-- Cambia de usuario como lo hace la Data API: claims del JWT + rol de Postgres.
-- Se invoca siempre tras `reset role` (como superusuario).
create function pg_temp.como(p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $f$;

create function pg_temp.como_anon() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
end $f$;

select plan(21);

-- ---------------------------------------------------------------------------
-- Permisos y políticas declarados
-- ---------------------------------------------------------------------------
select table_privs_are('public', 'comercios', 'authenticated', array['SELECT'],
  'authenticated solo tiene SELECT en comercios');
select table_privs_are('public', 'productos', 'authenticated', array['SELECT'],
  'authenticated solo tiene SELECT en productos');
select table_privs_are('public', 'productos', 'anon', array[]::text[],
  'anon no tiene privilegios en productos');
select policies_are('public', 'productos', array['productos_lectura'],
  'productos solo tiene la política de lectura');

-- ---------------------------------------------------------------------------
-- anon: sin acceso al catálogo
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como_anon();
select throws_ok($$ select * from public.comercios $$, '42501', null,
  'anon no puede leer comercios');
select throws_ok($$ select * from public.productos $$, '42501', null,
  'anon no puede leer productos');
select throws_ok($$ select * from public.catalogo_productos $$, '42501', null,
  'anon no puede leer la vista del catálogo');

-- ---------------------------------------------------------------------------
-- Solicitante: ve solo comercios y productos activos
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a1');

select results_eq(
  $$ select id from public.comercios order by id $$,
  $$ values ('00000000-0000-0000-0000-0000000000e1'::uuid),
            ('00000000-0000-0000-0000-0000000000e3'::uuid) $$,
  'el cliente ve solo los comercios activos');

select results_eq(
  $$ select id from public.productos order by id $$,
  $$ values ('00000000-0000-0000-0000-0000000000f1'::uuid),
            ('00000000-0000-0000-0000-0000000000f3'::uuid),
            ('00000000-0000-0000-0000-0000000000f5'::uuid),
            ('00000000-0000-0000-0000-0000000000f6'::uuid),
            ('00000000-0000-0000-0000-0000000000f7'::uuid) $$,
  'el cliente no ve productos inactivos ni los de comercios inactivos');

select results_eq(
  $$ select id, disponible from public.catalogo_productos
     where comercio_id = '00000000-0000-0000-0000-0000000000e1' order by id $$,
  $$ values ('00000000-0000-0000-0000-0000000000f1'::uuid, true),
            ('00000000-0000-0000-0000-0000000000f3'::uuid, false),
            ('00000000-0000-0000-0000-0000000000f6'::uuid, true),
            ('00000000-0000-0000-0000-0000000000f7'::uuid, true) $$,
  'la vista del catálogo marca la disponibilidad según el inventario');

select is(
  (select precio from public.catalogo_productos where id = '00000000-0000-0000-0000-0000000000f1'),
  22000.00::numeric,
  'la vista expone el precio');

select is(
  (select inventario_disponible from public.catalogo_productos where id = '00000000-0000-0000-0000-0000000000f1'),
  5,
  'la vista expone el inventario disponible');

-- ---------------------------------------------------------------------------
-- Solicitante: sin escritura ni acceso a otras tablas
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into public.productos (comercio_id, nombre, precio)
     values ('00000000-0000-0000-0000-0000000000e1', 'Intruso', 1) $$,
  '42501', null, 'el cliente no puede insertar productos');
select throws_ok(
  $$ update public.productos set inventario_disponible = 999 $$,
  '42501', null, 'el cliente no puede modificar el inventario');
select throws_ok(
  $$ delete from public.productos $$,
  '42501', null, 'el cliente no puede borrar productos');
select throws_ok(
  $$ select * from public.perfiles $$,
  '42501', null, 'el cliente no puede leer perfiles (aún sin políticas)');

-- ---------------------------------------------------------------------------
-- Administrador de comercio: ve lo suyo aunque esté inactivo
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select is(
  (select count(*)::int from public.productos where comercio_id = '00000000-0000-0000-0000-0000000000e1'),
  5,
  'el administrador ve todos sus productos, incluidos los inactivos');
select is(
  (select count(*)::int from public.catalogo_productos where comercio_id = '00000000-0000-0000-0000-0000000000e1'),
  4,
  'la vista del catálogo solo lista productos activos, incluso al administrador');
select is(
  (select count(*)::int from public.productos where id = '00000000-0000-0000-0000-0000000000f4'),
  0,
  'el administrador no ve productos de otro comercio inactivo');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000c2');
select is(
  (select count(*)::int from public.comercios where id = '00000000-0000-0000-0000-0000000000e2'),
  1,
  'el administrador ve su propio comercio inactivo');
select is(
  (select count(*)::int from public.productos where comercio_id = '00000000-0000-0000-0000-0000000000e2'),
  1,
  'el administrador ve los productos de su comercio inactivo');

select * from finish();
rollback;
