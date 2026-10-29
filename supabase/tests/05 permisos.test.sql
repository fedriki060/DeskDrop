-- Revisión general de permisos: ninguna tabla de public queda con más permisos de los que
-- se dieron a propósito. Supabase da ALL por defecto a anon y authenticated sobre cada tabla
-- nueva; si una migración olvida el "revoke all", estas pruebas fallan.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(4);

-- 1. Sin sesión (anon) no se puede escribir en ninguna tabla
SELECT is_empty(
  $$
    SELECT c.relname || ' (' || p.privilegio || ')'
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN (VALUES ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) AS p(privilegio)
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
      AND has_table_privilege('anon', c.oid, p.privilegio)
  $$,
  'anon no puede escribir en ninguna tabla de public'
);

-- 2. Con sesión, nadie puede vaciar tablas ni crear triggers o referencias sobre ellas
SELECT is_empty(
  $$
    SELECT c.relname || ' (' || p.privilegio || ')'
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN (VALUES ('TRUNCATE'), ('TRIGGER'), ('REFERENCES')) AS p(privilegio)
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
      AND has_table_privilege('authenticated', c.oid, p.privilegio)
  $$,
  'authenticated no puede vaciar tablas ni crear triggers sobre ellas'
);

-- 3. El rol de un perfil no se puede editar directamente (solo con asignar_rol)
SELECT ok(
  NOT has_column_privilege('authenticated', 'public.perfiles', 'rol', 'UPDATE'),
  'authenticated no puede editar la columna rol'
);

-- 4. Pedidos y relacionados: la app solo lee; las escrituras van por funciones
SELECT is_empty(
  $$
    SELECT c.relname || ' (' || p.privilegio || ')'
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN (VALUES ('INSERT'), ('UPDATE'), ('DELETE')) AS p(privilegio)
    WHERE n.nspname = 'public'
      AND c.relname IN ('pedidos', 'items_pedido', 'pagos', 'calificaciones')
      AND has_table_privilege('authenticated', c.oid, p.privilegio)
  $$,
  'authenticated no escribe directo en pedidos, ítems, pagos ni calificaciones'
);

SELECT * FROM finish();

ROLLBACK;