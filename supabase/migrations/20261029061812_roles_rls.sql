-- T-072: roles y políticas RLS.
-- Roles (enum rol_usuario): solicitante, repartidor, comercio, admin.
-- Regla general: lecturas con RLS; escrituras solo donde el rol lo justifica.
-- Los pedidos, ítems, pagos y calificaciones quedan de SOLO LECTURA para la app:
-- se escriben a través de funciones security definer (crear_pedido y demás, T-023 en adelante).

-- ============================================================================
-- 1. Funciones de apoyo para las políticas
--    security definer: leen perfiles/comercios sin pasar por su RLS (evita recursión).
-- ============================================================================
create or replace function public.mi_rol() returns public.rol_usuario
language sql stable security definer set search_path = '' as $$
  select p.rol from public.perfiles p where p.id = (select auth.uid())
$$;

create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.mi_rol() = 'admin', false)
$$;

-- Dueño = rol comercio y asignado como administrador de ese comercio
create or replace function public.es_dueno_comercio(p_comercio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.mi_rol() = 'comercio'
     and exists (
       select 1 from public.comercios c
       where c.id = p_comercio and c.administrador_id = (select auth.uid())
     )
$$;

revoke execute on function public.mi_rol(), public.es_admin(), public.es_dueno_comercio(uuid)
  from public, anon;
grant execute on function public.mi_rol(), public.es_admin(), public.es_dueno_comercio(uuid)
  to authenticated;

-- ============================================================================
-- 2. Asignar roles: solo un admin, nunca uno mismo
-- ============================================================================
create or replace function public.asignar_rol(p_usuario uuid, p_rol public.rol_usuario)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede asignar roles' using errcode = '42501';
  end if;
  if p_usuario = (select auth.uid()) then
    raise exception 'No puedes cambiar tu propio rol' using errcode = '42501';
  end if;
  update public.perfiles set rol = p_rol where id = p_usuario;
  if not found then
    raise exception 'Usuario no encontrado' using errcode = 'P0002';
  end if;
end $$;

revoke execute on function public.asignar_rol(uuid, public.rol_usuario) from public, anon;
grant execute on function public.asignar_rol(uuid, public.rol_usuario) to authenticated;

-- ============================================================================
-- 3. Perfiles: cada uno ve y edita sus datos básicos (nunca el rol); el admin ve todos
-- ============================================================================
grant update (nombre_completo, telefono) on public.perfiles to authenticated;

drop policy if exists editar_mi_perfil on public.perfiles;
create policy editar_mi_perfil on public.perfiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists admin_ve_perfiles on public.perfiles;
create policy admin_ve_perfiles on public.perfiles
  for select to authenticated
  using ((select public.es_admin()));

-- ============================================================================
-- 4. Comercios: el admin los crea, edita y borra; el dueño edita el suyo
-- ============================================================================
grant insert, update, delete on public.comercios to authenticated;

drop policy if exists dueno_o_admin_ve_comercio on public.comercios;
create policy dueno_o_admin_ve_comercio on public.comercios
  for select to authenticated
  using ((select public.es_admin()) or public.es_dueno_comercio(id));

drop policy if exists admin_crea_comercio on public.comercios;
create policy admin_crea_comercio on public.comercios
  for insert to authenticated
  with check ((select public.es_admin()));

drop policy if exists dueno_o_admin_edita_comercio on public.comercios;
create policy dueno_o_admin_edita_comercio on public.comercios
  for update to authenticated
  using ((select public.es_admin()) or public.es_dueno_comercio(id))
  with check ((select public.es_admin()) or public.es_dueno_comercio(id));

drop policy if exists admin_borra_comercio on public.comercios;
create policy admin_borra_comercio on public.comercios
  for delete to authenticated
  using ((select public.es_admin()));

-- Solo un admin cambia el dueño de un comercio. Desde el SQL Editor (sin usuario de la app)
-- sí se permite, para poder asignar el primero.
create or replace function public.proteger_dueno_comercio() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.administrador_id is distinct from old.administrador_id
     and (select auth.uid()) is not null
     and not public.es_admin() then
    raise exception 'Solo un administrador puede cambiar el dueño del comercio'
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists t_proteger_dueno_comercio on public.comercios;
create trigger t_proteger_dueno_comercio before update of administrador_id on public.comercios
  for each row execute function public.proteger_dueno_comercio();

-- ============================================================================
-- 5. Productos: el dueño del comercio y el admin los administran
--    (el with check impide pasar un producto a un comercio ajeno)
-- ============================================================================
grant insert, update, delete on public.productos to authenticated;

drop policy if exists dueno_o_admin_ve_productos on public.productos;
create policy dueno_o_admin_ve_productos on public.productos
  for select to authenticated
  using ((select public.es_admin()) or public.es_dueno_comercio(comercio_id));

drop policy if exists dueno_o_admin_crea_producto on public.productos;
create policy dueno_o_admin_crea_producto on public.productos
  for insert to authenticated
  with check ((select public.es_admin()) or public.es_dueno_comercio(comercio_id));

drop policy if exists dueno_o_admin_edita_producto on public.productos;
create policy dueno_o_admin_edita_producto on public.productos
  for update to authenticated
  using ((select public.es_admin()) or public.es_dueno_comercio(comercio_id))
  with check ((select public.es_admin()) or public.es_dueno_comercio(comercio_id));

drop policy if exists dueno_o_admin_borra_producto on public.productos;
create policy dueno_o_admin_borra_producto on public.productos
  for delete to authenticated
  using ((select public.es_admin()) or public.es_dueno_comercio(comercio_id));

-- ============================================================================
-- 6. Zonas y puntos de entrega: solo el admin los administra (y ve los inactivos)
-- ============================================================================
grant insert, update, delete on public.zonas_campus, public.puntos_entrega to authenticated;

drop policy if exists admin_gestiona_zonas on public.zonas_campus;
create policy admin_gestiona_zonas on public.zonas_campus
  for all to authenticated
  using ((select public.es_admin()))
  with check ((select public.es_admin()));

drop policy if exists admin_gestiona_puntos on public.puntos_entrega;
create policy admin_gestiona_puntos on public.puntos_entrega
  for all to authenticated
  using ((select public.es_admin()))
  with check ((select public.es_admin()));

-- ============================================================================
-- 7. Pedidos y relacionados: RLS activo, SOLO LECTURA desde la app
-- ============================================================================
alter table public.pedidos        enable row level security;
alter table public.items_pedido   enable row level security;
alter table public.pagos          enable row level security;
alter table public.calificaciones enable row level security;

revoke all on public.pedidos, public.items_pedido, public.pagos, public.calificaciones
  from anon, authenticated;
grant select on public.pedidos, public.items_pedido, public.pagos, public.calificaciones
  to authenticated;

-- Solicitante: los suyos. Repartidor: los asignados a él y los disponibles (Creado, sin
-- repartidor). Comercio: los de su comercio. Admin: todos.
drop policy if exists ver_pedidos_por_rol on public.pedidos;
create policy ver_pedidos_por_rol on public.pedidos
  for select to authenticated
  using (
    solicitante_id = (select auth.uid())
    or repartidor_id = (select auth.uid())
    or (
      (select public.mi_rol()) = 'repartidor'
      and estado = 'Creado'
      and repartidor_id is null
    )
    or public.es_dueno_comercio(comercio_id)
    or (select public.es_admin())
  );

-- Ítems y pagos: visibles si el pedido es visible (la subconsulta respeta la RLS de pedidos)
drop policy if exists ver_items_de_mis_pedidos on public.items_pedido;
create policy ver_items_de_mis_pedidos on public.items_pedido
  for select to authenticated
  using (exists (select 1 from public.pedidos p where p.id = items_pedido.pedido_id));

drop policy if exists ver_pagos_de_mis_pedidos on public.pagos;
create policy ver_pagos_de_mis_pedidos on public.pagos
  for select to authenticated
  using (exists (select 1 from public.pedidos p where p.id = pagos.pedido_id));

drop policy if exists ver_calificaciones_propias on public.calificaciones;
create policy ver_calificaciones_propias on public.calificaciones
  for select to authenticated
  using (
    solicitante_id = (select auth.uid())
    or repartidor_id = (select auth.uid())
    or (select public.es_admin())
  );

-- ============================================================================
-- 8. Consentimientos: el admin puede consultarlos (auditoría, Ley 1581)
-- ============================================================================
drop policy if exists admin_ve_consentimientos on public.consentimientos;
create policy admin_ve_consentimientos on public.consentimientos
  for select to authenticated
  using ((select public.es_admin()));