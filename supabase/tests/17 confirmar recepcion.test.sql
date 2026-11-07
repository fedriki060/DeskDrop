-- Pruebas de confirmar_recepcion (T-040): el solicitante dueño pasa su pedido de En Camino a Entregado.
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1-a4 solicitantes, b1 repartidor, c1 admin de comercio, d1 zona, e1 comercio, 11 punto.
-- Pedidos (ac0N es del solicitante aN), todos de 1.000 + 2.000 = 3.000:
--   ac01 En Camino (b1)   -> el caso feliz
--   ac02 Asignado (b1)    -> todavía no se puede confirmar
--   ac03 Creado           -> todavía no se puede confirmar
--   ac04 Cancelado        -> estado final, no se puede confirmar
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co', 'Solicitante Tres',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co', 'Solicitante Cuatro', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',     'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1',   'comercio')
on conflict (id) do update set rol = excluded.rol;

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);

insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);

insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000ac01', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ac02', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Asignado',  1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ac03', '00000000-0000-0000-0000-0000000000a3', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',    1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ac04', '00000000-0000-0000-0000-0000000000a4', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Cancelado', 1000, 2000, 3000);

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

select plan(20);

-- ---------------------------------------------------------------------------
-- Estructura y permisos
-- ---------------------------------------------------------------------------
select has_function('public', 'confirmar_recepcion', array['uuid'],
  'existe public.confirmar_recepcion(uuid)');
select is_definer('public', 'confirmar_recepcion', array['uuid'],
  'confirmar_recepcion es SECURITY DEFINER');
select ok(
  has_function_privilege('authenticated', 'public.confirmar_recepcion(uuid)', 'execute'),
  'authenticated puede ejecutar confirmar_recepcion');
select ok(
  not has_function_privilege('anon', 'public.confirmar_recepcion(uuid)', 'execute'),
  'anon no puede ejecutar confirmar_recepcion');

-- ---------------------------------------------------------------------------
-- Quién puede confirmar
-- ---------------------------------------------------------------------------
select pg_temp.como_anon();
select throws_ok(
  $$ select public.confirmar_recepcion('00000000-0000-0000-0000-00000000ac01') $$,
  '42501', null,
  'un usuario sin sesión no puede confirmar');
reset role;

-- Sesión de authenticated sin usuario (sub)
select set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
set local role authenticated;
select throws_ok(
  $$ select public.confirmar_recepcion('00000000-0000-0000-0000-00000000ac01') $$,
  '28000', 'NO_AUTENTICADO: Debes iniciar sesión.',
  'sin usuario en la sesión responde NO_AUTENTICADO');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select throws_ok(
  $$ select public.confirmar_recepcion('00000000-0000-0000-0000-00000000ac01') $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es tuyo.',
  'otro solicitante no puede confirmar un pedido ajeno');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_ok(
  $$ select public.confirmar_recepcion('00000000-0000-0000-0000-00000000ac01') $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es tuyo.',
  'el repartidor asignado no puede confirmar por el solicitante');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select throws_ok(
  $$ select public.confirmar_recepcion('00000000-0000-0000-0000-00000000ac01') $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es tuyo.',
  'el comercio no puede confirmar la recepción');
reset role;

select is(pg_temp.estado('00000000-0000-0000-0000-00000000ac01'), 'En Camino',
  'los intentos rechazados no cambian el pedido');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_ok(
  $$ select public.confirmar_recepcion('00000000-0000-0000-0000-0000000000ff') $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es tuyo.',
  'un pedido que no existe responde PEDIDO_NO_ENCONTRADO');

-- ---------------------------------------------------------------------------
-- Caso feliz: En Camino -> Entregado
-- ---------------------------------------------------------------------------
select is(
  public.confirmar_recepcion('00000000-0000-0000-0000-00000000ac01') ->> 'estado',
  'Entregado',
  'el solicitante dueño confirma y la función devuelve estado Entregado');
reset role;

select is(pg_temp.estado('00000000-0000-0000-0000-00000000ac01'), 'Entregado',
  'el pedido queda Entregado en la tabla');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_ok(
  $$ select public.confirmar_recepcion('00000000-0000-0000-0000-00000000ac01') $$,
  '55000', 'ESTADO_NO_PERMITIDO: Solo puedes confirmar un pedido que está En Camino (estado actual: Entregado).',
  'confirmar dos veces responde ESTADO_NO_PERMITIDO');

-- RN-001: un pedido Entregado ya no es activo, así que el solicitante puede pedir otro
reset role;
select lives_ok(
  $$ insert into public.pedidos (solicitante_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total)
     values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e1',
             '00000000-0000-0000-0000-000000000011', 'Creado', 1000, 2000, 3000) $$,
  'con el pedido Entregado, el solicitante puede crear otro');

-- Con el pedido Entregado, el repartidor ya puede registrar el cobro en efectivo (T-031)
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select lives_ok(
  $$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000ac01') $$,
  'el repartidor puede registrar el cobro después de la confirmación');
reset role;

-- ---------------------------------------------------------------------------
-- Estados desde los que no se puede confirmar
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select throws_ok(
  $$ select public.confirmar_recepcion('00000000-0000-0000-0000-00000000ac02') $$,
  '55000', 'ESTADO_NO_PERMITIDO: Solo puedes confirmar un pedido que está En Camino (estado actual: Asignado).',
  'no se puede confirmar un pedido Asignado (aún no lo recogen)');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select throws_ok(
  $$ select public.confirmar_recepcion('00000000-0000-0000-0000-00000000ac03') $$,
  '55000', 'ESTADO_NO_PERMITIDO: Solo puedes confirmar un pedido que está En Camino (estado actual: Creado).',
  'no se puede confirmar un pedido Creado');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a4');
select throws_ok(
  $$ select public.confirmar_recepcion('00000000-0000-0000-0000-00000000ac04') $$,
  '55000', 'ESTADO_NO_PERMITIDO: Solo puedes confirmar un pedido que está En Camino (estado actual: Cancelado).',
  'no se puede confirmar un pedido Cancelado');
reset role;

select is(pg_temp.estado('00000000-0000-0000-0000-00000000ac02'), 'Asignado',
  'el pedido Asignado sigue igual tras el intento');

select * from finish();
rollback;
