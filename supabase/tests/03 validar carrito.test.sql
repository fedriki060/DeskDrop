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

select plan(32);

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
select has_function('public', 'validar_carrito', array['jsonb'], 'existe public.validar_carrito(jsonb)');
select function_privs_are('public', 'validar_carrito', array['jsonb'], 'anon', array[]::text[],
  'anon no puede ejecutar validar_carrito');
select function_privs_are('public', 'validar_carrito', array['jsonb'], 'authenticated', array['EXECUTE'],
  'authenticated puede ejecutar validar_carrito');
select function_privs_are('public', '_evaluar_carrito', array['jsonb', 'boolean'], 'authenticated', array[]::text[],
  'el núcleo _evaluar_carrito no es invocable desde la API');
select function_privs_are('public', 'tarifa_domicilio_piloto', array[]::name[], 'authenticated', array[]::text[],
  'tarifa_domicilio_piloto no es invocable desde la API');

reset role; select pg_temp.como_anon();
select throws_ok($$ select public.validar_carrito('[]') $$, '42501', null,
  'anon recibe permission denied al validar un carrito');

reset role; select pg_temp.como(null);
select throws_like($$ select public.validar_carrito('[]') $$, 'NO_AUTENTICADO%',
  'sin sesión no se puede validar un carrito');

-- ---------------------------------------------------------------------------
-- Carrito válido (como solicitante)
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a1');

-- 2 x Hamburguesa (22.000) + 1 x Papas (3.000), ambos del comercio e1
select is(
  (public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":2},
                            {"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') ->> 'valido')::boolean,
  true, 'carrito válido de un comercio con inventario suficiente');

select is(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":2},
                           {"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') ->> 'comercio_id',
  '00000000-0000-0000-0000-0000000000e1', 'devuelve el comercio del carrito');

select is(
  (public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":2},
                            {"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') ->> 'subtotal')::numeric,
  47000::numeric, 'subtotal = suma de precio x cantidad con precios de la base');

select is(
  (public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":2},
                            {"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') ->> 'total')::numeric,
  49000::numeric, 'total = subtotal + tarifa de domicilio de $2.000');

select is(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000F1","cantidad":1}]') ->> 'valido',
  'true', 'acepta el UUID en mayúsculas');

-- ---------------------------------------------------------------------------
-- Inventario
-- ---------------------------------------------------------------------------
select is(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":6}]') #>> '{errores,0,codigo}',
  'INVENTARIO_INSUFICIENTE', 'rechaza cantidad mayor al inventario');

select is(
  (public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":6}]') #>> '{errores,0,disponible}')::int,
  5, 'informa las unidades disponibles');

select is(
  (public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f3","cantidad":1}]') #>> '{errores,0,disponible}')::int,
  0, 'un producto agotado no se puede pedir');

select is(
  (public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":3},
                            {"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":3}]') #>> '{errores,0,solicitado}')::int,
  6, 'suma las líneas repetidas del mismo producto antes de comparar con el inventario');

select is(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":5}]') ->> 'valido',
  'true', 'pedir exactamente el inventario disponible es válido');

select is(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":6}]') -> 'total',
  'null'::jsonb, 'un carrito inválido no devuelve totales');

-- ---------------------------------------------------------------------------
-- Un solo comercio
-- ---------------------------------------------------------------------------
select ok(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1},
                           {"producto_id":"00000000-0000-0000-0000-0000000000f5","cantidad":1}]') -> 'errores'
    @> '[{"codigo":"COMERCIOS_DISTINTOS"}]'::jsonb,
  'rechaza productos de dos comercios distintos');

-- ---------------------------------------------------------------------------
-- Vigencia: inexistente, inactivo o de comercio inactivo
-- ---------------------------------------------------------------------------
select is(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f2","cantidad":1}]') #>> '{errores,0,codigo}',
  'PRODUCTO_NO_DISPONIBLE', 'rechaza un producto inactivo');
select is(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f4","cantidad":1}]') #>> '{errores,0,codigo}',
  'PRODUCTO_NO_DISPONIBLE', 'rechaza un producto de un comercio inactivo');
select is(
  public.validar_carrito('[{"producto_id":"11111111-2222-3333-4444-555555555555","cantidad":1}]') #>> '{errores,0,codigo}',
  'PRODUCTO_NO_DISPONIBLE', 'rechaza un producto que no existe');

-- ---------------------------------------------------------------------------
-- Forma de la entrada
-- ---------------------------------------------------------------------------
select is(public.validar_carrito('[]') #>> '{errores,0,codigo}',
  'CARRITO_VACIO', 'rechaza un carrito vacío');
select is(public.validar_carrito(null) #>> '{errores,0,codigo}',
  'CARRITO_VACIO', 'rechaza un carrito nulo');
select is(public.validar_carrito('{"producto_id":"x"}') #>> '{errores,0,codigo}',
  'FORMATO_INVALIDO', 'rechaza algo que no es un arreglo');
select is(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":0}]') #>> '{errores,0,codigo}',
  'ITEM_INVALIDO', 'rechaza cantidad 0');
select is(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":-2}]') #>> '{errores,0,codigo}',
  'ITEM_INVALIDO', 'rechaza cantidad negativa');
select is(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1.5}]') #>> '{errores,0,codigo}',
  'ITEM_INVALIDO', 'rechaza cantidad decimal');
select is(
  public.validar_carrito('[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":"2"}]') #>> '{errores,0,codigo}',
  'ITEM_INVALIDO', 'rechaza cantidad como texto');
select is(
  public.validar_carrito('[{"producto_id":"no-es-un-uuid","cantidad":1}]') #>> '{errores,0,codigo}',
  'ITEM_INVALIDO', 'rechaza un producto_id que no es UUID');
select is(
  public.validar_carrito((select jsonb_agg(jsonb_build_object(
    'producto_id', '00000000-0000-0000-0000-0000000000f1', 'cantidad', 1)) from generate_series(1, 51))
  ) #>> '{errores,0,codigo}',
  'CARRITO_DEMASIADO_GRANDE', 'rechaza más de 50 líneas');

-- ---------------------------------------------------------------------------
-- Es solo lectura
-- ---------------------------------------------------------------------------
reset role;
select is(
  (select inventario_disponible from public.productos where id = '00000000-0000-0000-0000-0000000000f1'),
  5, 'validar_carrito no descuenta inventario');

select * from finish();
rollback;
