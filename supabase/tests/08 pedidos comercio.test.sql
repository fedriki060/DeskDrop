-- Pruebas de pedidos del comercio: RLS por rol y marcar "Listo para recoger".
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1-a3 solicitantes, b1 repartidor, c1-c2 admins de comercio, d1 zona, e1-e2 comercios,
--      f1 producto de e1, 11 punto de entrega.
-- Pedidos: aa01 (a1, e1, Creado), aa02 (a2, e1, Asignado a b1), aa03 (a3, e2, Creado),
--          aa04 (a1, e1, Entregado).
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'com2@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co', 'Solicitante Tres', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',   'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1', 'comercio'),
  ('00000000-0000-0000-0000-0000000000c2', 'com2@eia.edu.co', 'Admin Comercio 2', 'comercio')
on conflict (id) do update set rol = excluded.rol;

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c2', 'Papelería Test', true);

insert into public.productos (id, comercio_id, nombre, precio, inventario_disponible, activo) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', 'Hamburguesa', 22000, 5, true);

insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);

insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',    1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Asignado',  1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000aa03', '00000000-0000-0000-0000-0000000000a3', null,
   '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-000000000011', 'Creado',    1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000aa04', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Entregado', 1000, 2000, 3000);

insert into public.items_pedido (pedido_id, producto_id, cantidad, precio_unitario) values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000f1', 2, 22000);

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

select plan(28);

-- ---------------------------------------------------------------------------
-- Funciones y permisos
-- ---------------------------------------------------------------------------
select has_function('public', 'rol_actual', array[]::name[], 'existe public.rol_actual()');
select has_function('public', 'marcar_listo_para_recoger', array['uuid'], 'existe marcar_listo_para_recoger');
select function_privs_are('public', 'marcar_listo_para_recoger', array['uuid'], 'anon', array[]::text[],
  'anon no puede ejecutar marcar_listo_para_recoger');
select function_privs_are('public', 'marcar_listo_para_recoger', array['uuid'], 'authenticated', array['EXECUTE'],
  'authenticated puede ejecutar marcar_listo_para_recoger');

-- ---------------------------------------------------------------------------
-- RLS por rol: quién ve qué
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select is((select public.rol_actual()::text), 'comercio', 'rol_actual() devuelve el rol del usuario');
select is((select count(*)::int from public.pedidos), 3, 'el comercio 1 lista los 3 pedidos de su comercio');
select is((select count(*)::int from public.pedidos where id = '00000000-0000-0000-0000-00000000aa03'), 0,
  'el comercio 1 no ve pedidos de otro comercio');
select is((select count(*)::int from public.items_pedido where pedido_id = '00000000-0000-0000-0000-00000000aa01'), 1,
  'el comercio ve los ítems de sus pedidos');
select throws_ok(
  $$ update public.pedidos set listo_para_recoger = true where id = '00000000-0000-0000-0000-00000000aa01' $$,
  '42501', null, 'el comercio no modifica pedidos directamente');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000c2');
select is((select count(*)::int from public.pedidos), 1, 'el comercio 2 solo ve su pedido');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.pedidos), 2, 'el solicitante 1 ve solo sus 2 pedidos');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select is((select count(*)::int from public.pedidos), 1, 'el solicitante 2 ve solo su pedido');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select is((select count(*)::int from public.pedidos), 2, 'el repartidor ve solo los pedidos que tiene asignados');

reset role; select pg_temp.como_anon();
select throws_ok($$ select count(*) from public.pedidos $$, '42501', null, 'anon no lee pedidos');

-- ---------------------------------------------------------------------------
-- marcar_listo_para_recoger: quién puede
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como_anon();
select throws_ok(
  $$ select public.marcar_listo_para_recoger('00000000-0000-0000-0000-00000000aa01') $$,
  '42501', null, 'anon recibe permission denied');

reset role; select pg_temp.como(null);
select throws_ok(
  $$ select public.marcar_listo_para_recoger('00000000-0000-0000-0000-00000000aa01') $$,
  '28000', null, 'sin sesión no se marca nada');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_like(
  $$ select public.marcar_listo_para_recoger('00000000-0000-0000-0000-00000000aa01') $$,
  'ROL_NO_PERMITIDO%', 'un solicitante no puede marcar pedidos como listos');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_like(
  $$ select public.marcar_listo_para_recoger('00000000-0000-0000-0000-00000000aa02') $$,
  'ROL_NO_PERMITIDO%', 'un repartidor no puede marcar pedidos como listos');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000c2');
select throws_like(
  $$ select public.marcar_listo_para_recoger('00000000-0000-0000-0000-00000000aa01') $$,
  'PEDIDO_NO_ENCONTRADO%', 'el comercio 2 no puede marcar un pedido del comercio 1');

-- ---------------------------------------------------------------------------
-- marcar_listo_para_recoger: camino feliz y estados
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select lives_ok(
  $$ select set_config('test.r', public.marcar_listo_para_recoger('00000000-0000-0000-0000-00000000aa01')::text, true) $$,
  'el comercio marca su pedido Creado como listo');
select is((current_setting('test.r')::jsonb ->> 'listo_para_recoger')::boolean, true, 'la respuesta indica listo');

reset role;
select is((select listo_para_recoger from public.pedidos where id = '00000000-0000-0000-0000-00000000aa01'), true,
  'el pedido queda marcado como listo');
select is((select estado::text from public.pedidos where id = '00000000-0000-0000-0000-00000000aa01'), 'Creado',
  'marcarlo listo no cambia el estado');

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select lives_ok(
  $$ select public.marcar_listo_para_recoger('00000000-0000-0000-0000-00000000aa01') $$,
  'marcarlo dos veces no falla (idempotente)');
select lives_ok(
  $$ select public.marcar_listo_para_recoger('00000000-0000-0000-0000-00000000aa02') $$,
  'también puede marcar un pedido Asignado');
select throws_like(
  $$ select public.marcar_listo_para_recoger('00000000-0000-0000-0000-00000000aa04') $$,
  'ESTADO_NO_PERMITIDO%', 'no puede marcar un pedido ya Entregado');
select throws_like(
  $$ select public.marcar_listo_para_recoger('99999999-9999-9999-9999-999999999999') $$,
  'PEDIDO_NO_ENCONTRADO%', 'un pedido inexistente se reporta como no encontrado');

reset role;
select is(
  (select count(*)::int from public.pedidos
   where listo_para_recoger is true and id in ('00000000-0000-0000-0000-00000000aa03', '00000000-0000-0000-0000-00000000aa04')),
  0, 'los pedidos ajenos o rechazados no quedaron marcados');

select * from finish();
rollback;
