-- Pruebas de T-072 / T-074: acceso permitido y denegado según el rol.
-- Cada prueba se hace "como" un usuario: rol authenticated + su id en el JWT (request.jwt.claims),
-- igual que cuando la app llama a Supabase. Todo corre dentro de una transacción que se deshace.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(24);

-- ---------------------------------------------------------------------------
-- Ayudas: actuar como un usuario de la app, o volver a ser el administrador de la base
-- ---------------------------------------------------------------------------
CREATE FUNCTION pg_temp.como(p_usuario uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_usuario, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END $$;

CREATE FUNCTION pg_temp.como_anonimo() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  EXECUTE 'SET LOCAL ROLE anon';
END $$;

CREATE FUNCTION pg_temp.como_base() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- ---------------------------------------------------------------------------
-- Datos de prueba (ids con prefijo f... para no chocar con el seed)
--   Usuarios: admin, dueña (comercio), otro comercio, repartidor, sol1, sol2
--   Comercios: C1 de la dueña, C3 del otro comercio. C1 tiene un producto activo y uno inactivo.
--   Pedidos: P1 de sol1 en C1 disponible; P2 de sol2 en C1 asignado al repartidor; P3 de sol2 en C3.
-- ---------------------------------------------------------------------------
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('f0000000-0000-0000-0000-00000000000a', 'prueba.admin@eia.edu.co',  '{"nombre_completo":"Admin"}'),
  ('f0000000-0000-0000-0000-00000000000c', 'prueba.duena@eia.edu.co',  '{"nombre_completo":"Dueña"}'),
  ('f0000000-0000-0000-0000-00000000000d', 'prueba.otro@eia.edu.co',   '{"nombre_completo":"Otro comercio"}'),
  ('f0000000-0000-0000-0000-00000000000b', 'prueba.repa@eia.edu.co',   '{"nombre_completo":"Repartidor"}'),
  ('f0000000-0000-0000-0000-000000000001', 'prueba.sol1@eia.edu.co',   '{"nombre_completo":"Sol 1"}'),
  ('f0000000-0000-0000-0000-000000000002', 'prueba.sol2@eia.edu.co',   '{"nombre_completo":"Sol 2"}');

UPDATE public.perfiles SET rol = 'admin'      WHERE id = 'f0000000-0000-0000-0000-00000000000a';
UPDATE public.perfiles SET rol = 'comercio'   WHERE id IN ('f0000000-0000-0000-0000-00000000000c', 'f0000000-0000-0000-0000-00000000000d');
UPDATE public.perfiles SET rol = 'repartidor' WHERE id = 'f0000000-0000-0000-0000-00000000000b';

INSERT INTO public.zonas_campus (id, nombre) VALUES ('f1000000-0000-0000-0000-000000000001', 'Zona de prueba');
INSERT INTO public.puntos_entrega (id, zona_id, nombre, latitud, longitud) VALUES
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'Punto de prueba', 6.1672, -75.5671);

INSERT INTO public.comercios (id, nombre, tipo, administrador_id) VALUES
  ('f3000000-0000-0000-0000-000000000001', 'Comercio de la dueña', 'restaurante', 'f0000000-0000-0000-0000-00000000000c'),
  ('f3000000-0000-0000-0000-000000000003', 'Comercio ajeno',       'utensilios',  'f0000000-0000-0000-0000-00000000000d');

INSERT INTO public.productos (id, comercio_id, nombre, precio, inventario_disponible, activo) VALUES
  ('f4000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Activo',   1000, 10, true),
  ('f4000000-0000-0000-0000-000000000002', 'f3000000-0000-0000-0000-000000000001', 'Inactivo', 1000, 10, false),
  ('f4000000-0000-0000-0000-000000000003', 'f3000000-0000-0000-0000-000000000003', 'Ajeno',    1000, 10, true);

INSERT INTO public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, total) VALUES
  ('f5000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', NULL,
   'f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'Creado', 1000, 1000),
  ('f5000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-00000000000b',
   'f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'Asignado', 1000, 1000),
  ('f5000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000002', NULL,
   'f3000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000001', 'Entregado', 1000, 1000);

-- Pedidos de prueba que puede ver quien esté actuando
CREATE FUNCTION pg_temp.pedidos_visibles() RETURNS int LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.pedidos WHERE id::text LIKE 'f5%'
$$;

-- ===========================================================================
-- Solicitante
-- ===========================================================================
SELECT pg_temp.como('f0000000-0000-0000-0000-000000000001');

SELECT is(pg_temp.pedidos_visibles(), 1, 'solicitante: ve solo su pedido');

SELECT is(
  (SELECT count(*)::int FROM public.perfiles WHERE id <> 'f0000000-0000-0000-0000-000000000001'),
  0, 'solicitante: no ve perfiles ajenos');

SELECT is(
  (SELECT count(*)::int FROM public.productos WHERE id = 'f4000000-0000-0000-0000-000000000002'),
  0, 'solicitante: no ve productos inactivos');

WITH x AS (UPDATE public.productos SET precio = 1 WHERE id::text LIKE 'f4%' RETURNING 1)
SELECT is(count(*)::int, 0, 'solicitante: no puede cambiar precios') FROM x;

SELECT throws_ok(
  $$ UPDATE public.perfiles SET rol = 'admin' WHERE id = 'f0000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'solicitante: no puede cambiarse el rol');

SELECT throws_ok(
  $$ SELECT public.asignar_rol('f0000000-0000-0000-0000-000000000001', 'admin') $$,
  '42501', NULL, 'solicitante: no puede usar asignar_rol');

SELECT throws_ok(
  $$ INSERT INTO public.pedidos (solicitante_id, comercio_id, punto_entrega_id, subtotal, total)
     VALUES ('f0000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
             'f2000000-0000-0000-0000-000000000001', 1, 1) $$,
  '42501', NULL, 'solicitante: no puede insertar pedidos directamente');

WITH x AS (
  UPDATE public.perfiles SET nombre_completo = 'Sol Uno'
  WHERE id = 'f0000000-0000-0000-0000-000000000001' RETURNING 1)
SELECT is(count(*)::int, 1, 'solicitante: sí puede editar su nombre') FROM x;

SELECT pg_temp.como_base();

-- ===========================================================================
-- Repartidor
-- ===========================================================================
SELECT pg_temp.como('f0000000-0000-0000-0000-00000000000b');

SELECT is(pg_temp.pedidos_visibles(), 2, 'repartidor: ve el disponible y el asignado a él');

SELECT throws_ok(
  $$ UPDATE public.pedidos SET estado = 'Entregado' WHERE id = 'f5000000-0000-0000-0000-000000000002' $$,
  '42501', NULL, 'repartidor: no puede cambiar el estado directamente');

SELECT pg_temp.como_base();

-- ===========================================================================
-- Comercio (dueña de C1)
-- ===========================================================================
SELECT pg_temp.como('f0000000-0000-0000-0000-00000000000c');

SELECT is(
  (SELECT count(*)::int FROM public.productos WHERE id = 'f4000000-0000-0000-0000-000000000002'),
  1, 'comercio: ve su producto inactivo');

SELECT is(pg_temp.pedidos_visibles(), 2, 'comercio: ve solo los pedidos de su comercio');

WITH x AS (UPDATE public.productos SET precio = 1200 WHERE id = 'f4000000-0000-0000-0000-000000000001' RETURNING 1)
SELECT is(count(*)::int, 1, 'comercio: sí puede editar su producto') FROM x;

WITH x AS (UPDATE public.productos SET precio = 1 WHERE id = 'f4000000-0000-0000-0000-000000000003' RETURNING 1)
SELECT is(count(*)::int, 0, 'comercio: no puede editar productos de otro comercio') FROM x;

SELECT throws_ok(
  $$ UPDATE public.productos SET comercio_id = 'f3000000-0000-0000-0000-000000000003'
     WHERE id = 'f4000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'comercio: no puede pasar su producto a otro comercio');

SELECT throws_ok(
  $$ INSERT INTO public.comercios (nombre) VALUES ('Comercio nuevo') $$,
  '42501', NULL, 'comercio: no puede crear comercios');

SELECT throws_ok(
  $$ UPDATE public.comercios SET administrador_id = 'f0000000-0000-0000-0000-000000000001'
     WHERE id = 'f3000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'comercio: no puede cambiar el dueño de su comercio');

SELECT throws_ok(
  $$ INSERT INTO public.zonas_campus (nombre) VALUES ('Zona nueva') $$,
  '42501', NULL, 'comercio: no puede crear zonas');

SELECT pg_temp.como_base();

-- ===========================================================================
-- Admin
-- ===========================================================================
SELECT pg_temp.como('f0000000-0000-0000-0000-00000000000a');

SELECT is(pg_temp.pedidos_visibles(), 3, 'admin: ve todos los pedidos');

SELECT lives_ok(
  $$ SELECT public.asignar_rol('f0000000-0000-0000-0000-000000000001', 'repartidor') $$,
  'admin: puede asignar roles');

SELECT throws_ok(
  $$ SELECT public.asignar_rol('f0000000-0000-0000-0000-00000000000a', 'solicitante') $$,
  '42501', NULL, 'admin: no puede cambiar su propio rol');

SELECT lives_ok(
  $$ INSERT INTO public.zonas_campus (nombre) VALUES ('Zona del admin') $$,
  'admin: puede crear zonas');

SELECT pg_temp.como_base();

-- ===========================================================================
-- Sin sesión (anon)
-- ===========================================================================
SELECT pg_temp.como_anonimo();

SELECT throws_ok(
  $$ SELECT count(*) FROM public.comercios $$,
  '42501', NULL, 'sin sesión: no puede leer el catálogo');

SELECT throws_ok(
  $$ SELECT count(*) FROM public.pedidos $$,
  '42501', NULL, 'sin sesión: no puede leer pedidos');

SELECT pg_temp.como_base();

SELECT * FROM finish();

ROLLBACK;