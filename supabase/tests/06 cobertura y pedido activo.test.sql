-- Pruebas de RN-002 (cobertura del campus) y RN-001 (un pedido activo por usuario, a nivel de base).
-- La concurrencia real (dos conexiones a la vez) se prueba en tests/integration/concurrencia.test.ts:
-- pgTAP corre en una sola transacción y no puede simular dos sesiones simultáneas.
begin;
create extension if not exists pgtap with schema extensions;

-- ---------------------------------------------------------------------------
-- Datos de prueba (todo se revierte con el rollback final)
-- ---------------------------------------------------------------------------
-- Ids: a1-a3 solicitantes, c1 admin de comercio, d1 zona, e1 comercio, f6 producto (10 uds),
--      11 punto dentro del campus, 14 punto lejos (fuera), 15 punto sobre el borde (V1),
--      16 punto a ~10 m fuera del borde occidental.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co', 'Solicitante Tres', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1', 'comercio')
on conflict (id) do update set rol = excluded.rol;

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);

insert into public.productos (id, comercio_id, nombre, precio, inventario_disponible, activo) values
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000e1', 'Papas', 3000, 10, true);

insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);

insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus',    6.1670, -75.5670, true),
  ('00000000-0000-0000-0000-000000000014', '00000000-0000-0000-0000-0000000000d1', 'Fuera (lejos)',        6.2001, -75.5781, true),
  ('00000000-0000-0000-0000-000000000015', '00000000-0000-0000-0000-0000000000d1', 'Sobre el borde (V1)',  6.1690, -75.5685, true),
  ('00000000-0000-0000-0000-000000000016', '00000000-0000-0000-0000-0000000000d1', 'Fuera (borde oeste)',  6.1670, -75.5686, true);

create function pg_temp.como(p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $f$;

select plan(38);

-- ---------------------------------------------------------------------------
-- RN-002: estructura y permisos
-- ---------------------------------------------------------------------------
select has_table('public', 'cobertura_campus', 'existe public.cobertura_campus');
select has_function('public', '_punto_en_cobertura', array['numeric', 'numeric'], 'existe _punto_en_cobertura');
select table_privs_are('public', 'cobertura_campus', 'authenticated', array[]::text[],
  'authenticated no accede directo a cobertura_campus');
select function_privs_are('public', '_punto_en_cobertura', array['numeric', 'numeric'], 'authenticated', array[]::text[],
  'authenticated no ejecuta _punto_en_cobertura');
select is(
  (select count(*)::int from public.cobertura_campus
   where activo and poligono ~= polygon '((-75.5685,6.169),(-75.5645,6.169),(-75.5645,6.1645),(-75.5685,6.1645))'),
  1, 'el polígono oficial (docs/zonas_campus_piloto.md) viene configurado y activo');

-- ---------------------------------------------------------------------------
-- RN-002: _punto_en_cobertura (centro, vértices, bordes y exteriores)
-- ---------------------------------------------------------------------------
select is(public._punto_en_cobertura(6.1670, -75.5670), true,  'centro del campus: dentro');
select is(public._punto_en_cobertura(6.1690, -75.5685), true,  'vértice V1: dentro (el borde cuenta)');
select is(public._punto_en_cobertura(6.1645, -75.5645), true,  'vértice V3: dentro (el borde cuenta)');
select is(public._punto_en_cobertura(6.1690, -75.5665), true,  'borde norte: dentro');
select is(public._punto_en_cobertura(6.1691, -75.5670), false, 'justo al norte: fuera');
select is(public._punto_en_cobertura(6.1644, -75.5670), false, 'justo al sur: fuera');
select is(public._punto_en_cobertura(6.1670, -75.5644), false, 'justo al este: fuera');
select is(public._punto_en_cobertura(6.1670, -75.5686), false, 'justo al oeste: fuera');
select is(public._punto_en_cobertura(6.2001, -75.5781), false, 'lejos del campus: fuera');
select is(public._punto_en_cobertura(null, null),       false, 'coordenadas nulas: fuera');

-- ---------------------------------------------------------------------------
-- RN-002 en crear_pedido (solicitante 1)
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000014',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'FUERA_DE_COBERTURA%', 'rechaza un punto activo pero fuera del polígono');
select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000016',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'FUERA_DE_COBERTURA%', 'rechaza un punto a pocos metros fuera del borde');

reset role;
select is(
  (select count(*)::int from public.pedidos where solicitante_id = '00000000-0000-0000-0000-0000000000a1'),
  0, 'los rechazos por cobertura no crean pedido');
select is(
  (select inventario_disponible from public.productos where id = '00000000-0000-0000-0000-0000000000f6'),
  10, 'los rechazos por cobertura no descuentan inventario');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select lives_ok(
  $$ select set_config('test.p1', public.crear_pedido('00000000-0000-0000-0000-000000000015',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]')::text, true) $$,
  'acepta un punto sobre el borde del polígono');

reset role;
select is(
  (select count(*)::int from public.pedidos
   where id = (current_setting('test.p1')::jsonb ->> 'pedido_id')::uuid
     and punto_entrega_id = '00000000-0000-0000-0000-000000000015' and estado = 'Creado'),
  1, 'el pedido del punto en el borde queda guardado');

-- ---------------------------------------------------------------------------
-- RN-002 usa el polígono CONFIGURADO (solicitante 2)
-- ---------------------------------------------------------------------------
update public.cobertura_campus set activo = false;
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'COBERTURA_NO_CONFIGURADA%', 'sin polígono activo no se aceptan pedidos (falla cerrado)');

reset role;
update public.cobertura_campus
set poligono = polygon '((-75.5782,6.2002),(-75.5780,6.2002),(-75.5780,6.2000),(-75.5782,6.2000))',
    activo = true;
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select throws_like(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'FUERA_DE_COBERTURA%', 'si se cambia el polígono, el punto del campus original queda fuera');
select lives_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000014',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'y el punto que ahora cae dentro del polígono nuevo se acepta');

reset role;
update public.cobertura_campus
set poligono = polygon '((-75.5685,6.169),(-75.5645,6.169),(-75.5645,6.1645),(-75.5685,6.1645))',
    activo = true;
select is(public._punto_en_cobertura(6.1670, -75.5670), true, 'tras restaurar el polígono oficial vuelve a cubrir el campus');

-- ---------------------------------------------------------------------------
-- RN-001 desde crear_pedido: el solicitante 1 ya tiene un pedido Creado
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  '23505', 'PEDIDO_ACTIVO_EXISTENTE: Ya tienes un pedido en curso.',
  'un segundo pedido con uno activo se rechaza');

-- ---------------------------------------------------------------------------
-- RN-001: el índice único parcial (la garantía real, también para la concurrencia)
-- ---------------------------------------------------------------------------
reset role;
select ok(
  exists (select 1 from pg_index i
          where i.indexrelid = 'public.idx_un_pedido_activo_por_usuario'::regclass
            and i.indisunique and i.indpred is not null),
  'idx_un_pedido_activo_por_usuario es único y parcial');
select like(pg_get_indexdef('public.idx_un_pedido_activo_por_usuario'::regclass),
  '%(solicitante_id)%', 'el índice es por solicitante_id');
select like(
  (select pg_get_expr(i.indpred, i.indrelid) from pg_index i
   where i.indexrelid = 'public.idx_un_pedido_activo_por_usuario'::regclass),
  '%Creado%Asignado%En Camino%', 'el índice cubre Creado, Asignado y En Camino');
select ok(
  (select pg_get_expr(i.indpred, i.indrelid) !~ '(Cancelado|Cerrado)' from pg_index i
   where i.indexrelid = 'public.idx_un_pedido_activo_por_usuario'::regclass),
  'el índice no cubre los estados finales Cancelado ni Cerrado');

-- Inserciones directas (saltándose crear_pedido): la base igual lo impide.
select lives_ok(
  $$ insert into public.pedidos (solicitante_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total)
     values
       ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Cancelado', 1000, 2000, 3000),
       ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Cancelado', 1000, 2000, 3000),
       ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Cerrado',   1000, 2000, 3000) $$,
  'se permiten varios pedidos finalizados del mismo usuario');
select lives_ok(
  $$ insert into public.pedidos (id, solicitante_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total)
     values ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000a3',
             '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado', 1000, 2000, 3000) $$,
  'junto a los finalizados se permite un pedido activo');
select throws_ok(
  $$ insert into public.pedidos (solicitante_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total)
     values ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000e1',
             '00000000-0000-0000-0000-000000000011', 'Creado', 1000, 2000, 3000) $$,
  '23505', null, 'el índice rechaza un segundo pedido Creado');
select throws_ok(
  $$ insert into public.pedidos (solicitante_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total)
     values ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000e1',
             '00000000-0000-0000-0000-000000000011', 'Asignado', 1000, 2000, 3000) $$,
  '23505', null, 'el índice rechaza un segundo pedido Asignado');
select throws_ok(
  $$ insert into public.pedidos (solicitante_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total)
     values ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000e1',
             '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000) $$,
  '23505', null, 'el índice rechaza un segundo pedido En Camino');

-- ---------------------------------------------------------------------------
-- RN-001 a lo largo del ciclo de vida del pedido (solicitante 3)
-- ---------------------------------------------------------------------------
update public.pedidos set estado = 'Asignado' where id = '00000000-0000-0000-0000-0000000000aa';
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select throws_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  '23505', 'PEDIDO_ACTIVO_EXISTENTE: Ya tienes un pedido en curso.',
  'con un pedido Asignado no se puede crear otro');

reset role;
update public.pedidos set estado = 'En Camino' where id = '00000000-0000-0000-0000-0000000000aa';
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select throws_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  '23505', 'PEDIDO_ACTIVO_EXISTENTE: Ya tienes un pedido en curso.',
  'con un pedido En Camino no se puede crear otro');

reset role;
update public.pedidos set estado = 'Entregado' where id = '00000000-0000-0000-0000-0000000000aa';
update public.pedidos set estado = 'Cerrado'   where id = '00000000-0000-0000-0000-0000000000aa';
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select lives_ok(
  $$ select public.crear_pedido('00000000-0000-0000-0000-000000000011',
       '[{"producto_id":"00000000-0000-0000-0000-0000000000f6","cantidad":1}]') $$,
  'con el pedido anterior Cerrado ya puede crear otro');

select * from finish();
rollback;
