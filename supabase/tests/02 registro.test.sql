-- Pruebas de T-068: dominio institucional, perfil automático y correo verificado.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(5);

-- 1. Un correo de otro dominio es rechazado
SELECT throws_ok(
    format(
        'INSERT INTO auth.users (id, email)
         VALUES (%L, %L)',
        '00000000-0000-0000-0000-0000000000a0',
        'externo@gmail.com'
    ),
    'P0001',
    'Solo se permiten correos institucionales',
    'rechaza un correo de otro dominio'
);

-- 2. Un correo institucional se acepta
SELECT lives_ok(
    format(
        'INSERT INTO auth.users (id, email)
         VALUES (%L, %L)',
        '00000000-0000-0000-0000-0000000000a1',
        'prueba@' || (
            SELECT MIN(dominio)
            FROM public.dominios_permitidos
        )
    ),
    'acepta un correo institucional'
);

-- 3. Se crea el perfil con rol solicitante
SELECT is(
    (
        SELECT rol::text
        FROM public.perfiles
        WHERE id = '00000000-0000-0000-0000-0000000000a1'
    ),
    'solicitante',
    'el perfil se crea con rol solicitante'
);

-- 4. No se puede cambiar el correo a uno externo
SELECT throws_ok(
    format(
        'UPDATE auth.users
         SET email = %L
         WHERE id = %L',
        'cambio@gmail.com',
        '00000000-0000-0000-0000-0000000000a1'
    ),
    'P0001',
    'Solo se permiten correos institucionales',
    'rechaza cambiar el correo a otro dominio'
);

-- 5. Sin sesión, correo_verificado() es falso
SELECT is(
    public.correo_verificado(),
    false,
    'sin sesión no hay correo verificado'
);

SELECT * FROM finish();

ROLLBACK;