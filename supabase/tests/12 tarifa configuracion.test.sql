-- Pruebas de la tabla de configuración y del total con la tarifa leída de ella (T-014).
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1-a2 solicitantes, c1 admin de comercio, d1 zona, e1 comercio, f6 producto (3.000 x 10 uds), 11 punto del campus.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos', 'solicitante'),
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

create function pg_temp.como(p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $f$;

select plan(16);

-- ---------------------------------------------------------------------------
-- Tabla y valor oficial (T-014)
-- ---------------------------------------------------------------------------
select has_table('public', 'configuracion', 'existe public.configuracion');
select table_privs_are('public', 'configuracion', 'authenticated', array[]::text[],
  'authenticated no accede directo a configuracion');
select is((select valor from public.configuracion where clave = 'tarifa_domicilio'), 2000.00::numeric,
  'la tarifa configurada es $2.000 COP (T-014)');
select is(public.tarifa_domicilio_piloto(), 2000.00::numeric, 'tarifa_domicilio_piloto() lee la tabla');
select function_privs_are('public', 'tarifa_domicilio_piloto', array[]::name[], 'authenticated', array[]::text[],
  'tarifa_domicilio_piloto sigue sin ser invocable desde la API');
select throws_ok(
  $$ update public.configuracion set valor = -1 where clave = 'tarifa_domicilio' $$,
  '23514', null, 'la tarifa no puede ser negativa');

-- ---------------------------------------------------------------------------
-- El total usa la tarifa de la tabla
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is(
  (public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":2}]') ->> 'total')::numeric,
  8000::numeric, 'con la tarifa de $2.000: 6.000 + 2.000 = 8.000');

reset role;
update public.configuracion set valor = 2500 where clave = 'tarifa_domicilio';
select is(public.tarifa_domicilio_piloto(), 2500.00::numeric, 'cambiar la tabla cambia la tarifa vigente');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select set_config('test.pedido', public.crear_pedido(
       '00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":2}]')::text, true) $$,
  'crear_pedido funciona con la tarifa nueva');
select is((current_setting('test.pedido')::jsonb ->> 'tarifa_domicilio')::numeric, 2500::numeric,
  'la respuesta trae la tarifa de la tabla');
select is((current_setting('test.pedido')::jsonb ->> 'total')::numeric, 8500::numeric,
  'el total es subtotal 6.000 + tarifa 2.500');

reset role;
select is(
  (select count(*)::int from public.pedidos
   where id = (current_setting('test.pedido')::jsonb ->> 'pedido_id')::uuid
     and subtotal = 6000 and tarifa_domicilio = 2500 and total = 8500),
  1, 'el pedido guarda la tarifa y el total calculados');

update public.configuracion set valor = 2000 where clave = 'tarifa_domicilio';
select is(
  (select tarifa_domicilio from public.pedidos
   where id = (current_setting('test.pedido')::jsonb ->> 'pedido_id')::uuid),
  2500::numeric, 'cambiar la tarifa después no altera pedidos ya creados');

-- ---------------------------------------------------------------------------
-- Falla cerrado si falta la tarifa
-- ---------------------------------------------------------------------------
delete from public.configuracion where clave = 'tarifa_domicilio';
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'CONFIG_FALTANTE%', 'sin tarifa configurada no se crean pedidos');

reset role;
select is(
  (select count(*)::int from public.pedidos where solicitante_id = '00000000-0000-0000-0000-0000000000a2'),
  0, 'el rechazo por falta de tarifa no creó pedido');
select is(
  (select inventario_disponible from public.productos where id = '00000000-0000-0000-0000-0000000000f6'),
  8, 'el rechazo por falta de tarifa no descontó inventario (solo los 2 del pedido válido)');

select * from finish();
rollback;
