-- ==============================================================================
-- DESKDROP: UNA ENTREGA A LA VEZ, REGENERAR CÓDIGO Y AUTO-CONFIRMACIÓN MÁS LARGA (T-084, T-088, T-089)
-- ==============================================================================
--   * T-084: un domiciliario solo puede tener una entrega Asignada o En Camino a la vez. Lo
--     garantiza un índice único parcial (aunque dos aceptaciones lleguen al mismo tiempo) y
--     aceptar_pedido responde ENTREGA_EN_CURSO antes de chocar con el índice.
--   * T-088: regenerar_codigo_entrega(pedido): el solicitante dueño pide un código nuevo (por
--     ejemplo si se lo vio otra persona o se agotaron los intentos); los intentos vuelven a 0.
--   * T-089: con el código de entrega, la auto-confirmación deja de ser el camino normal sino
--     la red de seguridad: pasa de 15 a 60 minutos (sigue siendo configurable).
--
-- Errores nuevos: ENTREGA_EN_CURSO 55000 (aceptar_pedido), y en regenerar_codigo_entrega:
--   NO_AUTENTICADO 28000, PEDIDO_NO_ENCONTRADO P0002, ESTADO_NO_PERMITIDO 55000
-- Uso: supabase.rpc('regenerar_codigo_entrega', { p_pedido_id }) -> { pedido_id, codigo }
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Una entrega a la vez por domiciliario (T-084)
-- ------------------------------------------------------------------------------
create unique index if not exists idx_una_entrega_activa_por_repartidor
  on public.pedidos (repartidor_id)
  where estado in ('Asignado', 'En Camino');

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

  if exists (
    select 1 from public.pedidos p
    where p.repartidor_id = v_uid and p.estado in ('Asignado', 'En Camino')
  ) then
    raise exception 'ENTREGA_EN_CURSO: Termina tu entrega actual antes de aceptar otro pedido.'
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

-- ------------------------------------------------------------------------------
-- 2. Regenerar el código de entrega (T-088)
-- ------------------------------------------------------------------------------
create or replace function public.regenerar_codigo_entrega(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_estado public.estado_pedido;
  v_codigo text;
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
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es tuyo.' using errcode = 'P0002';
  end if;

  if v_estado not in ('Creado', 'Asignado', 'En Camino') then
    raise exception 'ESTADO_NO_PERMITIDO: Solo puedes cambiar el código de un pedido en curso (estado actual: %).', v_estado
      using errcode = '55000';
  end if;

  v_codigo := lpad((floor(random() * 10000))::int::text, 4, '0');

  update public.codigos_entrega
  set codigo = v_codigo,
      intentos_fallidos = 0
  where pedido_id = p_pedido_id;

  return jsonb_build_object('pedido_id', p_pedido_id, 'codigo', v_codigo);
end;
$$;

comment on function public.regenerar_codigo_entrega(uuid) is
  'T-088 (HU-20). El solicitante dueño genera un código de entrega nuevo y reinicia los intentos fallidos.';

revoke all on function public.regenerar_codigo_entrega(uuid) from public, anon;
grant execute on function public.regenerar_codigo_entrega(uuid) to authenticated;

-- ------------------------------------------------------------------------------
-- 3. Auto-confirmación como red de seguridad: 60 minutos (T-089)
-- ------------------------------------------------------------------------------
update public.configuracion
set valor = 60,
    descripcion = 'Minutos que un pedido puede estar En Camino antes de darse por entregado si el domiciliario no digita el código (T-089)'
where clave = 'minutos_auto_confirmacion';
