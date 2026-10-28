-- ==============================================================================
-- DESKDROP: PEDIDOS DEL COMERCIO (listar, ver y marcar "Listo para recoger")
-- ==============================================================================
-- Listar y ver: el comercio consulta `pedidos` e `items_pedido` directamente y RLS le
-- deja ver SOLO los de los comercios que administra (política pedidos_lectura).
--
--   supabase.from('pedidos')
--     .select('id, estado, listo_para_recoger, total, notas_entrega, creado_en, items_pedido(cantidad, precio_unitario, productos(nombre))')
--     .eq('comercio_id', comercioId)
--     .in('estado', ['Creado', 'Asignado'])
--     .order('creado_en')
--
-- Escribir: nadie modifica pedidos desde la Data API. El comercio usa
--   supabase.rpc('marcar_listo_para_recoger', { p_pedido_id })
--
-- Errores (error.message empieza por el código):
--   NO_AUTENTICADO, ROL_NO_PERMITIDO, PEDIDO_NO_ENCONTRADO, ESTADO_NO_PERMITIDO
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Rol del usuario autenticado (para políticas RLS por rol)
-- ------------------------------------------------------------------------------
-- SECURITY DEFINER porque `perfiles` no es legible desde la API.
create or replace function public.rol_actual()
returns public.rol_usuario
language sql
stable
security definer
set search_path = ''
as $$
  select p.rol from public.perfiles p where p.id = (select auth.uid())
$$;

comment on function public.rol_actual() is
  'Rol del usuario autenticado (null si no hay sesión o no tiene perfil). Se usa en políticas RLS.';

revoke all on function public.rol_actual() from public, anon;
grant execute on function public.rol_actual() to authenticated;

-- ------------------------------------------------------------------------------
-- 2. Lectura de pedidos por rol
-- ------------------------------------------------------------------------------
--   solicitante -> sus pedidos
--   repartidor  -> los pedidos que tiene asignados
--   comercio    -> los pedidos de los comercios que administra
-- items_pedido y pagos heredan esta visibilidad (sus políticas consultan pedidos).
drop policy if exists pedidos_lectura on public.pedidos;

create policy pedidos_lectura
  on public.pedidos
  for select
  to authenticated
  using (
    (    (select public.rol_actual()) = 'solicitante'
     and solicitante_id = (select auth.uid()))
    or ((select public.rol_actual()) = 'repartidor'
     and repartidor_id = (select auth.uid()))
    or ((select public.rol_actual()) = 'comercio'
     and exists (
          select 1
          from public.comercios c
          where c.id = pedidos.comercio_id
            and c.administrador_id = (select auth.uid())
        ))
  );

-- ------------------------------------------------------------------------------
-- 3. Marcar un pedido como "Listo para recoger"
-- ------------------------------------------------------------------------------
-- Solo el administrador del comercio del pedido, y solo mientras el pedido siga en
-- Creado o Asignado (aún no salió). Es idempotente: marcarlo dos veces no falla.
-- El pedido de otro comercio responde PEDIDO_NO_ENCONTRADO (no revela que existe).
create or replace function public.marcar_listo_para_recoger(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_estado public.estado_pedido;
  v_listo  boolean;
  v_actual timestamptz;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if public.rol_actual() is distinct from 'comercio' then
    raise exception 'ROL_NO_PERMITIDO: Solo un comercio puede marcar pedidos como listos.'
      using errcode = '42501';
  end if;

  -- Bloquea la fila: dos clics simultáneos se serializan.
  select p.estado, p.listo_para_recoger
    into v_estado, v_listo
  from public.pedidos p
  join public.comercios c on c.id = p.comercio_id
  where p.id = p_pedido_id
    and c.administrador_id = v_uid
  for update of p;

  if not found then
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es de tu comercio.'
      using errcode = 'P0002';
  end if;

  if v_estado not in ('Creado', 'Asignado') then
    raise exception 'ESTADO_NO_PERMITIDO: Un pedido en estado % ya no puede marcarse como listo.', v_estado
      using errcode = '55000';
  end if;

  if v_listo is not true then
    update public.pedidos
    set listo_para_recoger = true
    where id = p_pedido_id;
  end if;

  select p.actualizado_en into v_actual from public.pedidos p where p.id = p_pedido_id;

  return jsonb_build_object(
    'pedido_id',          p_pedido_id,
    'estado',             v_estado,
    'listo_para_recoger', true,
    'actualizado_en',     v_actual
  );
end;
$$;

comment on function public.marcar_listo_para_recoger(uuid) is
  'El comercio marca su pedido (Creado o Asignado) como listo para recoger. Idempotente.';

revoke all on function public.marcar_listo_para_recoger(uuid) from public, anon;
grant execute on function public.marcar_listo_para_recoger(uuid) to authenticated;
