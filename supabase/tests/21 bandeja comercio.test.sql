-- Pruebas de HU-05: número de pedido y datos_partes_pedido (T-030, T-097).
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1, a2 solicitantes, b1 y b2 domiciliarios, c1 admin de comercio, c2 admin de otro comercio.
-- Pedidos: ca01 (a1, b1, En Camino), ca02 (a2, Creado, sin domiciliario).
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b2', 'rep2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'com2@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Ana Gómez',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Beto Ruiz',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Carlos Pérez', 'repartidor'),
  ('00000000-0000-0000-0000-0000000000b2', 'rep2@eia.edu.co', 'Dora Mejía',  'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1', 'comercio'),
  ('00000000-0000-0000-0000-0000000000c2', 'com2@eia.edu.co', 'Admin Comercio 2', 'comercio')
on conflict (id) do update set nombre_completo = excluded.nombre_completo, rol = excluded.rol;

insert into public.aceptaciones_repartidor (usuario_id, version) values
  ('00000000-0000-0000-0000-0000000000b1', 'test'),
  ('00000000-0000-0000-0000-0000000000b2', 'test');

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c2', 'Papelería Test', true);
insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);
insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ca02', '00000000-0000-0000-0000-0000000000a2', null,
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

select plan(15);

select has_function('public', 'datos_partes_pedido', array['uuid[]'], 'existe datos_partes_pedido');
select ok(has_function_privilege('authenticated', 'public.datos_partes_pedido(uuid[])', 'execute'),
  'authenticated puede ejecutar datos_partes_pedido');
select ok(not has_function_privilege('anon', 'public.datos_partes_pedido(uuid[])', 'execute'),
  'anon no puede ejecutar datos_partes_pedido');

-- Número de pedido
select is((select count(distinct numero)::int from public.pedidos), 2, 'cada pedido tiene su propio número');
select ok((select min(numero) >= 1001 from public.pedidos), 'los números arrancan en 1001');

-- Solicitante: su pedido, con su nombre y el del domiciliario
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-00000000ca02']::uuid[])),
  1, 'el solicitante solo obtiene datos de su propio pedido');
select is((select repartidor from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01']::uuid[])),
  'Carlos', 'el solicitante ve el primer nombre del domiciliario');
reset role;

-- Dueño del comercio: ve a ambas partes de los pedidos de su comercio
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select is((select count(*)::int from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-00000000ca02']::uuid[])),
  2, 'el dueño del comercio obtiene datos de los pedidos de su comercio');
select is((select solicitante from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca02']::uuid[])),
  'Beto', 'el comercio ve el primer nombre del solicitante');
select is((select repartidor from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca02']::uuid[])),
  null, 'sin domiciliario asignado el nombre sale vacío');
reset role;

-- Otro comercio no ve nada
select pg_temp.como('00000000-0000-0000-0000-0000000000c2');
select is((select count(*)::int from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-00000000ca02']::uuid[])),
  0, 'el administrador de otro comercio no obtiene datos');
reset role;

-- Domiciliarios
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select is((select solicitante from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01']::uuid[])),
  'Ana', 'el domiciliario asignado ve el nombre del solicitante');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select is((select count(*)::int from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-00000000ca02']::uuid[])),
  0, 'un domiciliario no ve nombres de pedidos que no ha aceptado');
reset role;

-- Errores
select pg_temp.como_anon();
select throws_ok($$ select * from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01']::uuid[]) $$,
  '42501', null, 'sin sesión no se pueden consultar nombres');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select throws_ok(
  $$ select * from public.datos_partes_pedido((select array_agg(gen_random_uuid()) from generate_series(1, 101))) $$,
  '22023', 'DEMASIADOS_PEDIDOS: Máximo 100 pedidos por consulta.', 'más de 100 pedidos por consulta se rechaza');
reset role;

select * from finish();
rollback;
