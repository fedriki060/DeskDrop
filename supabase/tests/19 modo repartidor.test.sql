-- Pruebas de HU-19: vista de repartidor para cualquier usuario con declaración de +18 (T-083).
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1, a2 solicitantes, b1 repartidor heredado, c1 admin de comercio, ad administrador,
--      d1 zona, e1 comercio, 11 punto del campus, aa01 pedido Creado sin repartidor.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000ad', 'adm@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',  'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio',  'comercio'),
  ('00000000-0000-0000-0000-0000000000ad', 'adm@eia.edu.co',  'Administrador',   'admin')
on conflict (id) do update set rol = excluded.rol;

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);
insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);
insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);
insert into public.pedidos (id, solicitante_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a2',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado', 1000, 2000, 3000);

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

select plan(19);

-- Permisos y estructura
select has_table('public', 'aceptaciones_repartidor', 'existe aceptaciones_repartidor');
select function_privs_are('public', 'activar_modo_repartidor', array['boolean', 'text'], 'anon', array[]::text[],
  'anon no puede ejecutar activar_modo_repartidor');
select function_privs_are('public', 'activar_modo_repartidor', array['boolean', 'text'], 'authenticated', array['EXECUTE'],
  'authenticated puede ejecutar activar_modo_repartidor');
select table_privs_are('public', 'aceptaciones_repartidor', 'authenticated', array['SELECT'],
  'authenticated solo puede leer aceptaciones_repartidor');

-- Sin sesión
select pg_temp.como_anon();
select throws_ok($$ select public.activar_modo_repartidor(true, '1.0') $$, '42501', null,
  'anon no puede activar la vista de repartidor');
reset role;

-- Solicitante sin aceptar: no es repartidor y no ve pedidos disponibles
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is(public.es_repartidor_habilitado(), false, 'un solicitante que no ha aceptado no está habilitado');
select is((select count(*)::int from public.pedidos), 0, 'sin aceptar no ve pedidos disponibles de otros');

-- Validaciones
select throws_ok($$ select public.activar_modo_repartidor(false, '1.0') $$, '22023', null,
  'sin marcar el +18 se rechaza (false)');
select throws_ok($$ select public.activar_modo_repartidor(null, '1.0') $$, '22023', null,
  'sin marcar el +18 se rechaza (null)');
select throws_ok($$ select public.activar_modo_repartidor(true, '  ') $$, '22023', null,
  'la versión del texto es obligatoria');

-- Aceptación válida e idempotente
select is((public.activar_modo_repartidor(true, '1.0')->>'habilitado')::boolean, true,
  'aceptar con +18 habilita la vista de repartidor');
select is(public.es_repartidor_habilitado(), true, 'queda habilitado');
select is((select count(*)::int from public.aceptaciones_repartidor), 1, 'solo ve su propia aceptación');
select is((select count(*)::int from public.pedidos where estado = 'Creado'), 1,
  'habilitado ve el pedido disponible');
select lives_ok($$ select public.activar_modo_repartidor(true, '1.0') $$, 'repetir la aceptación no falla');
select is((select count(*)::int from public.aceptaciones_repartidor), 1, 'repetir no duplica la fila');
select throws_ok(
  $$ insert into public.aceptaciones_repartidor (usuario_id, version) values ('00000000-0000-0000-0000-0000000000a1', '9.9') $$,
  '42501', null, 'no se puede escribir directo en la tabla');
reset role;

-- Roles que no pueden ser repartidor
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$ select public.activar_modo_repartidor(true, '1.0') $$, '42501', null,
  'un comercio no puede activar la vista de repartidor');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select throws_ok($$ select public.activar_modo_repartidor(true, '1.0') $$, '42501', null,
  'un admin no puede activar la vista de repartidor');
reset role;

select * from finish();
rollback;
