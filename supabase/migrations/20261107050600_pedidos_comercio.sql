-- ==============================================================================
-- DESKDROP: PEDIDOS DEL COMERCIO (listar, ver y marcar "Listo para recoger")
-- ==============================================================================
-- Listar y ver: el comercio consulta `pedidos` e `items_pedido` directamente y RLS le
-- deja ver SOLO los de los comercios que administra (política ver_pedidos_por_rol de roles_rls).
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
-- 1. Marcar un pedido como "Listo para recoger"
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

  if public.mi_rol() is distinct from 'comercio' then
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
