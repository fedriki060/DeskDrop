-- Pruebas de pagos manuales: pago pendiente automático, RLS y registrar_cobro_efectivo.
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1-a3 solicitantes, b1-b2 repartidores, c1 admin de comercio, d1 zona, e1 comercio,
--      f6 producto (3.000 x 10 uds), 11 punto del campus.
-- Pedidos directos: aa01 (a1, b1, Entregado), aa02 (a2, b1, En Camino), aa03 (a3, b2, Entregado); todos de 1.000 + 2.000 = 3.000.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b2', 'rep2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co', 'Solicitante Tres', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',   'repartidor'),
  ('00000000-0000-0000-0000-0000000000b2', 'rep2@eia.edu.co', 'Repartidor Dos',   'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1', 'comercio')
on conflict (id) do update set rol = excluded.rol;

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);

insert into public.productos (id, comercio_id, nombre, precio, inventario_disponible, activo) values
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000e1', 'Papas', 3000, 10, true);

insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);

insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Entregado', 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000aa03', '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000b2',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Entregado', 1000, 2000, 3000);

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

select plan(27);

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
select has_function('public', 'registrar_cobro_efectivo', array['uuid'], 'existe registrar_cobro_efectivo');
select function_privs_are('public', 'registrar_cobro_efectivo', array['uuid'], 'anon', array[]::text[],
  'anon no puede ejecutar registrar_cobro_efectivo');
select function_privs_are('public', 'registrar_cobro_efectivo', array['uuid'], 'authenticated', array['EXECUTE'],
  'authenticated puede ejecutar registrar_cobro_efectivo');

-- ---------------------------------------------------------------------------
-- Cada pedido nace con su pago pendiente (efectivo, monto = total)
-- ---------------------------------------------------------------------------
select results_eq(
  $$ select estado, metodo, monto, registrado_por, fecha_pago from public.pagos
     where pedido_id = '00000000-0000-0000-0000-00000000aa01' $$,
  $$ values ('pendiente'::public.estado_pago, 'efectivo'::public.metodo_pago, 3000.00::numeric, null::uuid, null::timestamptz) $$,
  'un pedido insertado crea su pago pendiente en efectivo por el total');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select set_config('test.pedido', public.crear_pedido(
       '00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]')::text, true) $$,
  'crear_pedido crea el pedido');

reset role;
select results_eq(
  $$ select estado, metodo, monto from public.pagos
     where pedido_id = (current_setting('test.pedido')::jsonb ->> 'pedido_id')::uuid $$,
  $$ values ('pendiente'::public.estado_pago, 'efectivo'::public.metodo_pago, 5000.00::numeric) $$,
  'el pedido creado con crear_pedido tiene su pago pendiente (3.000 + 2.000)');

-- ---------------------------------------------------------------------------
-- RLS de pagos: ve el pago quien ve el pedido
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.pagos), 2, 'el solicitante 1 ve los pagos de sus 2 pedidos');
select throws_ok(
  $$ update public.pagos set estado = 'cobrado' $$,
  '42501', null, 'nadie modifica pagos directamente desde la API');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select is((select count(*)::int from public.pagos), 2, 'el repartidor 1 ve los pagos de sus 2 pedidos');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select is((select count(*)::int from public.pagos), 1, 'el repartidor 2 ve solo el pago de su pedido');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select is((select count(*)::int from public.pagos), 1, 'el solicitante 2 ve solo su pago');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select is((select count(*)::int from public.pagos), 4, 'el comercio ve los pagos de los pedidos de su comercio');

reset role; select pg_temp.como_anon();
select throws_ok($$ select count(*) from public.pagos $$, '42501', null, 'anon no lee pagos');

-- ---------------------------------------------------------------------------
-- registrar_cobro_efectivo: quién puede
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como_anon();
select throws_ok(
  $$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000aa01') $$,
  '42501', null, 'anon recibe permission denied');

reset role; select pg_temp.como(null);
select throws_ok(
  $$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000aa01') $$,
  '28000', null, 'sin sesión no se registra cobro');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_like(
  $$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000aa01') $$,
  'ROL_NO_PERMITIDO%', 'un solicitante no registra cobros');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select throws_like(
  $$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000aa01') $$,
  'ROL_NO_PERMITIDO%', 'un comercio no registra cobros');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select throws_like(
  $$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000aa01') $$,
  'PEDIDO_NO_ENCONTRADO%', 'un repartidor no cobra un pedido que no tiene asignado');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_like(
  $$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000aa02') $$,
  'ESTADO_NO_PERMITIDO%', 'no se cobra un pedido que aún está En Camino');

-- ---------------------------------------------------------------------------
-- registrar_cobro_efectivo: camino feliz
-- ---------------------------------------------------------------------------
select lives_ok(
  $$ select set_config('test.cobro', public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000aa01')::text, true) $$,
  'el repartidor registra el cobro en efectivo de un pedido Entregado');
select is((current_setting('test.cobro')::jsonb ->> 'monto')::numeric, 3000::numeric, 'la respuesta trae el monto del pedido');

reset role;
select results_eq(
  $$ select estado, metodo, monto, registrado_por, fecha_pago is not null from public.pagos
     where pedido_id = '00000000-0000-0000-0000-00000000aa01' $$,
  $$ values ('cobrado'::public.estado_pago, 'efectivo'::public.metodo_pago, 3000.00::numeric,
             '00000000-0000-0000-0000-0000000000b1'::uuid, true) $$,
  'el pago queda cobrado, con quién lo registró y cuándo');
select is((select estado::text from public.pedidos where id = '00000000-0000-0000-0000-00000000aa01'), 'Cerrado',
  'el pedido cobrado pasa a Cerrado');

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_like(
  $$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000aa01') $$,
  'PAGO_YA_COBRADO%', 'un segundo cobro del mismo pedido se rechaza');

-- El pedido En Camino se cobra cuando pasa a Entregado.
reset role;
update public.pedidos set estado = 'Entregado' where id = '00000000-0000-0000-0000-00000000aa02';
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select lives_ok(
  $$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000aa02') $$,
  'al pasar a Entregado, el pedido anterior ya se puede cobrar');

-- ---------------------------------------------------------------------------
-- Integridad y pagos no cobrables
-- ---------------------------------------------------------------------------
reset role;
select throws_ok(
  $$ update public.pagos set estado = 'cobrado' where pedido_id = '00000000-0000-0000-0000-00000000aa03' $$,
  '23514', null, 'un pago cobrado exige quién lo registró y la fecha');

update public.pagos set estado = 'devuelto' where pedido_id = '00000000-0000-0000-0000-00000000aa03';
select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select throws_like(
  $$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000aa03') $$,
  'PAGO_NO_COBRABLE%', 'un pago devuelto no se vuelve a cobrar');

select * from finish();
rollback;
