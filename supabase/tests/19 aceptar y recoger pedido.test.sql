-- Pruebas de aceptar_pedido / confirmar_recogida y de la lista de pedidos disponibles (RLS por rol).
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1,a2,a3,a5 solicitantes, b1 y b2 repartidores, c1 comercio, d1 zona, e1 comercio, 11 punto.
-- Pedidos (todos 1.000 + 2.000):
--   ac01 Creado (a1)            -> lo acepta b1
--   ac02 Creado (a2)            -> disponible; sirve para "no lo tienes asignado"
--   ac03 Asignado a b2 (a3)     -> ajeno para b1
--   ac04 Creado, solicitante b1 -> b1 no puede aceptar su propio pedido
--   ac05 Asignado a b1 (a5)     -> b1 confirma la recogida
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b2', 'rep2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co', 'Solicitante Tres',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co', 'Solicitante Cinco', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',    'repartidor'),
  ('00000000-0000-0000-0000-0000000000b2', 'rep2@eia.edu.co', 'Repartidor Dos',    'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1',  'comercio')
on conflict (id) do update set rol = excluded.rol;

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);
insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);
insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000ac01', '00000000-0000-0000-0000-0000000000a1', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',   1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ac02', '00000000-0000-0000-0000-0000000000a2', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',   1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ac03', '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000b2',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Asignado', 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ac04', '00000000-0000-0000-0000-0000000000b1', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',   1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ac05', '00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Asignado', 1000, 2000, 3000);

create function pg_temp.estado(p_id uuid) returns text language sql security definer as $f$
  select estado::text from public.pedidos where id = p_id
$f$;
create function pg_temp.repartidor(p_id uuid) returns uuid language sql security definer as $f$
  select repartidor_id from public.pedidos where id = p_id
$f$;

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

select plan(31);

-- ---------------------------------------------------------------------------
-- Estructura y permisos
-- ---------------------------------------------------------------------------
select has_function('public', 'aceptar_pedido', array['uuid'], 'existe aceptar_pedido(uuid)');
select is_definer('public', 'aceptar_pedido', array['uuid'], 'aceptar_pedido es SECURITY DEFINER');
select has_function('public', 'confirmar_recogida', array['uuid'], 'existe confirmar_recogida(uuid)');
select is_definer('public', 'confirmar_recogida', array['uuid'], 'confirmar_recogida es SECURITY DEFINER');
select ok(has_function_privilege('authenticated', 'public.aceptar_pedido(uuid)', 'execute'),
  'authenticated puede ejecutar aceptar_pedido');
select ok(not has_function_privilege('anon', 'public.aceptar_pedido(uuid)', 'execute'),
  'anon no puede ejecutar aceptar_pedido');
select ok(not has_function_privilege('anon', 'public.confirmar_recogida(uuid)', 'execute'),
  'anon no puede ejecutar confirmar_recogida');

-- ---------------------------------------------------------------------------
-- Listar pedidos: RLS por rol
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select is((select count(*)::int from public.pedidos where estado = 'Creado' and repartidor_id is null), 3,
  'el repartidor ve los 3 pedidos disponibles (Creado sin repartidor)');
select is((select count(*)::int from public.pedidos), 4,
  'el repartidor ve disponibles + el suyo, y no el Asignado de otro');
select is((select count(*)::int from public.pedidos where id = '00000000-0000-0000-0000-00000000ac03'), 0,
  'el repartidor 1 no ve el pedido asignado al repartidor 2');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.pedidos), 1, 'un solicitante solo ve su propio pedido, no los disponibles de otros');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select is((select count(*)::int from public.pedidos), 5, 'el comercio ve los pedidos de su comercio');
reset role;

select pg_temp.como_anon();
select throws_ok($$ select count(*) from public.pedidos $$, '42501', null, 'anon no lee pedidos');
reset role;

-- ---------------------------------------------------------------------------
-- aceptar_pedido
-- ---------------------------------------------------------------------------
select pg_temp.como_anon();
select throws_ok($$ select public.aceptar_pedido('00000000-0000-0000-0000-00000000ac01') $$, '42501', null,
  'sin sesión no se puede aceptar');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_like($$ select public.aceptar_pedido('00000000-0000-0000-0000-00000000ac01') $$, 'ROL_NO_PERMITIDO%',
  'un solicitante no puede aceptar pedidos');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_like($$ select public.aceptar_pedido('00000000-0000-0000-0000-00000000ac04') $$, 'PEDIDO_PROPIO%',
  'un repartidor no acepta su propio pedido');
select throws_like($$ select public.aceptar_pedido('00000000-0000-0000-0000-000000000999') $$, 'PEDIDO_NO_ENCONTRADO%',
  'un pedido inexistente se rechaza');
select throws_like($$ select public.aceptar_pedido('00000000-0000-0000-0000-00000000ac03') $$, 'PEDIDO_NO_DISPONIBLE%',
  'no se acepta un pedido que ya tiene repartidor');

select is((select public.aceptar_pedido('00000000-0000-0000-0000-00000000ac01') ->> 'estado'), 'Asignado',
  'b1 acepta el pedido disponible');
reset role;
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ac01'), 'Asignado', 'el pedido quedó Asignado');
select is(pg_temp.repartidor('00000000-0000-0000-0000-00000000ac01'), '00000000-0000-0000-0000-0000000000b1'::uuid,
  'con b1 como repartidor');

select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select throws_like($$ select public.aceptar_pedido('00000000-0000-0000-0000-00000000ac01') $$, 'PEDIDO_NO_DISPONIBLE%',
  'sin doble asignación: b2 no puede tomar un pedido que ya tomó b1');
select is((select count(*)::int from public.pedidos where id = '00000000-0000-0000-0000-00000000ac01'), 0,
  'y el pedido ya no aparece en la lista de b2');
reset role;
select is(pg_temp.repartidor('00000000-0000-0000-0000-00000000ac01'), '00000000-0000-0000-0000-0000000000b1'::uuid,
  'el repartidor del pedido no cambió');

-- ---------------------------------------------------------------------------
-- confirmar_recogida
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a5');
select throws_like($$ select public.confirmar_recogida('00000000-0000-0000-0000-00000000ac05') $$, 'ROL_NO_PERMITIDO%',
  'un solicitante no confirma recogidas');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select throws_like($$ select public.confirmar_recogida('00000000-0000-0000-0000-00000000ac05') $$, 'PEDIDO_NO_ENCONTRADO%',
  'otro repartidor no confirma la recogida de un pedido ajeno');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_like($$ select public.confirmar_recogida('00000000-0000-0000-0000-00000000ac02') $$, 'PEDIDO_NO_ENCONTRADO%',
  'no se confirma la recogida de un pedido que no tienes asignado');
select is((select public.confirmar_recogida('00000000-0000-0000-0000-00000000ac05') ->> 'estado'), 'En Camino',
  'b1 confirma la recogida: Asignado -> En Camino');
select throws_like($$ select public.confirmar_recogida('00000000-0000-0000-0000-00000000ac05') $$, 'ESTADO_NO_PERMITIDO%',
  'confirmar otra vez la recogida se rechaza');
reset role;
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ac05'), 'En Camino', 'el pedido quedó En Camino');
select ok((select en_camino_en is not null from public.pedidos where id = '00000000-0000-0000-0000-00000000ac05'),
  'se registró en_camino_en (lo usa la auto-confirmación)');

select * from finish();
rollback;
