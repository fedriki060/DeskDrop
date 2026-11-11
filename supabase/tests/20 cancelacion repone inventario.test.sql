-- Pruebas de la reposición de inventario al cancelar un pedido.
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1 y a2 solicitantes, c1 comercio, d1 zona, e1 comercio, f1 f2 productos, 11 punto.
-- Los pedidos ac01..ac03 se crean ya con su inventario descontado (f1: 10 -> 7, f2: 5 -> 4):
--   ac01 Creado: 2 x f1 + 1 x f2     ac02 Asignado: 1 x f1     ac03 En Camino: 1 x f1
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co', 'Solicitante Tres',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co', 'Solicitante Cuatro', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co', 'Solicitante Cinco', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',     'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1',   'comercio')
on conflict (id) do update set rol = excluded.rol;

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);
insert into public.productos (id, comercio_id, nombre, precio, inventario_disponible, activo) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', 'Hamburguesa', 1000, 3, true),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e1', 'Papas',       1000, 4, true);
insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);
insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000ac01', '00000000-0000-0000-0000-0000000000a1', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',    3000, 2000, 5000),
  ('00000000-0000-0000-0000-00000000ac02', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Asignado',  1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ac03', '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000);
insert into public.items_pedido (pedido_id, producto_id, cantidad, precio_unitario) values
  ('00000000-0000-0000-0000-00000000ac01', '00000000-0000-0000-0000-0000000000f1', 2, 1000),
  ('00000000-0000-0000-0000-00000000ac01', '00000000-0000-0000-0000-0000000000f2', 1, 1000),
  ('00000000-0000-0000-0000-00000000ac02', '00000000-0000-0000-0000-0000000000f1', 1, 1000),
  ('00000000-0000-0000-0000-00000000ac03', '00000000-0000-0000-0000-0000000000f1', 1, 1000);

create function pg_temp.inv(p_id uuid) returns int language sql security definer as $f$
  select inventario_disponible from public.productos where id = p_id
$f$;
create function pg_temp.como(p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $f$;

select plan(14);

select has_trigger('public', 'pedidos', 'trg_pedidos_reponer_inventario', 'existe el trigger de reposición');

-- Cancelar un pedido Creado repone todos sus ítems
update public.pedidos set estado = 'Cancelado' where id = '00000000-0000-0000-0000-00000000ac01';
select is(pg_temp.inv('00000000-0000-0000-0000-0000000000f1'), 5, 'cancelar un Creado repone 2 x f1 (3 -> 5)');
select is(pg_temp.inv('00000000-0000-0000-0000-0000000000f2'), 5, 'y 1 x f2 (4 -> 5)');

-- Cancelar de nuevo / actualizaciones posteriores no reponen otra vez
update public.pedidos set estado = 'Cancelado' where id = '00000000-0000-0000-0000-00000000ac01';
update public.pedidos set notas_entrega = 'x' where id = '00000000-0000-0000-0000-00000000ac01';
select is(pg_temp.inv('00000000-0000-0000-0000-0000000000f1'), 5, 'no se repone dos veces el mismo pedido');

-- Cancelar un Asignado también repone
update public.pedidos set estado = 'Cancelado' where id = '00000000-0000-0000-0000-00000000ac02';
select is(pg_temp.inv('00000000-0000-0000-0000-0000000000f1'), 6, 'cancelar un Asignado repone su unidad');

-- Un pedido En Camino no se puede cancelar y el inventario no se toca
select throws_ok(
  $$ update public.pedidos set estado = 'Cancelado' where id = '00000000-0000-0000-0000-00000000ac03' $$,
  '23514', null, 'un pedido En Camino no se cancela');
select is(pg_temp.inv('00000000-0000-0000-0000-0000000000f1'), 6, 'y su inventario sigue descontado');

-- Misma transacción: la reposición se deshace con la cancelación (savepoint = transacción interna)
insert into public.pedidos (id, solicitante_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000ac05', '00000000-0000-0000-0000-0000000000a5',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado', 1000, 2000, 3000);
insert into public.items_pedido (pedido_id, producto_id, cantidad, precio_unitario) values
  ('00000000-0000-0000-0000-00000000ac05', '00000000-0000-0000-0000-0000000000f2', 1, 1000);
savepoint antes;
update public.pedidos set estado = 'Cancelado' where id = '00000000-0000-0000-0000-00000000ac05';
select is(pg_temp.inv('00000000-0000-0000-0000-0000000000f2'), 6, 'dentro de la transacción la cancelación ya repuso (5 -> 6)');
rollback to savepoint antes;
select is(pg_temp.inv('00000000-0000-0000-0000-0000000000f2'), 5, 'al revertir la cancelación se revierte también la reposición');

-- Auto-cancelación (pg_cron) también repone: pedido vencido
insert into public.pedidos (id, solicitante_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total, creado_en) values
  ('00000000-0000-0000-0000-00000000ac04', '00000000-0000-0000-0000-0000000000a4',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado', 1000, 2000, 3000,
   now() - interval '30 minutes');
insert into public.items_pedido (pedido_id, producto_id, cantidad, precio_unitario) values
  ('00000000-0000-0000-0000-00000000ac04', '00000000-0000-0000-0000-0000000000f2', 2, 1000);
select is(public.cancelar_pedidos_vencidos(), 1, 'la auto-cancelación cancela el pedido vencido');
select is(pg_temp.inv('00000000-0000-0000-0000-0000000000f2'), 7, 'y repone sus 2 x f2 (5 -> 7)');

-- De punta a punta: crear_pedido descuenta, cancelar repone
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":3}]'::jsonb) $$,
  'el solicitante crea un pedido con 3 x f1');
reset role;
select is(pg_temp.inv('00000000-0000-0000-0000-0000000000f1'), 3, 'crear_pedido descontó 3 unidades (6 -> 3)');
update public.pedidos set estado = 'Cancelado'
where solicitante_id = '00000000-0000-0000-0000-0000000000a1' and estado = 'Creado';
select is(pg_temp.inv('00000000-0000-0000-0000-0000000000f1'), 6, 'cancelar ese pedido devuelve las 3 unidades (3 -> 6)');

select * from finish();
rollback;
