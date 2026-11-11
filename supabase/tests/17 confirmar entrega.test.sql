-- Pruebas de HU-20: código de 4 dígitos y confirmar_entrega (T-091).
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1, a2, a3, a5 solicitantes, b1 y b2 repartidores habilitados, c1 admin de comercio,
--      d1 zona, e1 comercio, 11 punto del campus.
-- Pedidos (todos de 1.000 + 2.000 = 3.000):
--   ac01 a1 En Camino (b1)  -> caso feliz
--   ac02 a2 Asignado  (b1)  -> todavía no se puede confirmar
--   ac03 a3 Creado          -> sin domiciliario
--   ac05 a5 En Camino (b1)  -> bloqueo por intentos fallidos
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b2', 'rep2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co', 'Solicitante Tres',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co', 'Solicitante Cinco',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',     'repartidor'),
  ('00000000-0000-0000-0000-0000000000b2', 'rep2@eia.edu.co', 'Repartidor Dos',     'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1',   'comercio')
on conflict (id) do update set rol = excluded.rol;

-- Los repartidores de prueba ya aceptaron la declaración de +18 (HU-19).
insert into public.aceptaciones_repartidor (usuario_id, version) values
  ('00000000-0000-0000-0000-0000000000b1', 'test'),
  ('00000000-0000-0000-0000-0000000000b2', 'test');

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);

insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);

insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000ac01', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ac02', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Asignado',  1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ac03', '00000000-0000-0000-0000-0000000000a3', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',    1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ac05', '00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000);

create function pg_temp.estado(p_id uuid) returns text language sql security definer as $f$
  select estado::text from public.pedidos where id = p_id
$f$;

create function pg_temp.codigo(p_id uuid) returns text language sql security definer as $f$
  select codigo from public.codigos_entrega where pedido_id = p_id
$f$;

create function pg_temp.intentos(p_id uuid) returns integer language sql security definer as $f$
  select intentos_fallidos::int from public.codigos_entrega where pedido_id = p_id
$f$;

-- Un código de 4 dígitos que seguro no es el del pedido
create function pg_temp.codigo_malo(p_id uuid) returns text language sql security definer as $f$
  select lpad(((codigo::int + 1) % 10000)::text, 4, '0') from public.codigos_entrega where pedido_id = p_id
$f$;

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

select plan(31);

-- ---------------------------------------------------------------------------
-- Estructura y permisos
-- ---------------------------------------------------------------------------
select has_table('public', 'codigos_entrega', 'existe codigos_entrega');
select has_function('public', 'confirmar_entrega', array['uuid', 'text'], 'existe confirmar_entrega(uuid, text)');
select is_definer('public', 'confirmar_entrega', array['uuid', 'text'], 'confirmar_entrega es SECURITY DEFINER');
select ok(has_function_privilege('authenticated', 'public.confirmar_entrega(uuid, text)', 'execute'),
  'authenticated puede ejecutar confirmar_entrega');
select ok(not has_function_privilege('anon', 'public.confirmar_entrega(uuid, text)', 'execute'),
  'anon no puede ejecutar confirmar_entrega');
select hasnt_function('public', 'confirmar_recepcion', array['uuid'],
  'confirmar_recepcion ya no existe (la entrega se confirma con el código)');
select table_privs_are('public', 'codigos_entrega', 'authenticated', array['SELECT'],
  'authenticated solo puede leer codigos_entrega');

-- ---------------------------------------------------------------------------
-- Cada pedido nace con su código
-- ---------------------------------------------------------------------------
select matches(pg_temp.codigo('00000000-0000-0000-0000-00000000ac01'), '^[0-9]{4}$',
  'el pedido tiene un código de 4 dígitos');
select is((select count(*)::int from public.codigos_entrega), 4, 'hay un código por pedido');

-- ---------------------------------------------------------------------------
-- Quién ve el código: solo el solicitante dueño
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select codigo from public.codigos_entrega), pg_temp.codigo('00000000-0000-0000-0000-00000000ac01'),
  'el solicitante ve el código de su pedido (y solo ese)');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select is((select count(*)::int from public.codigos_entrega), 0, 'el domiciliario no puede leer los códigos');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select is((select count(*)::int from public.codigos_entrega), 0, 'el comercio no puede leer los códigos');
reset role;

-- ---------------------------------------------------------------------------
-- Quién puede confirmar la entrega
-- ---------------------------------------------------------------------------
select pg_temp.como_anon();
select throws_ok($$ select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac01', '1234') $$,
  '42501', null, 'un usuario sin sesión no puede confirmar');
reset role;

select set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
set local role authenticated;
select throws_ok($$ select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac01', '1234') $$,
  '28000', 'NO_AUTENTICADO: Debes iniciar sesión.', 'sin usuario en la sesión responde NO_AUTENTICADO');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$ select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac01', '1234') $$,
  '42501', null, 'el solicitante no habilitado no puede confirmar su propio pedido');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select throws_ok($$ select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac01', '1234') $$,
  '42501', null, 'el comercio no puede confirmar entregas');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select throws_ok($$ select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac01', '1234') $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no lo tienes asignado.',
  'otro domiciliario no puede confirmar un pedido ajeno');
reset role;

-- ---------------------------------------------------------------------------
-- Código mal escrito, equivocado y correcto
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac01', 'abcd') $$,
  '22023', 'CODIGO_INVALIDO: El código son 4 dígitos.', 'un código con letras se rechaza');
select throws_ok($$ select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac01', '123') $$,
  '22023', 'CODIGO_INVALIDO: El código son 4 dígitos.', 'un código de 3 dígitos se rechaza');

select is(
  (public.confirmar_entrega('00000000-0000-0000-0000-00000000ac01',
     pg_temp.codigo_malo('00000000-0000-0000-0000-00000000ac01')) ->> 'intentos_restantes')::int,
  4, 'un código equivocado responde ok=false y los intentos que quedan');
reset role;
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ac01'), 'En Camino', 'el código equivocado no cambia el pedido');
select is(pg_temp.intentos('00000000-0000-0000-0000-00000000ac01'), 1, 'el intento fallido queda contado');

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select is(
  public.confirmar_entrega('00000000-0000-0000-0000-00000000ac01',
     pg_temp.codigo('00000000-0000-0000-0000-00000000ac01')) ->> 'estado',
  'Entregado', 'con el código correcto el domiciliario confirma la entrega');
reset role;
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ac01'), 'Entregado', 'el pedido queda Entregado');

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_ok(
  $$ select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac01', '0000') $$,
  '55000', 'ESTADO_NO_PERMITIDO: Solo puedes confirmar la entrega de un pedido En Camino (estado actual: Entregado).',
  'confirmar dos veces responde ESTADO_NO_PERMITIDO');
select lives_ok($$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000ac01') $$,
  'tras la entrega el domiciliario puede registrar el cobro');

-- ---------------------------------------------------------------------------
-- Estados desde los que no se puede confirmar
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac02', '0000') $$,
  '55000', 'ESTADO_NO_PERMITIDO: Solo puedes confirmar la entrega de un pedido En Camino (estado actual: Asignado).',
  'no se confirma un pedido Asignado');
select throws_ok(
  $$ select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac03', '0000') $$,
  'P0002', 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no lo tienes asignado.',
  'no se confirma un pedido sin domiciliario');
reset role;

-- ---------------------------------------------------------------------------
-- Bloqueo tras 5 intentos fallidos
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac05', pg_temp.codigo_malo('00000000-0000-0000-0000-00000000ac05'));
select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac05', pg_temp.codigo_malo('00000000-0000-0000-0000-00000000ac05'));
select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac05', pg_temp.codigo_malo('00000000-0000-0000-0000-00000000ac05'));
select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac05', pg_temp.codigo_malo('00000000-0000-0000-0000-00000000ac05'));
select is(
  (public.confirmar_entrega('00000000-0000-0000-0000-00000000ac05',
     pg_temp.codigo_malo('00000000-0000-0000-0000-00000000ac05')) ->> 'intentos_restantes')::int,
  0, 'el quinto intento fallido deja 0 intentos');
select throws_ok(
  $$ select public.confirmar_entrega('00000000-0000-0000-0000-00000000ac05', '0000') $$,
  '55000', 'CODIGO_BLOQUEADO: Se agotaron los intentos. El pedido se confirmará solo en unos minutos.',
  'agotados los intentos el código se bloquea');
reset role;
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ac05'), 'En Camino', 'el pedido bloqueado sigue En Camino');

select * from finish();
rollback;
