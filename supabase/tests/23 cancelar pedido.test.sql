-- Pruebas de HU-24: cancelar_pedido y reposición de inventario, manual y automática (T-104).
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1-a5 solicitantes, b1 domiciliario, c1 y c2 admins de comercio, d1 zona, e1 y e2 comercios,
--      f1 producto del comercio e1 con 10 unidades, 11 punto del campus.
-- Pedidos (se crean con crear_pedido, que descuenta el inventario):
--   p1 a1 x2 (cancela el solicitante)   p2 a2 x3 (lo rechaza el comercio estando Asignado a b1)
--   p3 a3 x1 (sale En Camino: ya no se cancela)   p4 a4 x1 (lo cancela el job por tiempo)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'com2@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co', 'Solicitante Tres',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co', 'Solicitante Cuatro', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co', 'Solicitante Cinco',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',     'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1',   'comercio'),
  ('00000000-0000-0000-0000-0000000000c2', 'com2@eia.edu.co', 'Admin Comercio 2',   'comercio')
on conflict (id) do update set rol = excluded.rol;

insert into public.aceptaciones_repartidor (usuario_id, version) values
  ('00000000-0000-0000-0000-0000000000b1', 'test');

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c2', 'Papelería Test', true);
insert into public.productos (id, comercio_id, nombre, precio, inventario_disponible, activo) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', 'Hamburguesa', 22000, 10, true);
insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);
insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

create function pg_temp.como(p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $f$;

-- Id del pedido guardado como test.pN
create function pg_temp.p(n int) returns uuid language sql as $f$
  select current_setting('test.p' || n)::uuid
$f$;

create function pg_temp.stock() returns int language sql security definer as $f$
  select inventario_disponible from public.productos where id = '00000000-0000-0000-0000-0000000000f1'
$f$;

create function pg_temp.dato(p_id uuid, p_columna text) returns text language plpgsql security definer as $f$
declare v text;
begin
  execute format('select %I::text from public.pedidos where id = $1', p_columna) into v using p_id;
  return v;
end $f$;

-- Pedidos de prueba, creados como lo haría la app (descuentan inventario)
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select set_config('test.p1', public.crear_pedido('00000000-0000-0000-0000-000000000011',
  '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":2}]') ->> 'pedido_id', true);
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select set_config('test.p2', public.crear_pedido('00000000-0000-0000-0000-000000000011',
  '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":3}]') ->> 'pedido_id', true);
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select set_config('test.p3', public.crear_pedido('00000000-0000-0000-0000-000000000011',
  '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]') ->> 'pedido_id', true);
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000a4');
select set_config('test.p4', public.crear_pedido('00000000-0000-0000-0000-000000000011',
  '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]') ->> 'pedido_id', true);
reset role;

-- b1 acepta p2 (queda Asignado)
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select public.aceptar_pedido(pg_temp.p(2));
reset role;

select plan(21);

select has_function('public', 'cancelar_pedido', array['uuid', 'text'], 'existe cancelar_pedido(uuid, text)');
select ok(not has_function_privilege('anon', 'public.cancelar_pedido(uuid, text)', 'execute'),
  'anon no puede ejecutar cancelar_pedido');

-- Quién no puede cancelar
select pg_temp.como('00000000-0000-0000-0000-0000000000a5');
select throws_ok($$ select public.cancelar_pedido(pg_temp.p(1)) $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es tuyo.', 'otro solicitante no puede cancelar un pedido ajeno');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000c2');
select throws_ok($$ select public.cancelar_pedido(pg_temp.p(1)) $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es tuyo.', 'el dueño de otro comercio no puede rechazar el pedido');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.cancelar_pedido(pg_temp.p(2)) $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es tuyo.', 'el domiciliario no puede cancelar el pedido que tiene asignado');
reset role;

-- El solicitante cancela su pedido
select is(pg_temp.stock(), 3, 'antes de cancelar el inventario está descontado (10 - 2 - 3 - 1 - 1)');
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is(public.cancelar_pedido(pg_temp.p(1), 'Me equivoqué') ->> 'estado', 'Cancelado',
  'el solicitante cancela su pedido Creado');
reset role;
select is(pg_temp.dato(pg_temp.p(1), 'cancelado_por'), 'solicitante', 'queda registrado que canceló el solicitante');
select is(pg_temp.dato(pg_temp.p(1), 'motivo_cancelacion'), 'Me equivoqué', 'queda el motivo');
select is(pg_temp.stock(), 5, 'al cancelar se repone el inventario (+2)');
select is(
  (select count(*)::int from public.pedidos
   where solicitante_id = '00000000-0000-0000-0000-0000000000a1' and estado in ('Creado', 'Asignado', 'En Camino')),
  0, 'el solicitante queda libre para hacer otro pedido');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$ select public.cancelar_pedido(pg_temp.p(1)) $$,
  '55000', 'ESTADO_NO_PERMITIDO: Solo puedes cancelar un pedido Creado o Asignado (estado actual: Cancelado).',
  'cancelar dos veces responde ESTADO_NO_PERMITIDO');
reset role;

-- El comercio rechaza un pedido ya Asignado
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select is(public.cancelar_pedido(pg_temp.p(2), 'Sin inventario') ->> 'estado', 'Cancelado',
  'el comercio rechaza un pedido Asignado');
reset role;
select is(pg_temp.dato(pg_temp.p(2), 'cancelado_por'), 'comercio', 'queda registrado que rechazó el comercio');
select is(pg_temp.stock(), 8, 'al rechazar se repone el inventario (+3)');

-- Libre el domiciliario, acepta otro; con el pedido En Camino ya no se cancela
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select lives_ok($$ select public.aceptar_pedido(pg_temp.p(3)) $$, 'con la entrega cancelada, el domiciliario puede aceptar otro pedido');
reset role;
update public.pedidos set listo_para_recoger = true where id = pg_temp.p(3);
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select public.confirmar_recogida(pg_temp.p(3));
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select throws_ok($$ select public.cancelar_pedido(pg_temp.p(3)) $$,
  '55000', 'ESTADO_NO_PERMITIDO: Solo puedes cancelar un pedido Creado o Asignado (estado actual: En Camino).',
  'un pedido En Camino no se puede cancelar');
reset role;

-- Motivo demasiado largo
select pg_temp.como('00000000-0000-0000-0000-0000000000a4');
select throws_ok($$ select public.cancelar_pedido(pg_temp.p(4), repeat('x', 201)) $$,
  '22023', 'MOTIVO_INVALIDO: El motivo puede tener máximo 200 caracteres.', 'un motivo de más de 200 caracteres se rechaza');
reset role;

-- Auto-cancelación por tiempo: también repone el inventario
update public.pedidos set creado_en = now() - interval '11 minutes' where id = pg_temp.p(4);
select is(public.cancelar_pedidos_vencidos(), 1, 'el job cancela el pedido vencido');
select is(pg_temp.stock(), 9, 'la auto-cancelación también repone el inventario (+1)');
select is(pg_temp.dato(pg_temp.p(4), 'cancelado_por'), 'sistema', 'queda registrado que canceló el sistema');

select * from finish();
rollback;
