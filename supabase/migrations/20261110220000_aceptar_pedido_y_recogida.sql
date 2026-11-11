-- ==============================================================================
-- DESKDROP: EL DOMICILIARIO ACEPTA UN PEDIDO Y CONFIRMA LA RECOGIDA (T-036, T-084, T-085)
-- ==============================================================================
-- aceptar_pedido(pedido):    Creado -> Asignado, el pedido queda con el domiciliario que llama.
-- confirmar_recogida(pedido): Asignado -> En Camino, cuando el comercio ya lo marcó listo.
--
--   * Solo un domiciliario habilitado (HU-19). Nadie acepta su propio pedido, aunque sea
--     domiciliario: puede pedir y repartir, pero no entregarse a sí mismo.
--   * Aceptar bloquea la fila (`for update`): si dos domiciliarios aceptan a la vez, el
--     segundo espera, ve el pedido ya Asignado y recibe PEDIDO_NO_DISPONIBLE.
--   * Confirmar la recogida exige `listo_para_recoger` (lo marca el comercio con
--     marcar_listo_para_recoger). El trigger de transiciones llena `en_camino_en`, que cuenta
--     el tiempo de la auto-confirmación.
--   * La app no escribe en pedidos: solo cambia el estado a través de estas funciones.
--
-- Uso desde la app:
--   supabase.rpc('aceptar_pedido',      { p_pedido_id })
--     -> { pedido_id, estado: 'Asignado', repartidor_id, actualizado_en }
--   supabase.rpc('confirmar_recogida',  { p_pedido_id })
--     -> { pedido_id, estado: 'En Camino', en_camino_en }
--
-- Errores (error.message empieza por el código):
--   NO_AUTENTICADO 28000, ROL_NO_PERMITIDO 42501, PEDIDO_NO_ENCONTRADO P0002,
--   PEDIDO_PROPIO 42501, PEDIDO_NO_DISPONIBLE 55000,
--   ESTADO_NO_PERMITIDO 55000, PEDIDO_NO_LISTO 55000
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Aceptar un pedido disponible
-- ------------------------------------------------------------------------------
create or replace function public.aceptar_pedido(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := (select auth.uid());
  v_estado      public.estado_pedido;
  v_repartidor  uuid;
  v_solicitante uuid;
  v_actual      timestamptz;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if not public.es_repartidor_habilitado() then
    raise exception 'ROL_NO_PERMITIDO: Solo un domiciliario habilitado puede aceptar pedidos.'
      using errcode = '42501';
  end if;

  select p.estado, p.repartidor_id, p.solicitante_id
    into v_estado, v_repartidor, v_solicitante
  from public.pedidos p
  where p.id = p_pedido_id
  for update;

  if not found then
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe.' using errcode = 'P0002';
  end if;

  if v_solicitante = v_uid then
    raise exception 'PEDIDO_PROPIO: No puedes entregarte tu propio pedido.' using errcode = '42501';
  end if;

  if v_estado <> 'Creado' or v_repartidor is not null then
    raise exception 'PEDIDO_NO_DISPONIBLE: Otro domiciliario ya tomó este pedido o ya no está disponible.'
      using errcode = '55000';
  end if;

  -- Creado -> Asignado. El trigger de transiciones valida el cambio y pone actualizado_en.
  update public.pedidos
  set estado = 'Asignado',
      repartidor_id = v_uid
  where id = p_pedido_id
  returning actualizado_en into v_actual;

  return jsonb_build_object(
    'pedido_id',      p_pedido_id,
    'estado',         'Asignado',
    'repartidor_id',  v_uid,
    'actualizado_en', v_actual
  );
end;
$$;

comment on function public.aceptar_pedido(uuid) is
  'T-036 (HU-21). Un domiciliario habilitado toma un pedido Creado sin repartidor (Creado -> Asignado). Atómico frente a otros domiciliarios.';

revoke all on function public.aceptar_pedido(uuid) from public, anon;
grant execute on function public.aceptar_pedido(uuid) to authenticated;

-- ------------------------------------------------------------------------------
-- 2. Confirmar que recogió el pedido en el comercio
-- ------------------------------------------------------------------------------
create or replace function public.confirmar_recogida(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_estado public.estado_pedido;
  v_listo  boolean;
  v_salida timestamptz;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if not public.es_repartidor_habilitado() then
    raise exception 'ROL_NO_PERMITIDO: Solo un domiciliario habilitado puede confirmar recogidas.'
      using errcode = '42501';
  end if;

  select p.estado, p.listo_para_recoger
    into v_estado, v_listo
  from public.pedidos p
  where p.id = p_pedido_id
    and p.repartidor_id = v_uid
  for update;

  if not found then
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no lo tienes asignado.'
      using errcode = 'P0002';
  end if;

  if v_estado <> 'Asignado' then
    raise exception 'ESTADO_NO_PERMITIDO: Solo puedes confirmar la recogida de un pedido Asignado (estado actual: %).', v_estado
      using errcode = '55000';
  end if;

  if v_listo is not true then
    raise exception 'PEDIDO_NO_LISTO: El comercio aún no marca el pedido como listo para recoger.'
      using errcode = '55000';
  end if;

  -- Asignado -> En Camino. El trigger trg_pedidos_marcar_en_camino llena en_camino_en.
  update public.pedidos
  set estado = 'En Camino'
  where id = p_pedido_id
  returning en_camino_en into v_salida;

  return jsonb_build_object(
    'pedido_id',    p_pedido_id,
    'estado',       'En Camino',
    'en_camino_en', v_salida
  );
end;
$$;

comment on function public.confirmar_recogida(uuid) is
  'T-037 (HU-21). El domiciliario asignado confirma que recogió el pedido ya listo (Asignado -> En Camino).';

revoke all on function public.confirmar_recogida(uuid) from public, anon;
grant execute on function public.confirmar_recogida(uuid) to authenticated;
