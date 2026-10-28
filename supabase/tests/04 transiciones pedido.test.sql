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

select plan(29);

-- ---------------------------------------------------------------------------
-- La función de transiciones
-- ---------------------------------------------------------------------------
select has_function('public', 'transicion_pedido_permitida',
  array['estado_pedido', 'estado_pedido'], 'existe transicion_pedido_permitida');
select has_trigger('public', 'pedidos', 'trg_pedidos_validar_transicion',
  'pedidos tiene el trigger que valida transiciones');

-- Compara las 36 combinaciones contra la matriz esperada (diferencia vacía = coincide).
select is_empty(
  $$
  select d, h
  from unnest(enum_range(null::public.estado_pedido)) d
  cross join unnest(enum_range(null::public.estado_pedido)) h
  where public.transicion_pedido_permitida(d, h)
        is distinct from ((d::text, h::text) in (
          ('Creado',    'Asignado'),
          ('Creado',    'Cancelado'),
          ('Asignado',  'En Camino'),
          ('Asignado',  'Cancelado'),
          ('En Camino', 'Entregado'),
          ('Entregado', 'Cerrado')))
  $$,
  'la matriz de transiciones permitidas es exactamente la definida');

select is(public.transicion_pedido_permitida('Creado', 'Creado'), false,
  'quedarse en el mismo estado no cuenta como transición');

-- ---------------------------------------------------------------------------
-- Pedido A: camino feliz completo y estados finales
-- ---------------------------------------------------------------------------
insert into public.pedidos (id, solicitante_id, comercio_id, punto_entrega_id,
                            subtotal, tarifa_domicilio, total, creado_en, actualizado_en)
values ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1',
        '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011',
        10000, 2000, 12000, now() - interval '1 hour', now() - interval '1 hour');

select is((select estado from public.pedidos where id = '00000000-0000-0000-0000-00000000aa01'),
  'Creado'::public.estado_pedido, 'un pedido nuevo nace en estado Creado');

select throws_ok(
  $$ update public.pedidos set estado = 'Entregado' where id = '00000000-0000-0000-0000-00000000aa01' $$,
  '23514', 'TRANSICION_INVALIDA: no se puede pasar de "Creado" a "Entregado".',
  'Creado no puede saltar a Entregado');

select lives_ok(
  $$ update public.pedidos set estado = 'Asignado', repartidor_id = '00000000-0000-0000-0000-0000000000b1'
     where id = '00000000-0000-0000-0000-00000000aa01' $$,
  'Creado -> Asignado');

select ok(
  (select actualizado_en > creado_en from public.pedidos where id = '00000000-0000-0000-0000-00000000aa01'),
  'actualizado_en se renueva al cambiar de estado');

select throws_ok(
  $$ update public.pedidos set estado = 'Creado' where id = '00000000-0000-0000-0000-00000000aa01' $$,
  '23514', null, 'Asignado no puede volver a Creado');
select throws_ok(
  $$ update public.pedidos set estado = 'Entregado' where id = '00000000-0000-0000-0000-00000000aa01' $$,
  '23514', null, 'Asignado no puede saltar a Entregado');

select lives_ok(
  $$ update public.pedidos set estado = 'En Camino' where id = '00000000-0000-0000-0000-00000000aa01' $$,
  'Asignado -> En Camino');
select throws_ok(
  $$ update public.pedidos set estado = 'Cancelado' where id = '00000000-0000-0000-0000-00000000aa01' $$,
  '23514', null, 'un pedido En Camino ya no se puede cancelar');
select lives_ok(
  $$ update public.pedidos set estado = 'Entregado' where id = '00000000-0000-0000-0000-00000000aa01' $$,
  'En Camino -> Entregado');
select lives_ok(
  $$ update public.pedidos set estado = 'Cerrado' where id = '00000000-0000-0000-0000-00000000aa01' $$,
  'Entregado -> Cerrado');
select throws_ok(
  $$ update public.pedidos set estado = 'Creado' where id = '00000000-0000-0000-0000-00000000aa01' $$,
  '23514', null, 'Cerrado es un estado final');
select throws_ok(
  $$ update public.pedidos set estado = 'Cancelado' where id = '00000000-0000-0000-0000-00000000aa01' $$,
  '23514', null, 'Cerrado no puede cancelarse');

-- ---------------------------------------------------------------------------
-- Pedido B: cancelación y estado final
-- ---------------------------------------------------------------------------
insert into public.pedidos (id, solicitante_id, comercio_id, punto_entrega_id, subtotal, tarifa_domicilio, total)
values ('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-0000000000a1',
        '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 5000, 2000, 7000);

select lives_ok(
  $$ update public.pedidos set estado = 'Cancelado' where id = '00000000-0000-0000-0000-00000000aa02' $$,
  'Creado -> Cancelado');
select throws_ok(
  $$ update public.pedidos set estado = 'Creado' where id = '00000000-0000-0000-0000-00000000aa02' $$,
  '23514', null, 'un pedido Cancelado no se puede reactivar');
select throws_ok(
  $$ update public.pedidos set estado = 'Asignado' where id = '00000000-0000-0000-0000-00000000aa02' $$,
  '23514', null, 'un pedido Cancelado no se puede asignar');
select lives_ok(
  $$ update public.pedidos set notas_entrega = 'cambio de notas' where id = '00000000-0000-0000-0000-00000000aa02' $$,
  'actualizar otros campos sin cambiar de estado no se bloquea');

-- ---------------------------------------------------------------------------
-- Integridad del total
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into public.pedidos (solicitante_id, comercio_id, punto_entrega_id, subtotal, tarifa_domicilio, total)
     values ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000e1',
             '00000000-0000-0000-0000-000000000011', 10000, 2000, 99999) $$,
  '23514', null, 'el total debe ser subtotal + tarifa de domicilio');

-- ---------------------------------------------------------------------------
-- Pedido C (otro solicitante, con repartidor) para probar la lectura por RLS
-- ---------------------------------------------------------------------------
insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id,
                            estado, subtotal, tarifa_domicilio, total)
values ('00000000-0000-0000-0000-00000000aa03', '00000000-0000-0000-0000-0000000000a2',
        '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000e1',
        '00000000-0000-0000-0000-000000000011', 'Asignado', 22000, 2000, 24000);
insert into public.items_pedido (pedido_id, producto_id, cantidad, precio_unitario)
values ('00000000-0000-0000-0000-00000000aa03', '00000000-0000-0000-0000-0000000000f1', 1, 22000);

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.pedidos), 2,
  'el solicitante ve solo sus pedidos');
select is((select count(*)::int from public.items_pedido), 0,
  'el solicitante no ve ítems de pedidos ajenos');
select throws_ok(
  $$ update public.pedidos set estado = 'Cancelado' where id = '00000000-0000-0000-0000-00000000aa02' $$,
  '42501', null, 'el cliente no puede modificar pedidos directamente');
select throws_ok(
  $$ insert into public.pedidos (solicitante_id, comercio_id, punto_entrega_id, subtotal, total)
     values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e1',
             '00000000-0000-0000-0000-000000000011', 1, 1) $$,
  '42501', null, 'el cliente no puede insertar pedidos directamente (solo con crear_pedido)');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select is((select count(*)::int from public.pedidos), 2,
  'el repartidor ve los pedidos que tiene asignados (A y C)');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select is((select count(*)::int from public.pedidos), 3,
  'el administrador del comercio ve los pedidos de su comercio');
select is((select count(*)::int from public.items_pedido), 1,
  'el administrador del comercio ve los ítems de esos pedidos');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000c3');
select is((select count(*)::int from public.pedidos), 0,
  'el administrador de otro comercio no ve esos pedidos');

select * from finish();
rollback;
