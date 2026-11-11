-- Catálogo legible desde la app: tipo de comercio, administrador opcional y permisos (RLS + grants).
-- Escrita de forma defensiva: staging ya tiene tablas y datos creados fuera de las migraciones,
-- así que no asume columnas ni políticas y se puede correr más de una vez sin errores.

-- 1. Tipo de comercio (el front filtra por 'restaurante' | 'utensilios').
--    Las filas que ya existen quedan como 'restaurante'; corregir las de utensilios con un UPDATE.
alter table public.comercios
  add column if not exists tipo text not null default 'restaurante';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'comercios_tipo_check' and conrelid = 'public.comercios'::regclass
  ) then
    alter table public.comercios
      add constraint comercios_tipo_check check (tipo in ('restaurante', 'utensilios'));
  end if;
end $$;

-- 2. Administrador opcional: permite sembrar comercios sin crear antes un usuario.
--    Se asigna cuando exista la bandeja del comercio. Solo aplica si la columna existe.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'comercios' and column_name = 'administrador_id'
  ) then
    alter table public.comercios alter column administrador_id drop not null;
  end if;
end $$;

-- 3. Índice para listar los productos de un comercio.
create index if not exists idx_productos_comercio on public.productos (comercio_id);

-- 4. RLS activo en las cuatro tablas del catálogo.
alter table public.comercios      enable row level security;
alter table public.productos      enable row level security;
alter table public.zonas_campus   enable row level security;
alter table public.puntos_entrega enable row level security;

-- 5. Permisos explícitos: solo lectura y solo para usuarios con sesión.
--    Escribir en el catálogo queda para el rol comercio/admin (T-072).
revoke all on public.comercios, public.productos, public.zonas_campus, public.puntos_entrega
  from anon, authenticated;
grant select on public.comercios, public.productos, public.zonas_campus, public.puntos_entrega
  to authenticated;

-- 6. Políticas: solo se ve lo activo (activo admite null, por eso "is true").
drop policy if exists leer_comercios_activos on public.comercios;
create policy leer_comercios_activos on public.comercios
  for select to authenticated
  using (activo is true);

drop policy if exists leer_productos_activos on public.productos;
create policy leer_productos_activos on public.productos
  for select to authenticated
  using (
    activo is true
    and exists (
      select 1 from public.comercios c
      where c.id = productos.comercio_id and c.activo is true
    )
  );

drop policy if exists leer_zonas_activas on public.zonas_campus;
create policy leer_zonas_activas on public.zonas_campus
  for select to authenticated
  using (activo is true);

drop policy if exists leer_puntos_activos on public.puntos_entrega;
create policy leer_puntos_activos on public.puntos_entrega
  for select to authenticated
  using (activo is true);
