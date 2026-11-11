-- Pruebas de T-076: eliminar la cuenta (anonimizando) y limpiar cuentas sin verificar.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(17);

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
-- Datos: Ana (pedido entregado), Beto (pedido en curso), Admin único,
-- y tres cuentas para la limpieza: vieja sin verificar, nueva sin verificar, vieja verificada
-- ---------------------------------------------------------------------------
INSERT INTO auth.users (id, email, raw_user_meta_data, email_confirmed_at, created_at) VALUES
  ('f7000000-0000-0000-0000-000000000001', 'prueba.ana.del@eia.edu.co',
   '{"nombre_completo":"Ana","terminos_version":"0.1-borrador"}', now(), now()),
  ('f7000000-0000-0000-0000-000000000002', 'prueba.beto.del@eia.edu.co',
   '{"nombre_completo":"Beto"}', now(), now()),
  ('f7000000-0000-0000-0000-00000000000a', 'prueba.admin.del@eia.edu.co',
   '{"nombre_completo":"Admin"}', now(), now()),
  ('f7000000-0000-0000-0000-000000000011', 'prueba.vieja@eia.edu.co',
   '{"nombre_completo":"Vieja","terminos_version":"0.1-borrador"}', NULL, now() - interval '8 days'),
  ('f7000000-0000-0000-0000-000000000012', 'prueba.nueva@eia.edu.co',
   '{"nombre_completo":"Nueva"}', NULL, now() - interval '1 day'),
  ('f7000000-0000-0000-0000-000000000013', 'prueba.verificada@eia.edu.co',
   '{"nombre_completo":"Verificada"}', now(), now() - interval '30 days');

-- Que no haya otros admins en la base para la prueba del "único admin"
UPDATE public.perfiles SET rol = 'solicitante' WHERE rol = 'admin';
UPDATE public.perfiles SET rol = 'admin' WHERE id = 'f7000000-0000-0000-0000-00000000000a';

INSERT INTO public.zonas_campus (id, nombre) VALUES ('f8000000-0000-0000-0000-000000000001', 'Zona');
INSERT INTO public.puntos_entrega (id, zona_id, nombre, latitud, longitud) VALUES
  ('f8100000-0000-0000-0000-000000000001', 'f8000000-0000-0000-0000-000000000001', 'Punto', 6.1672, -75.5671);
INSERT INTO public.comercios (id, nombre) VALUES ('f8200000-0000-0000-0000-000000000001', 'Comercio');
INSERT INTO public.pedidos (id, solicitante_id, comercio_id, punto_entrega_id, estado, subtotal, total) VALUES
  ('f8300000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000001',
   'f8200000-0000-0000-0000-000000000001', 'f8100000-0000-0000-0000-000000000001', 'Entregado', 1000, 1000),
  ('f8300000-0000-0000-0000-000000000002', 'f7000000-0000-0000-0000-000000000002',
   'f8200000-0000-0000-0000-000000000001', 'f8100000-0000-0000-0000-000000000001', 'En Camino', 1000, 1000);

-- ===========================================================================
-- Eliminar la propia cuenta
-- ===========================================================================
SELECT pg_temp.como_anonimo();
SELECT throws_ok($$ SELECT public.eliminar_mi_cuenta() $$, '42501', NULL,
  'sin sesión no se puede llamar eliminar_mi_cuenta');
SELECT pg_temp.como_base();

SELECT pg_temp.como('f7000000-0000-0000-0000-000000000002');
SELECT throws_ok($$ SELECT public.eliminar_mi_cuenta() $$, 'DD001', NULL,
  'no se puede eliminar la cuenta con un pedido en curso');
SELECT pg_temp.como_base();

SELECT pg_temp.como('f7000000-0000-0000-0000-00000000000a');
SELECT throws_ok($$ SELECT public.eliminar_mi_cuenta() $$, 'DD002', NULL,
  'el único admin no puede eliminar su cuenta');
SELECT pg_temp.como_base();

SELECT pg_temp.como('f7000000-0000-0000-0000-000000000001');
SELECT lives_ok($$ SELECT public.eliminar_mi_cuenta() $$,
  'un usuario sin pedidos en curso puede eliminar su cuenta');
SELECT pg_temp.como_base();

SELECT is(
  (SELECT count(*)::int FROM auth.users WHERE id = 'f7000000-0000-0000-0000-000000000001'),
  0, 'el usuario ya no existe en auth (no puede volver a entrar)');

SELECT results_eq(
  $$ SELECT email, nombre_completo, telefono, rol::text, eliminado_en IS NOT NULL
     FROM public.perfiles WHERE id = 'f7000000-0000-0000-0000-000000000001' $$,
  $$ VALUES (NULL::varchar, 'Usuario eliminado'::varchar, NULL::varchar, 'solicitante', true) $$,
  'el perfil queda anonimizado');

SELECT is(
  (SELECT solicitante_id FROM public.pedidos WHERE id = 'f8300000-0000-0000-0000-000000000001'),
  'f7000000-0000-0000-0000-000000000001'::uuid, 'sus pedidos se conservan');

SELECT is(
  (SELECT version FROM public.consentimientos WHERE usuario_id = 'f7000000-0000-0000-0000-000000000001'),
  '0.1-borrador', 'su aceptación de los términos se conserva');

SELECT ok(
  (SELECT email IS NOT NULL FROM public.perfiles WHERE id = 'f7000000-0000-0000-0000-000000000002'),
  'los demás perfiles no se tocan');

-- Borrar desde el panel (sin pasar por la app) también anonimiza
DELETE FROM auth.users WHERE id = 'f7000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT nombre_completo::text FROM public.perfiles WHERE id = 'f7000000-0000-0000-0000-000000000002'),
  'Usuario eliminado', 'borrar un usuario desde el panel también anonimiza su perfil');

-- ===========================================================================
-- Limpieza de cuentas sin verificar
-- ===========================================================================
SELECT pg_temp.como('f7000000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.limpiar_cuentas_sin_verificar() $$, '42501', NULL,
  'la app no puede ejecutar la limpieza');
SELECT pg_temp.como_base();

SELECT ok(public.limpiar_cuentas_sin_verificar() >= 1, 'la limpieza borra al menos una cuenta');

SELECT is(
  (SELECT count(*)::int FROM auth.users WHERE id = 'f7000000-0000-0000-0000-000000000011'),
  0, 'borra la cuenta sin verificar de más de 7 días');

SELECT is(
  (SELECT count(*)::int FROM public.perfiles WHERE id = 'f7000000-0000-0000-0000-000000000011'),
  0, 'y también su perfil (nunca se usó)');

SELECT is(
  (SELECT count(*)::int FROM auth.users WHERE id = 'f7000000-0000-0000-0000-000000000012'),
  1, 'no borra la cuenta sin verificar reciente');

SELECT is(
  (SELECT count(*)::int FROM auth.users WHERE id = 'f7000000-0000-0000-0000-000000000013'),
  1, 'no borra cuentas verificadas');

SELECT is(
  (SELECT schedule FROM cron.job WHERE jobname = 'limpiar-cuentas-sin-verificar'),
  '0 8 * * *', 'el job de limpieza está programado todos los días');

SELECT * FROM finish();

ROLLBACK;