-- Pruebas de T-075: aceptación de Términos y Política de privacidad (tabla consentimientos).

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(9);

CREATE FUNCTION pg_temp.como(p_usuario uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_usuario, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END $$;

CREATE FUNCTION pg_temp.como_base() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- Ana se registra desde la app (con versión); Beto se crea desde el panel (sin versión)
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('f6000000-0000-0000-0000-000000000001', 'prueba.ana@eia.edu.co',
   '{"nombre_completo":"Ana","terminos_version":"0.1-borrador"}'),
  ('f6000000-0000-0000-0000-000000000002', 'prueba.beto@eia.edu.co',
   '{"nombre_completo":"Beto"}'),
  ('f6000000-0000-0000-0000-00000000000a', 'prueba.admin2@eia.edu.co',
   '{"nombre_completo":"Admin"}');
UPDATE public.perfiles SET rol = 'admin' WHERE id = 'f6000000-0000-0000-0000-00000000000a';

-- 1-3. El registro guarda la aceptación con fecha del servidor
SELECT is(
  (SELECT version FROM public.consentimientos WHERE usuario_id = 'f6000000-0000-0000-0000-000000000001'),
  '0.1-borrador', 'el registro con versión guarda la aceptación');

SELECT ok(
  (SELECT aceptado_en IS NOT NULL FROM public.consentimientos
   WHERE usuario_id = 'f6000000-0000-0000-0000-000000000001'),
  'la aceptación queda con fecha');

SELECT is(
  (SELECT count(*)::int FROM public.consentimientos WHERE usuario_id = 'f6000000-0000-0000-0000-000000000002'),
  0, 'un usuario creado sin versión no queda con aceptación');

-- 4-8. Lo que puede y no puede hacer el usuario
SELECT pg_temp.como('f6000000-0000-0000-0000-000000000002');

SELECT is(
  (SELECT count(*)::int FROM public.consentimientos),
  0, 'un usuario no ve aceptaciones ajenas');

SELECT lives_ok(
  $$ INSERT INTO public.consentimientos (version) VALUES ('0.2') $$,
  'un usuario puede aceptar una versión nueva');

SELECT throws_ok(
  $$ INSERT INTO public.consentimientos (version, aceptado_en) VALUES ('0.3', '2020-01-01') $$,
  '42501', NULL, 'no puede inventar la fecha de aceptación');

SELECT throws_ok(
  $$ INSERT INTO public.consentimientos (usuario_id, version)
     VALUES ('f6000000-0000-0000-0000-000000000001', '0.3') $$,
  '42501', NULL, 'no puede aceptar a nombre de otro');

SELECT throws_ok(
  $$ DELETE FROM public.consentimientos $$,
  '42501', NULL, 'no puede borrar aceptaciones');

SELECT pg_temp.como_base();

-- 9. El admin puede auditarlas
SELECT pg_temp.como('f6000000-0000-0000-0000-00000000000a');

SELECT ok(
  (SELECT count(*) FROM public.consentimientos WHERE usuario_id::text LIKE 'f6%') >= 2,
  'el admin puede consultar las aceptaciones de todos');

SELECT pg_temp.como_base();

SELECT * FROM finish();

ROLLBACK;