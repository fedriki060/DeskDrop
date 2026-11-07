-- ==============================================================================
-- DESKDROP: VISTA DEL CATÁLOGO (precio y disponibilidad)
-- ==============================================================================
-- Los permisos y las políticas de comercios y productos ya los definen
-- catalogo_permisos (lectura de lo activo) y roles_rls (dueño del comercio y admin).
-- Aquí solo se agrega la vista que consume la app y un índice para las políticas.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Índice para es_dueno_comercio() y las políticas del dueño
-- ------------------------------------------------------------------------------
create index if not exists idx_comercios_administrador_id
  on public.comercios (administrador_id);

-- ------------------------------------------------------------------------------
-- 2. Vista del catálogo (lo que consume la app)
-- ------------------------------------------------------------------------------
-- security_invoker = true: la vista se ejecuta con los permisos de quien consulta,
-- así que aplican las políticas RLS de `productos` y `comercios`.
-- Uso: supabase.from('catalogo_productos').select('*').eq('comercio_id', id)
create or replace view public.catalogo_productos
with (security_invoker = true)
as
select
  p.id,
  p.comercio_id,
  p.nombre,
  p.descripcion,
  p.precio,
  p.imagen_url,
  p.inventario_disponible,
  (p.inventario_disponible > 0) as disponible
from public.productos p
where p.activo is true;

comment on view public.catalogo_productos is
  'Catálogo visible para el cliente: productos activos con precio y disponibilidad. Hereda RLS de productos/comercios.';

revoke all on public.catalogo_productos from anon, authenticated;
grant select on public.catalogo_productos to authenticated;