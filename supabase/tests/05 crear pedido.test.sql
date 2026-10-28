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

select plan(33);

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
select has_function('public', 'crear_pedido', array['uuid', 'jsonb', 'text'], 'existe public.crear_pedido');
select function_privs_are('public', 'crear_pedido', array['uuid', 'jsonb', 'text'], 'anon', array[]::text[],
  'anon no puede ejecutar crear_pedido');
select function_privs_are('public', 'crear_pedido', array['uuid', 'jsonb', 'text'], 'authenticated', array['EXECUTE'],
  'authenticated puede ejecutar crear_pedido');

reset role; select pg_temp.como_anon();
select throws_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]') $$,
  '42501', null, 'anon recibe permission denied');

reset role; select pg_temp.como(null);
select throws_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]') $$,
  '28000', null, 'sin sesión no se crea el pedido');

-- ---------------------------------------------------------------------------
-- Solo un solicitante crea pedidos
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]') $$,
  'ROL_NO_PERMITIDO%', 'un repartidor no puede crear pedidos');

reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]') $$,
  'ROL_NO_PERMITIDO%', 'un administrador de comercio no puede crear pedidos');

-- ---------------------------------------------------------------------------
-- Camino feliz (solicitante 1): 2 x Hamburguesa + 1 x Papas, con notas con espacios
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select set_config('test.pedido', public.crear_pedido(
       '00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":2},
         {"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]',
       '  Mesa 4  ')::text, true) $$,
  'crear_pedido crea el pedido');

select is(current_setting('test.pedido')::jsonb ->> 'estado', 'Creado', 'la respuesta indica estado Creado');
select is((current_setting('test.pedido')::jsonb ->> 'total')::numeric, 49000::numeric,
  'la respuesta trae el total (47.000 + 2.000 de domicilio)');

reset role;
select is(
  (select count(*)::int from public.pedidos
   where id = (current_setting('test.pedido')::jsonb ->> 'pedido_id')::uuid
     and solicitante_id = '00000000-0000-0000-0000-0000000000a1'
     and comercio_id = '00000000-0000-0000-0000-0000000000e1'
     and punto_entrega_id = '00000000-0000-0000-0000-000000000011'
     and estado = 'Creado'
     and subtotal = 47000 and tarifa_domicilio = 2000 and total = 49000),
  1, 'el pedido queda guardado con ID único, solicitante, comercio, punto y totales correctos');

select is(
  (select notas_entrega from public.pedidos
   where id = (current_setting('test.pedido')::jsonb ->> 'pedido_id')::uuid),
  'Mesa 4', 'las notas se guardan sin espacios sobrantes');

select results_eq(
  $$ select producto_id, cantidad, precio_unitario from public.items_pedido
     where pedido_id = (current_setting('test.pedido')::jsonb ->> 'pedido_id')::uuid
     order by producto_id $$,
  $$ values ('00000000-0000-0000-0000-0000000000f1'::uuid, 2, 22000.00::numeric),
            ('00000000-0000-0000-0000-0000000000f6'::uuid, 1,  3000.00::numeric) $$,
  'los ítems guardan cantidad y el precio unitario vigente');

select results_eq(
  $$ select id, inventario_disponible from public.productos
     where id in ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f3',
                  '00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000f6')
     order by id $$,
  $$ values ('00000000-0000-0000-0000-0000000000f1'::uuid, 3),
            ('00000000-0000-0000-0000-0000000000f3'::uuid, 0),
            ('00000000-0000-0000-0000-0000000000f5'::uuid, 10),
            ('00000000-0000-0000-0000-0000000000f6'::uuid, 9) $$,
  'descuenta el inventario solo de los productos pedidos');

-- ---------------------------------------------------------------------------
-- Un solo pedido activo por usuario (RN-001 según docs/ADR 001)
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1}]') $$,
  '23505', 'PEDIDO_ACTIVO_EXISTENTE: Ya tienes un pedido en curso.',
  'no permite un segundo pedido mientras hay uno activo');

reset role;
select is(
  (select inventario_disponible from public.productos where id = '00000000-0000-0000-0000-0000000000f1'),
  3, 'el pedido rechazado no descontó inventario');

-- Al cancelarse el primero (lo hará la tarea de cancelación), el usuario puede pedir de nuevo.
update public.pedidos set estado = 'Cancelado'
where id = (current_setting('test.pedido')::jsonb ->> 'pedido_id')::uuid;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'tras cancelar el pedido anterior, puede crear otro');

-- ---------------------------------------------------------------------------
-- Última unidad: la toma el solicitante 3; el solicitante 2 ya no puede
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select lives_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f7","cantidad":1}]') $$,
  'el solicitante 3 se lleva la última unidad');

reset role;
select is(
  (select inventario_disponible from public.productos where id = '00000000-0000-0000-0000-0000000000f7'),
  0, 'el inventario queda en 0, sin negativos');

-- ---------------------------------------------------------------------------
-- Rechazos del solicitante 2: nada se crea y nada se descuenta
-- ---------------------------------------------------------------------------
reset role; select pg_temp.como('00000000-0000-0000-0000-0000000000a2');

select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f7","cantidad":1}]') $$,
  'CARRITO_INVALIDO%', 'no puede pedir la unidad que otro ya se llevó');

do $$
declare v_detalle text;
begin
  begin
    perform public.crear_pedido('00000000-0000-0000-0000-000000000011',
      '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":99}]');
  exception when others then
    get stacked diagnostics v_detalle = pg_exception_detail;
  end;
  perform set_config('test.detalle', coalesce(v_detalle, ''), true);
end $$;
select alike(current_setting('test.detalle'), '%"codigo": "INVENTARIO_INSUFICIENTE"%',
  'el detalle del error trae el JSON con el código y las unidades disponibles');

-- Atomicidad: la primera línea es válida, la segunda no; no debe quedar nada a medias.
select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":2},
         {"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":99}]') $$,
  'CARRITO_INVALIDO%', 'un carrito con una línea inválida se rechaza completo');

select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f1","cantidad":1},
         {"producto_id":"00000000-0000-0000-0000-0000000000f5","cantidad":1}]') $$,
  'CARRITO_INVALIDO%', 'rechaza productos de dos comercios');

select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011', '[]') $$,
  'CARRITO_INVALIDO%', 'rechaza un carrito vacío');

select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000012',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'PUNTO_ENTREGA_INVALIDO%', 'rechaza un punto de entrega inactivo');
select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000013',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'PUNTO_ENTREGA_INVALIDO%', 'rechaza un punto cuya zona está inactiva');
select throws_like(
  $$ select public.crear_pedido('99999999-9999-9999-9999-999999999999',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'PUNTO_ENTREGA_INVALIDO%', 'rechaza un punto de entrega que no existe');
select throws_like(
  $$ select public.crear_pedido(null,
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'PUNTO_ENTREGA_INVALIDO%', 'rechaza un punto de entrega nulo');

select throws_like(
  format($$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]', %L) $$, repeat('x', 501)),
  'NOTAS_DEMASIADO_LARGAS%', 'rechaza notas de más de 500 caracteres');

reset role;
select results_eq(
  $$ select id, inventario_disponible from public.productos
     where id in ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f5',
                  '00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000f7')
     order by id $$,
  $$ values ('00000000-0000-0000-0000-0000000000f1'::uuid, 3),
            ('00000000-0000-0000-0000-0000000000f5'::uuid, 10),
            ('00000000-0000-0000-0000-0000000000f6'::uuid, 8),
            ('00000000-0000-0000-0000-0000000000f7'::uuid, 0) $$,
  'tras todos los rechazos el inventario no cambió');

select is(
  (select count(*)::int from public.pedidos where solicitante_id = '00000000-0000-0000-0000-0000000000a2'),
  0, 'tras todos los rechazos no se creó ningún pedido');

-- ---------------------------------------------------------------------------
-- Solicitante 2: pedido válido con notas en blanco
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select lives_ok(
  $$ select set_config('test.pedido2', public.crear_pedido(
       '00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f5","cantidad":2}]', '   ')::text, true) $$,
  'el solicitante 2 crea un pedido de otro comercio');

reset role;
select results_eq(
  $$ select notas_entrega, total from public.pedidos
     where id = (current_setting('test.pedido2')::jsonb ->> 'pedido_id')::uuid $$,
  $$ values (null::text, 17000.00::numeric) $$,
  'notas en blanco se guardan como NULL y el total incluye el domicilio');

select * from finish();
rollback;
