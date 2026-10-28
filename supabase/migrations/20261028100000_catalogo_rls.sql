-- ==============================================================================
-- DESKDROP: CATÁLOGO DEL COMERCIO CON LECTURA PROTEGIDA POR RLS
-- ==============================================================================
-- Expone comercios y productos (precio y disponibilidad) a usuarios autenticados.
-- Reglas:
--   * Solo `authenticated` lee el catálogo; `anon` no ve nada (la app exige sesión).
--   * El cliente ve únicamente comercios activos y sus productos activos.
--   * El administrador de un comercio también ve lo suyo aunque esté inactivo.
--   * Nadie escribe desde la Data API: el inventario solo cambia por funciones SQL.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Línea base de seguridad: RLS activo en TODAS las tablas del esquema inicial
-- ------------------------------------------------------------------------------
-- La migración inicial creó las tablas sin RLS ni permisos explícitos. Se activa RLS
-- (sin políticas = nada es visible) y se revocan los privilegios por defecto. Cada
-- tabla recibe sus `grant` y políticas en la migración de la tarea que la expone.
-- No se usa FORCE: las funciones SECURITY DEFINER (dueño de las tablas) necesitan
-- operar sobre ellas, y el resto de roles queda sujeto a RLS.

alter table public.perfiles        enable row level security;
alter table public.comercios       enable row level security;
alter table public.productos       enable row level security;
alter table public.zonas_campus    enable row level security;
alter table public.puntos_entrega  enable row level security;
alter table public.pedidos         enable row level security;
alter table public.items_pedido    enable row level security;
alter table public.pagos           enable row level security;
alter table public.calificaciones  enable row level security;

revoke all on public.perfiles, public.comercios, public.productos,
              public.zonas_campus, public.puntos_entrega, public.pedidos,
              public.items_pedido, public.pagos, public.calificaciones
  from anon, authenticated;

-- ------------------------------------------------------------------------------
-- 2. Índices para las consultas del catálogo y de las políticas
-- ------------------------------------------------------------------------------
create index if not exists idx_productos_comercio_id
  on public.productos (comercio_id);

create index if not exists idx_comercios_administrador_id
  on public.comercios (administrador_id);

-- ------------------------------------------------------------------------------
-- 3. Políticas de lectura
-- ------------------------------------------------------------------------------
grant select on public.comercios, public.productos to authenticated;

create policy comercios_lectura
  on public.comercios
  for select
  to authenticated
  using (
    activo is true
    or administrador_id = (select auth.uid())
  );

-- La subconsulta sobre `comercios` también pasa por RLS: un cliente solo puede
-- "ver" comercios activos, así que los productos de un comercio inactivo quedan ocultos.
create policy productos_lectura
  on public.productos
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.comercios c
      where c.id = productos.comercio_id
        and c.administrador_id = (select auth.uid())
    )
    or (
      productos.activo is true
      and exists (
        select 1
        from public.comercios c
        where c.id = productos.comercio_id
          and c.activo is true
      )
    )
  );

-- ------------------------------------------------------------------------------
-- 4. Vista del catálogo (lo que consume la app)
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
