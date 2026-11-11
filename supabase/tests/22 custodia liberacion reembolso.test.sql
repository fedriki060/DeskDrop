-- Pruebas de custodia (tarea 2), liberación al domiciliario (tarea 3) y reembolso (tarea 4).
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1-a4 solicitantes, b1 repartidor, c1 comercio, ad admin, e1 comercio, f1 producto, 11 punto.
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
create function pg_temp.pago(p_sol uuid, p_col text) returns text language plpgsql security definer as $f$
declare v text;
begin
  execute format('select %I::text from public.pagos where pedido_id = $1', p_col) into v using pg_temp.pedido(p_sol);
  return v;
end $f$;
create function pg_temp.estado(p_sol uuid) returns text language sql security definer as $f$
  select estado::text from public.pedidos where id = pg_temp.pedido(p_sol)
$f$;
create function pg_temp.movs(p_sol uuid, p_tipo text) returns int language sql security definer as $f$
  select count(*)::int from public.movimientos_pago where pedido_id = pg_temp.pedido(p_sol) and tipo = p_tipo
$f$;
create function pg_temp.crear_digital(p_sol uuid) returns void language plpgsql as $f$
begin
  perform pg_temp.como(p_sol);
  perform public.crear_pedido('00000000-0000-0000-0000-000000000011',
    '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]'::jsonb, null, 'transferencia');
  reset role;
end $f$;

select plan(28);

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
select has_table('public', 'movimientos_pago', 'existe el libro de movimientos');
select ok(has_function_privilege('service_role', 'public.retener_pago(uuid, text, uuid)', 'execute'),
  'service_role puede ejecutar retener_pago (la Edge Function)');
select ok(not has_function_privilege('authenticated', 'public.retener_pago(uuid, text, uuid)', 'execute'),
  'authenticated no puede ejecutar retener_pago');
select ok(not has_function_privilege('anon', 'public.retener_pago(uuid, text, uuid)', 'execute'),
  'anon no puede ejecutar retener_pago');
select ok(not has_function_privilege('authenticated', 'public._retener_pago(uuid, uuid, text)', 'execute'),
  'la lógica interna no se expone');

-- ---------------------------------------------------------------------------
-- Tarea 2: retener los fondos (a1: pago digital, por la puerta de la Edge Function)
-- ---------------------------------------------------------------------------
select pg_temp.crear_digital('00000000-0000-0000-0000-0000000000a1');
select is(pg_temp.pago('00000000-0000-0000-0000-0000000000a1', 'estado'), 'pendiente', 'el pago digital nace pendiente');

select is((select public.retener_pago(pg_temp.pedido('00000000-0000-0000-0000-0000000000a1'), 'PASARELA-001', null) ->> 'estado_pago'),
  'en_custodia', 'retener_pago deja el pago en custodia');
select is(pg_temp.pago('00000000-0000-0000-0000-0000000000a1', 'estado'), 'en_custodia', 'el pago queda en custodia');
select is((select estado_pago::text from public.pedidos where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a1')),
  'en_custodia', 'el pedido refleja la custodia (llega por Realtime)');
select is(pg_temp.movs('00000000-0000-0000-0000-0000000000a1', 'retencion'), 1, 'se registra el movimiento de retención');
select is((select referencia from public.movimientos_pago where pedido_id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a1') and tipo = 'retencion'),
  'PASARELA-001', 'con la referencia de la pasarela');
select throws_like($$ select public.retener_pago(pg_temp.pedido('00000000-0000-0000-0000-0000000000a1'), 'PASARELA-001', null) $$,
  'PAGO_YA_RETENIDO%', 'un reintento del webhook no retiene dos veces');
select is(pg_temp.movs('00000000-0000-0000-0000-0000000000a1', 'retencion'), 1, 'y no duplica el movimiento');

-- El solicitante ve su movimiento, pero no la referencia de la pasarela
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.movimientos_pago), 1, 'el solicitante ve los movimientos de su pedido');
select throws_like($$ select referencia from public.movimientos_pago $$, 'permission denied%',
  'pero no la referencia externa');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select is((select count(*)::int from public.movimientos_pago), 0, 'otro solicitante no ve movimientos ajenos');
reset role;

-- ---------------------------------------------------------------------------
-- Tarea 3: liberar al domiciliario cuando el pedido pasa a Entregado (RN-004)
-- ---------------------------------------------------------------------------
update public.pedidos set repartidor_id = '00000000-0000-0000-0000-0000000000b1', estado = 'Asignado'
 where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a1');
update public.pedidos set estado = 'En Camino' where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a1');
select is(pg_temp.pago('00000000-0000-0000-0000-0000000000a1', 'estado'), 'en_custodia', 'En Camino: los fondos siguen en custodia');
select is(pg_temp.movs('00000000-0000-0000-0000-0000000000a1', 'liberacion'), 0, 'y no hay liberación todavía');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$ select public.confirmar_recepcion(pg_temp.pedido('00000000-0000-0000-0000-0000000000a1')) $$,
  'el solicitante confirma la recepción');
reset role;
select is(pg_temp.pago('00000000-0000-0000-0000-0000000000a1', 'estado'), 'liberado', 'Entregado: los fondos se liberan');
select is(pg_temp.estado('00000000-0000-0000-0000-0000000000a1'), 'Cerrado', 'y el pedido queda Cerrado');
select is((select destinatario_id::text from public.movimientos_pago where pedido_id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a1') and tipo = 'liberacion'),
  '00000000-0000-0000-0000-0000000000b1', 'la liberación va al domiciliario del pedido');
select is((select (detalle ->> 'tarifa_repartidor')::numeric from public.movimientos_pago where pedido_id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a1') and tipo = 'liberacion'),
  1600.00, 'el desglose guarda el 80 % de la tarifa para el domiciliario (RN del piloto)');

-- Pago aprobado DESPUÉS de la entrega (a3): se retiene y se libera en el acto
select pg_temp.crear_digital('00000000-0000-0000-0000-0000000000a3');
update public.pedidos set repartidor_id = '00000000-0000-0000-0000-0000000000b1', estado = 'Asignado'
 where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a3');
update public.pedidos set estado = 'En Camino' where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a3');
update public.pedidos set estado = 'Entregado' where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a3');
select is(pg_temp.pago('00000000-0000-0000-0000-0000000000a3', 'estado'), 'pendiente', 'Entregado sin pago aprobado: no hay nada que liberar');
select public.retener_pago(pg_temp.pedido('00000000-0000-0000-0000-0000000000a3'), 'PASARELA-003', null);
select is(pg_temp.pago('00000000-0000-0000-0000-0000000000a3', 'estado') || '/' || pg_temp.estado('00000000-0000-0000-0000-0000000000a3'),
  'liberado/Cerrado', 'aprobar el pago de un pedido ya Entregado retiene, libera y cierra');

-- ---------------------------------------------------------------------------
-- Tarea 4: reembolso automático al cancelar (a2: el job de T-043; a4: pago sin aprobar)
-- ---------------------------------------------------------------------------
select pg_temp.crear_digital('00000000-0000-0000-0000-0000000000a2');
select public.retener_pago(pg_temp.pedido('00000000-0000-0000-0000-0000000000a2'), 'PASARELA-002', null);
update public.pedidos set creado_en = now() - interval '11 minutes'
 where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a2');
select ok(public.cancelar_pedidos_vencidos() >= 1, 'el job de T-043 cancela el pedido vencido');
select is(pg_temp.pago('00000000-0000-0000-0000-0000000000a2', 'estado') || '/' || pg_temp.movs('00000000-0000-0000-0000-0000000000a2', 'reembolso'),
  'devuelto/1', 'al cancelarse, el pago retenido se reembolsa y queda registrado');

select pg_temp.crear_digital('00000000-0000-0000-0000-0000000000a4');
update public.pedidos set estado = 'Cancelado' where id = pg_temp.pedido('00000000-0000-0000-0000-0000000000a4');
select is(pg_temp.pago('00000000-0000-0000-0000-0000000000a4', 'estado') || '/' || pg_temp.movs('00000000-0000-0000-0000-0000000000a4', 'reembolso'),
  'pendiente/0', 'cancelar un pedido cuyo pago nunca se aprobó no genera reembolso');

select * from finish();
rollback;
