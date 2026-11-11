-- ==============================================================================
-- DESKDROP: CANCELAR O RECHAZAR UN PEDIDO Y REPONER EL INVENTARIO (T-044, T-102)
-- ==============================================================================
--   * T-044: un trigger repone el inventario cada vez que un pedido pasa a Cancelado, sin
--     importar quién lo cancele (solicitante, comercio o el job de auto-cancelación). Corre en
--     la misma transacción que el cambio de estado: o se cancela y se repone, o ninguna.
--   * T-102: cancelar_pedido(pedido, motivo): el solicitante dueño ("Cancelar pedido") o el
--     dueño del comercio ("Rechazar pedido") lo cancelan mientras esté Creado o Asignado. Un
--     pedido En Camino o posterior no se cancela. El domiciliario no puede cancelar.
--   * Se guarda quién canceló (`cancelado_por`: solicitante, comercio o sistema) y el motivo,
--     para mostrarlos en el seguimiento y el historial.
--
-- Uso desde la app:
--   supabase.rpc('cancelar_pedido', { p_pedido_id, p_motivo: 'Sin inventario' })
--   -> { pedido_id, estado: 'Cancelado', cancelado_por: 'solicitante' | 'comercio' }
--
-- Errores (error.message empieza por el código):
--   NO_AUTENTICADO 28000, PEDIDO_NO_ENCONTRADO P0002, ESTADO_NO_PERMITIDO 55000,
--   MOTIVO_INVALIDO 22023 (más de 200 caracteres)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Quién canceló y por qué
-- ------------------------------------------------------------------------------
alter table public.pedidos
  add column if not exists cancelado_por text
    check (cancelado_por in ('solicitante', 'comercio', 'sistema')),
  add column if not exists motivo_cancelacion text
    check (char_length(motivo_cancelacion) <= 200);

comment on column public.pedidos.cancelado_por is
  'T-102. Quién canceló el pedido: solicitante, comercio o sistema (auto-cancelación). null si no está cancelado.';
comment on column public.pedidos.motivo_cancelacion is
  'T-102. Motivo opcional de la cancelación (máximo 200 caracteres).';

-- ------------------------------------------------------------------------------
-- 2. Reponer el inventario al cancelar (T-044)
-- ------------------------------------------------------------------------------
create or replace function public.trg_pedidos_reponer_inventario()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.productos p
  set inventario_disponible = p.inventario_disponible + i.cantidad
  from (
    select ip.producto_id, sum(ip.cantidad)::int as cantidad
    from public.items_pedido ip
    where ip.pedido_id = new.id
    group by ip.producto_id
  ) i
  where p.id = i.producto_id;
  return new;
end;
$$;

revoke all on function public.trg_pedidos_reponer_inventario() from public, anon, authenticated;

drop trigger if exists trg_pedidos_reponer_inventario on public.pedidos;
create trigger trg_pedidos_reponer_inventario
  after update of estado on public.pedidos
  for each row
  when (new.estado = 'Cancelado' and old.estado is distinct from 'Cancelado')
  execute function public.trg_pedidos_reponer_inventario();

-- ------------------------------------------------------------------------------
-- 3. Cancelar o rechazar un pedido (T-102)
-- ------------------------------------------------------------------------------
create or replace function public.cancelar_pedido(p_pedido_id uuid, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := (select auth.uid());
  v_motivo      text := nullif(btrim(p_motivo), '');
  v_estado      public.estado_pedido;
  v_solicitante uuid;
  v_comercio    uuid;
  v_quien       text;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if v_motivo is not null and char_length(v_motivo) > 200 then
    raise exception 'MOTIVO_INVALIDO: El motivo puede tener máximo 200 caracteres.' using errcode = '22023';
  end if;

  select p.estado, p.solicitante_id, p.comercio_id
    into v_estado, v_solicitante, v_comercio
  from public.pedidos p
  where p.id = p_pedido_id
  for update;

  -- Solo el solicitante dueño o el dueño del comercio; cualquier otro recibe lo mismo que si no existiera
  if not found or not (v_solicitante = v_uid or public.es_dueno_comercio(v_comercio)) then
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es tuyo.' using errcode = 'P0002';
  end if;

  if v_estado not in ('Creado', 'Asignado') then
    raise exception 'ESTADO_NO_PERMITIDO: Solo puedes cancelar un pedido Creado o Asignado (estado actual: %).', v_estado
      using errcode = '55000';
  end if;

  v_quien := case when v_solicitante = v_uid then 'solicitante' else 'comercio' end;

  -- Creado/Asignado -> Cancelado. El trigger valida la transición y repone el inventario.
  update public.pedidos
  set estado = 'Cancelado',
      cancelado_por = v_quien,
      motivo_cancelacion = v_motivo
  where id = p_pedido_id;

  return jsonb_build_object(
    'pedido_id',     p_pedido_id,
    'estado',        'Cancelado',
    'cancelado_por', v_quien
  );
end;
$$;

comment on function public.cancelar_pedido(uuid, text) is
  'T-102 (HU-24). El solicitante dueño o el dueño del comercio cancelan un pedido Creado o Asignado; repone el inventario.';

revoke all on function public.cancelar_pedido(uuid, text) from public, anon;
grant execute on function public.cancelar_pedido(uuid, text) to authenticated;

-- ------------------------------------------------------------------------------
-- 4. La auto-cancelación deja constancia de que la hizo el sistema
-- ------------------------------------------------------------------------------
create or replace function public.cancelar_pedidos_vencidos()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_minutos    numeric;
  v_cancelados integer;
begin
  select valor into v_minutos
  from public.configuracion
  where clave = 'minutos_auto_cancelacion';

  -- Falla cerrado: sin un tiempo válido no se cancela nada y la corrida queda como
  -- fallida en cron.job_run_details.
  if v_minutos is null or v_minutos <= 0 then
    raise exception 'CONFIG_FALTANTE: falta un valor mayor que 0 para minutos_auto_cancelacion en configuracion.';
  end if;

  with vencidos as (
    select p.id
    from public.pedidos p
    where p.estado = 'Creado'
      and p.repartidor_id is null
      and p.creado_en <= now() - make_interval(secs => (v_minutos * 60)::double precision)
    for update skip locked
  )
  update public.pedidos p
  set estado = 'Cancelado',
      cancelado_por = 'sistema',
      motivo_cancelacion = 'Ningún domiciliario tomó el pedido a tiempo'
  from vencidos v
  where p.id = v.id;

  get diagnostics v_cancelados = row_count;
  return v_cancelados;
end;
$$;
