-- Pruebas del estado del pago en el pedido y del pago digital (transferencia).
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1-a4 solicitantes, b1 repartidor, c1 comercio, f1 admin, d1 zona, e1 comercio, f1p producto, 11 punto.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000ad', 'adm1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co', 'Solicitante Tres',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co', 'Solicitante Cuatro', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',     'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1',   'comercio'),
  ('00000000-0000-0000-0000-0000000000ad', 'adm1@eia.edu.co', 'Administrador',      'admin')
on conflict (id) do update set rol = excluded.rol;

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);
insert into public.productos (id, comercio_id, nombre, precio, inventario_disponible, activo) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', 'Hamburguesa', 1000, 50, true);
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
create function pg_temp.pedido(p_sol uuid) returns uuid language sql security definer as $f$
  select id from public.pedidos where solicitante_id = p_sol order by creado_en desc limit 1
$f$;
create function pg_temp.col(p_id uuid, p_col text) returns text language plpgsql security definer as $f$
declare v text;
begin
  execute format('select %I::text from public.pedidos where id = $1', p_col) into v using p_id;
  return v;
end $f$;
create function pg_temp.pago(p_id uuid, p_col text) returns text language plpgsql security definer as $f$
declare v text;
begin
  execute format('select %I::text from public.pagos where pedido_id = $1', p_col) into v using p_id;
  return v;
end $f$;

select plan(26);

select has_column('public', 'pedidos', 'estado_pago', 'pedidos tiene estado_pago');
select has_column('public', 'pedidos', 'metodo_pago', 'pedidos tiene metodo_pago');
select ok(has_function_privilege('authenticated', 'public.confirmar_pago_digital(uuid)', 'execute'),
  'authenticated puede ejecutar confirmar_pago_digital (la función valida que sea admin)');
select ok(not has_function_privilege('anon', 'public.confirmar_pago_digital(uuid)', 'execute'),
  'anon no puede ejecutar confirmar_pago_digital');

-- ---------------------------------------------------------------------------
-- crear_pedido con método de pago
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
  '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]'::jsonb) $$,
  'sin método de pago el pedido se crea (compatibilidad con 3 argumentos)');
reset role;
select is(pg_temp.col(pg_temp.pedido('00000000-0000-0000-0000-0000000000a1'), 'metodo_pago'), 'efectivo', 'por defecto es efectivo');
select is(pg_temp.col(pg_temp.pedido('00000000-0000-0000-0000-0000000000a1'), 'estado_pago'), 'pendiente', 'y el pago queda pendiente');

select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select throws_like($$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
  '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]'::jsonb, null, 'pasarela') $$,
  'METODO_PAGO_NO_DISPONIBLE%', 'la pasarela aún no está disponible');
select is((select public.crear_pedido('00000000-0000-0000-0000-000000000011',
  '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]'::jsonb, null, 'transferencia') ->> 'metodo_pago'),
  'transferencia', 'el pedido se crea con pago por transferencia');
reset role;
select is(pg_temp.col(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2'), 'metodo_pago'), 'transferencia', 'el pedido guarda el método');
select is(pg_temp.pago(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2'), 'metodo'), 'transferencia', 'el pago nace con el mismo método');
select is(pg_temp.col(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2'), 'estado_pago'), 'pendiente', 'y pendiente');

-- Visible para el solicitante junto al pedido
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select is((select estado_pago::text from public.pedidos limit 1), 'pendiente', 'el solicitante lee el estado del pago en su pedido');
reset role;

-- ---------------------------------------------------------------------------
-- Cada método se cobra por su camino
-- ---------------------------------------------------------------------------
-- a2 (transferencia) pasa a En Camino con b1
update public.pedidos set repartidor_id = '00000000-0000-0000-0000-0000000000b1', estado = 'Asignado'
 where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a2');
update public.pedidos set estado = 'En Camino' where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a2');

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_like($$ select public.registrar_cobro_efectivo(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2')) $$,
  'PAGO_NO_ES_EFECTIVO%', 'el domiciliario no cobra en efectivo un pedido por transferencia');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_like($$ select public.confirmar_pago_digital(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2')) $$,
  'ROL_NO_PERMITIDO%', 'solo un admin confirma pagos digitales');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select throws_like($$ select public.confirmar_pago_digital(pg_temp.pedido('00000000-0000-0000-0000-0000000000a1')) $$,
  'PAGO_NO_ES_DIGITAL%', 'un pedido en efectivo no se confirma como digital');
select is((select public.confirmar_pago_digital(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2')) ->> 'estado_pago'),
  'en_custodia', 'el admin aprueba la transferencia y los fondos quedan en custodia');
select throws_like($$ select public.confirmar_pago_digital(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2')) $$,
  'PAGO_YA_RETENIDO%', 'no se retiene dos veces');
reset role;
select is(pg_temp.col(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2'), 'estado_pago'), 'en_custodia', 'el pedido refleja el pago en custodia');
select is(pg_temp.col(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2'), 'estado'), 'En Camino', 'y sigue En Camino');

-- El solicitante confirma la recepción: pedido digital ya pagado -> Cerrado solo
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select lives_ok($$ select public.confirmar_recepcion(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2')) $$,
  'el solicitante confirma que recibió');
reset role;
select is(pg_temp.col(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2'), 'estado'), 'Cerrado',
  'un pedido digital ya pagado queda Cerrado al entregarse');

-- Entregado con pago digital pendiente: confirmar el pago lo cierra
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select public.crear_pedido('00000000-0000-0000-0000-000000000011',
  '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]'::jsonb, null, 'transferencia');
reset role;
update public.pedidos set repartidor_id = '00000000-0000-0000-0000-0000000000b1', estado = 'Asignado'
 where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a3');
update public.pedidos set estado = 'En Camino' where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a3');
update public.pedidos set estado = 'Entregado' where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a3');
select is(pg_temp.col(pg_temp.pedido('00000000-0000-0000-0000-0000000000a3'), 'estado'), 'Entregado',
  'Entregado con pago digital pendiente no se cierra solo');
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select is((select public.confirmar_pago_digital(pg_temp.pedido('00000000-0000-0000-0000-0000000000a3')) ->> 'estado_pedido'),
  'Cerrado', 'aprobar el pago de un pedido Entregado libera los fondos y lo cierra');
reset role;

-- Cancelar un pedido ya cobrado deja el pago devuelto
select pg_temp.como('00000000-0000-0000-0000-0000000000a4');
select public.crear_pedido('00000000-0000-0000-0000-000000000011',
  '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]'::jsonb, null, 'transferencia');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000ad');
select public.confirmar_pago_digital(pg_temp.pedido('00000000-0000-0000-0000-0000000000a4'));
reset role;
update public.pedidos set estado = 'Cancelado' where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a4');
select is(pg_temp.pago(pg_temp.pedido('00000000-0000-0000-0000-0000000000a4'), 'estado'), 'devuelto',
  'cancelar un pedido con el pago en custodia lo deja devuelto');
select is(pg_temp.col(pg_temp.pedido('00000000-0000-0000-0000-0000000000a4'), 'estado_pago'), 'devuelto',
  'y el pedido lo refleja');

select * from finish();
rollback;
