-- Pruebas de T-101 y T-095: teléfono editable y contacto del domiciliario.
begin;
create extension if not exists pgtap with schema extensions;

-- a1, a2 solicitantes; b1 domiciliario; c1 dueño del comercio.
-- Pedidos: ca01 (a1, b1, En Camino), ca02 (a1, b1, Entregado)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Ana Gómez',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Beto Ruiz',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Carlos Pérez', 'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1', 'comercio')
on conflict (id) do update set nombre_completo = excluded.nombre_completo, rol = excluded.rol;

insert into public.aceptaciones_repartidor (usuario_id, version) values
  ('00000000-0000-0000-0000-0000000000b1', 'test');

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);
insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);
insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000);

create function pg_temp.como(p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $f$;

select plan(11);

-- Edición del teléfono: cada usuario solo el suyo, con formato de celular colombiano
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
update public.perfiles set telefono = '3001234567' where id = '00000000-0000-0000-0000-0000000000b1';
select is((select telefono from public.perfiles where id = '00000000-0000-0000-0000-0000000000b1'),
  '3001234567', 'el usuario guarda su teléfono');
select throws_ok($$ update public.perfiles set telefono = '12345' where id = '00000000-0000-0000-0000-0000000000b1' $$,
  '23514', null, 'un teléfono con formato inválido se rechaza');
select throws_ok($$ update public.perfiles set telefono = '600123456' where id = '00000000-0000-0000-0000-0000000000b1' $$,
  '23514', null, 'un número que no empieza por 3 se rechaza');
update public.perfiles set telefono = '3109998877' where id = '00000000-0000-0000-0000-0000000000a1';
select is((select count(*)::int from public.perfiles where id = '00000000-0000-0000-0000-0000000000a1'),
  0, 'no puede ver ni editar el perfil de otro usuario');
select is((select repartidor_telefono from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01']::uuid[])),
  null, 'el propio domiciliario no recibe teléfono en datos_partes_pedido');
reset role;

-- Solicitante dueño: ve el contacto mientras el pedido está en camino
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select repartidor_telefono from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01']::uuid[])),
  '3001234567', 'el solicitante ve el teléfono del domiciliario con el pedido En Camino');
select ok((select repartidor_calificacion is not null from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01']::uuid[])),
  'el solicitante recibe la calificación del domiciliario');
reset role;

-- El comercio no recibe el teléfono
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select is((select repartidor_telefono from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01']::uuid[])),
  null, 'el comercio no recibe el teléfono del domiciliario');
reset role;

-- Otro solicitante no recibe nada del pedido
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select is((select count(*)::int from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01']::uuid[])),
  0, 'otro solicitante no obtiene datos del pedido');
reset role;

-- Entregado: el contacto ya no se expone
update public.pedidos set estado = 'Entregado' where id = '00000000-0000-0000-0000-00000000ca01';
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select repartidor_telefono from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01']::uuid[])),
  null, 'con el pedido Entregado el teléfono deja de exponerse');
select is((select repartidor from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca01']::uuid[])),
  'Carlos', 'el nombre del domiciliario se sigue viendo');
reset role;

select * from finish();
rollback;
