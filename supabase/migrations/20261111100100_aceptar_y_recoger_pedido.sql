-- ==============================================================================
-- DESKDROP: EL DOMICILIARIO ACEPTA Y RECOGE UN PEDIDO
-- ==============================================================================
--   aceptar_pedido(p_pedido_id)     Creado    -> Asignado   (el repartidor toma el pedido)
--   confirmar_recogida(p_pedido_id) Asignado  -> En Camino  (el repartidor recogió y sale)
--
-- Sin doble asignación: aceptar_pedido bloquea la fila (`for update`) y revisa estado y
-- repartidor_id YA con el bloqueo tomado. Si dos domiciliarios aceptan a la vez, el segundo
-- espera, ve el pedido ya Asignado y recibe PEDIDO_NO_DISPONIBLE. Las transiciones además
-- pasan por el trigger de la matriz (20261107050200), así que nada se salta el orden.
-- La auto-cancelación usa `skip locked`: no cancela un pedido mientras alguien lo acepta.
--
--   supabase.rpc('aceptar_pedido',     { p_pedido_id })  -> { pedido_id, estado, repartidor_id, asignado_en }
--   supabase.rpc('confirmar_recogida', { p_pedido_id })  -> { pedido_id, estado, en_camino_en }
--
-- Errores (error.message empieza por el código):
--   NO_AUTENTICADO        28000  sin sesión
--   ROL_NO_PERMITIDO      42501  quien llama no es repartidor
--   PEDIDO_NO_ENCONTRADO  P0002  no existe (aceptar) / no existe o no es tuyo (recoger)
--   PEDIDO_PROPIO         42501  un repartidor no puede tomar su propio pedido de solicitante
--   PEDIDO_NO_DISPONIBLE  55000  ya lo tomó otro o ya no está en Creado
--   ESTADO_NO_PERMITIDO   55000  confirmar_recogida con el pedido fuera de Asignado
-- ==============================================================================

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
  v_fecha       timestamptz;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if public.mi_rol() is distinct from 'repartidor' then
    raise exception 'ROL_NO_PERMITIDO: Solo un domiciliario puede aceptar pedidos.'
      using errcode = '42501';
  end if;

  -- Bloqueo de la fila: aquí se serializan los domiciliarios que aceptan el mismo pedido.
  select p.estado, p.repartidor_id, p.solicitante_id
    into v_estado, v_repartidor, v_solicitante
  from public.pedidos p
  where p.id = p_pedido_id
  for update;

  if not found then
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe.' using errcode = 'P0002';
  end if;

  if v_solicitante = v_uid then
    raise exception 'PEDIDO_PROPIO: No puedes aceptar tu propio pedido.' using errcode = '42501';
  end if;

  -- Revisado con el bloqueo ya tomado: el perdedor de la carrera cae aquí.
  if v_estado <> 'Creado' or v_repartidor is not null then
    raise exception 'PEDIDO_NO_DISPONIBLE: Este pedido ya no está disponible.' using errcode = '55000';
  end if;

  update public.pedidos
  set repartidor_id = v_uid,
      estado        = 'Asignado'
  where id = p_pedido_id
  returning actualizado_en into v_fecha;

  return jsonb_build_object(
    'pedido_id',     p_pedido_id,
    'estado',        'Asignado',
    'repartidor_id', v_uid,
    'asignado_en',   v_fecha
  );
end;
$$;

comment on function public.aceptar_pedido(uuid) is
  'El domiciliario toma un pedido disponible (Creado -> Asignado) sin posibilidad de doble asignación.';

revoke all on function public.aceptar_pedido(uuid) from public, anon;
grant execute on function public.aceptar_pedido(uuid) to authenticated;

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
  v_en_camino timestamptz;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if public.mi_rol() is distinct from 'repartidor' then
    raise exception 'ROL_NO_PERMITIDO: Solo un domiciliario puede confirmar la recogida.'
      using errcode = '42501';
  end if;

  -- Solo el repartidor asignado; a cualquier otro se le responde que no existe.
  select p.estado
    into v_estado
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

  -- Asignado -> En Camino. El trigger llena en_camino_en (auto-confirmación, T-042).
  update public.pedidos
  set estado = 'En Camino'
  where id = p_pedido_id
  returning en_camino_en into v_en_camino;

  return jsonb_build_object(
    'pedido_id',    p_pedido_id,
    'estado',       'En Camino',
    'en_camino_en', v_en_camino
  );
end;
$$;

comment on function public.confirmar_recogida(uuid) is
  'El domiciliario asignado confirma que recogió el pedido (Asignado -> En Camino).';

revoke all on function public.confirmar_recogida(uuid) from public, anon;
grant execute on function public.confirmar_recogida(uuid) to authenticated;
