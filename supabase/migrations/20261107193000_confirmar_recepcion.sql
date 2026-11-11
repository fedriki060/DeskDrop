-- ==============================================================================
-- DESKDROP: EL SOLICITANTE CONFIRMA QUE RECIBIÓ SU PEDIDO (T-040)
-- ==============================================================================
-- confirmar_recepcion(p_pedido_id) pasa el pedido de `En Camino` a `Entregado`.
--   * Solo la puede usar el solicitante dueño del pedido. A cualquier otro usuario se le
--     responde PEDIDO_NO_ENCONTRADO, para no revelar que el pedido existe.
--   * Solo desde `En Camino` (matriz de 20261107050200_pedido_estados). Confirmar otra vez
--     un pedido ya entregado responde ESTADO_NO_PERMITIDO con el estado actual.
--   * Bloquea la fila (`for update`) para no chocar con la auto-confirmación (T-042) ni con
--     otro toque al botón: el segundo intento ve el estado ya cambiado.
--   * Con el pedido Entregado, el repartidor ya puede registrar el cobro en efectivo
--     (registrar_cobro_efectivo, T-031), y el solicitante queda libre para otro pedido
--     (RN-001 solo cuenta Creado, Asignado y En Camino).
--
-- Errores (mismo formato que crear_pedido: 'CODIGO: mensaje'):
--   NO_AUTENTICADO        28000  sin sesión
--   PEDIDO_NO_ENCONTRADO  P0002  no existe o no es del usuario
--   ESTADO_NO_PERMITIDO   55000  el pedido no está En Camino
--
-- Uso desde la app:
--   supabase.rpc('confirmar_recepcion', { p_pedido_id: id })
--   -> { pedido_id, estado: 'Entregado', entregado_en }
-- ==============================================================================

create or replace function public.confirmar_recepcion(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_estado public.estado_pedido;
  v_fecha  timestamptz;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  select p.estado
    into v_estado
  from public.pedidos p
  where p.id = p_pedido_id
    and p.solicitante_id = v_uid
  for update;

  if not found then
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es tuyo.'
      using errcode = 'P0002';
  end if;

  if v_estado <> 'En Camino' then
    raise exception 'ESTADO_NO_PERMITIDO: Solo puedes confirmar un pedido que está En Camino (estado actual: %).', v_estado
      using errcode = '55000';
  end if;

  -- En Camino -> Entregado. El trigger de transiciones valida el cambio y pone actualizado_en.
  update public.pedidos
  set estado = 'Entregado'
  where id = p_pedido_id
  returning actualizado_en into v_fecha;

  return jsonb_build_object(
    'pedido_id',    p_pedido_id,
    'estado',       'Entregado',
    'entregado_en', v_fecha
  );
end;
$$;

comment on function public.confirmar_recepcion(uuid) is
  'T-040 (HU-09): el solicitante dueño confirma que recibió su pedido (En Camino -> Entregado).';

revoke all on function public.confirmar_recepcion(uuid) from public, anon;
grant execute on function public.confirmar_recepcion(uuid) to authenticated;
