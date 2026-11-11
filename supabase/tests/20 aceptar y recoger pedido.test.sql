-- Pruebas de HU-21: aceptar_pedido y confirmar_recogida (T-084, T-085).
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1-a3, a5-a7 solicitantes, a4 solicitante que también es domiciliario, b1 y b2 domiciliarios,
--      c1 admin de comercio, d1 zona, e1 comercio, 11 punto del campus.
-- Pedidos (todos de 1.000 + 2.000 = 3.000):
--   ba01 a1 Creado            -> lo acepta b1 (caso feliz)
--   ba03 a4 Creado            -> a4 no puede aceptar su propio pedido
--   ba04 a5 Asignado (b1)     -> no está listo para recoger
--   ba05 a6 Asignado (b1) listo -> recogida feliz
--   ba06 a7 Creado            -> b1 no lo tiene asignado
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a6', 'sol6@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a7', 'sol7@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b2', 'rep2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co', 'Solicitante Cuatro', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co', 'Solicitante Cinco',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000a6', 'sol6@eia.edu.co', 'Solicitante Seis',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a7', 'sol7@eia.edu.co', 'Solicitante Siete',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',     'repartidor'),
  ('00000000-0000-0000-0000-0000000000b2', 'rep2@eia.edu.co', 'Repartidor Dos',     'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1',   'comercio')
on conflict (id) do update set rol = excluded.rol;

-- b1, b2 y a4 ya aceptaron la declaración de +18 (HU-19); a2 no.
insert into public.aceptaciones_repartidor (usuario_id, version) values
  ('00000000-0000-0000-0000-0000000000a4', 'test'),
  ('00000000-0000-0000-0000-0000000000b1', 'test'),
  ('00000000-0000-0000-0000-0000000000b2', 'test');

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);
insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);
insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, listo_para_recoger, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000ba01', '00000000-0000-0000-0000-0000000000a1', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',   false, 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ba03', '00000000-0000-0000-0000-0000000000a4', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',   false, 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ba04', '00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Asignado', false, 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ba05', '00000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Asignado', true,  1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ba06', '00000000-0000-0000-0000-0000000000a7', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',   false, 1000, 2000, 3000);

create function pg_temp.estado(p_id uuid) returns text language sql security definer as $f$
  select estado::text from public.pedidos where id = p_id
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

select plan(23);

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
select has_function('public', 'aceptar_pedido', array['uuid'], 'existe aceptar_pedido');
select has_function('public', 'confirmar_recogida', array['uuid'], 'existe confirmar_recogida');
select ok(has_function_privilege('authenticated', 'public.aceptar_pedido(uuid)', 'execute'),
  'authenticated puede ejecutar aceptar_pedido');
select ok(not has_function_privilege('anon', 'public.aceptar_pedido(uuid)', 'execute'),
  'anon no puede ejecutar aceptar_pedido');
select ok(not has_function_privilege('anon', 'public.confirmar_recogida(uuid)', 'execute'),
  'anon no puede ejecutar confirmar_recogida');

-- ---------------------------------------------------------------------------
-- aceptar_pedido: quién puede
-- ---------------------------------------------------------------------------
select pg_temp.como_anon();
select throws_ok($$ select public.aceptar_pedido('00000000-0000-0000-0000-00000000ba01') $$,
  '42501', null, 'sin sesión no se puede aceptar');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select throws_ok($$ select public.aceptar_pedido('00000000-0000-0000-0000-00000000ba01') $$,
  '42501', 'ROL_NO_PERMITIDO: Solo un domiciliario habilitado puede aceptar pedidos.',
  'un usuario que no ha activado la vista de domiciliario no puede aceptar');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$ select public.aceptar_pedido('00000000-0000-0000-0000-00000000ba01') $$,
  '42501', null, 'el comercio no puede aceptar pedidos');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a4');
select throws_ok($$ select public.aceptar_pedido('00000000-0000-0000-0000-00000000ba03') $$,
  '42501', 'PEDIDO_PROPIO: No puedes entregarte tu propio pedido.',
  'un domiciliario no puede aceptar su propio pedido');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.aceptar_pedido('00000000-0000-0000-0000-0000000000ff') $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe.', 'un pedido que no existe responde PEDIDO_NO_ENCONTRADO');

-- ---------------------------------------------------------------------------
-- aceptar_pedido: caso feliz y carrera
-- ---------------------------------------------------------------------------
select is(public.aceptar_pedido('00000000-0000-0000-0000-00000000ba01') ->> 'estado', 'Asignado',
  'el domiciliario acepta un pedido Creado y queda Asignado');
reset role;
select is((select repartidor_id from public.pedidos where id = '00000000-0000-0000-0000-00000000ba01'),
  '00000000-0000-0000-0000-0000000000b1'::uuid, 'el pedido queda asignado a quien lo aceptó');

select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select throws_ok($$ select public.aceptar_pedido('00000000-0000-0000-0000-00000000ba01') $$,
  '55000', 'PEDIDO_NO_DISPONIBLE: Otro domiciliario ya tomó este pedido o ya no está disponible.',
  'un segundo domiciliario no puede tomar un pedido ya asignado');
reset role;

select is((select repartidor_id from public.pedidos where id = '00000000-0000-0000-0000-00000000ba01'),
  '00000000-0000-0000-0000-0000000000b1'::uuid, 'el pedido sigue con el primer domiciliario');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select estado::text from public.pedidos where id = '00000000-0000-0000-0000-00000000ba01'), 'Asignado',
  'el solicitante ve su pedido Asignado');
reset role;

-- ---------------------------------------------------------------------------
-- confirmar_recogida
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select throws_ok($$ select public.confirmar_recogida('00000000-0000-0000-0000-00000000ba05') $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no lo tienes asignado.',
  'otro domiciliario no puede confirmar la recogida de un pedido ajeno');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.confirmar_recogida('00000000-0000-0000-0000-00000000ba06') $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no lo tienes asignado.',
  'no se confirma la recogida de un pedido que no se tiene asignado');
select throws_ok($$ select public.confirmar_recogida('00000000-0000-0000-0000-00000000ba04') $$,
  '55000', 'PEDIDO_NO_LISTO: El comercio aún no marca el pedido como listo para recoger.',
  'no se confirma la recogida si el comercio no lo marcó listo');
select is(public.confirmar_recogida('00000000-0000-0000-0000-00000000ba05') ->> 'estado', 'En Camino',
  'con el pedido listo, el domiciliario confirma la recogida y queda En Camino');
reset role;
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ba05'), 'En Camino', 'el pedido queda En Camino en la tabla');
select isnt((select en_camino_en from public.pedidos where id = '00000000-0000-0000-0000-00000000ba05'), null,
  'se registra la hora de salida (en_camino_en)');

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.confirmar_recogida('00000000-0000-0000-0000-00000000ba05') $$,
  '55000', 'ESTADO_NO_PERMITIDO: Solo puedes confirmar la recogida de un pedido Asignado (estado actual: En Camino).',
  'confirmar la recogida dos veces responde ESTADO_NO_PERMITIDO');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select throws_ok($$ select public.confirmar_recogida('00000000-0000-0000-0000-00000000ba05') $$,
  '42501', null, 'un usuario no habilitado no puede confirmar recogidas');
reset role;

select * from finish();
rollback;
