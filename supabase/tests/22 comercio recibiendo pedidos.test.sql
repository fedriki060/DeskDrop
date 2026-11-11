-- Pruebas de HU-23: el comercio abre y cierra su tienda (comercios.activo) (T-098).
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1 solicitante, c1 y c2 admins de comercio, d1 zona, e1 y e2 comercios, f1 producto, 11 punto.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'com2@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno', 'solicitante'),
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

create function pg_temp.como(p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $f$;

select plan(10);

-- El dueño cierra su comercio: deja de verse en el catálogo y no recibe pedidos
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select lives_ok($$ update public.comercios set activo = false where id = '00000000-0000-0000-0000-0000000000e1' $$,
  'el dueño cierra su comercio');
select is((select activo from public.comercios where id = '00000000-0000-0000-0000-0000000000e1'), false,
  'el dueño sigue viendo su comercio cerrado');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.comercios where id = '00000000-0000-0000-0000-0000000000e1'), 0,
  'el solicitante ya no ve el comercio cerrado');
select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]') $$,
  'CARRITO_INVALIDO%', 'no se pueden crear pedidos en un comercio cerrado');
-- Un solicitante no puede reabrirlo
select lives_ok($$ update public.comercios set activo = true where id = '00000000-0000-0000-0000-0000000000e1' $$,
  'el intento de un solicitante no falla pero no afecta filas');
reset role;

-- Otro comercio tampoco
select pg_temp.como('00000000-0000-0000-0000-0000000000c2');
select lives_ok($$ update public.comercios set activo = true where id = '00000000-0000-0000-0000-0000000000e1' $$,
  'el intento del administrador de otro comercio no falla pero no afecta filas');
reset role;

select is((select activo from public.comercios where id = '00000000-0000-0000-0000-0000000000e1'), false,
  'el comercio sigue cerrado: solo su dueño lo abre');

-- El dueño lo reabre y vuelve a recibir pedidos
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select lives_ok($$ update public.comercios set activo = true where id = '00000000-0000-0000-0000-0000000000e1' $$,
  'el dueño reabre su comercio');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.comercios where id = '00000000-0000-0000-0000-0000000000e1'), 1,
  'el solicitante vuelve a ver el comercio abierto');
select lives_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]') $$,
  'con el comercio abierto se crea el pedido');
reset role;

select * from finish();
rollback;
