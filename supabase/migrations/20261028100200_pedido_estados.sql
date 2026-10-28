-- ==============================================================================
-- DESKDROP: MODELO DE PEDIDO — ESTADOS Y TRANSICIONES
-- ==============================================================================
-- El enum `estado_pedido` y las tablas `pedidos` / `items_pedido` ya existen desde la
-- migración inicial (T-007). Aquí se agrega lo que faltaba:
--   * La matriz de transiciones permitidas y un trigger que la hace cumplir.
--   * Mantenimiento de `actualizado_en` (lo usan la auto-confirmación y el piloto).
--   * Coherencia del total, índices y lectura protegida por RLS.
--
-- Máquina de estados:
--
--   Creado ──► Asignado ──► En Camino ──► Entregado ──► Cerrado
--     │           │
--     └───────────┴──────► Cancelado
--
--   Creado    → Asignado   un repartidor toma el pedido
--   Creado    → Cancelado  auto-cancelación a los 10 min sin repartidor (RN-003) o cancelación
--   Asignado  → En Camino  el repartidor recoge y sale
--   Asignado  → Cancelado  (supuesto) se cancela antes de salir; ver nota en docs/adr/003
--   En Camino → Entregado  el solicitante confirma o auto-confirmación a los 15 min
--   Entregado → Cerrado    cobro registrado / cierre
--   Cancelado y Cerrado son finales: no tienen transiciones de salida.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Función que valida una transición
-- ------------------------------------------------------------------------------
create or replace function public.transicion_pedido_permitida(
  p_desde public.estado_pedido,
  p_hasta public.estado_pedido
)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case p_desde
    when 'Creado'    then p_hasta in ('Asignado', 'Cancelado')
    when 'Asignado'  then p_hasta in ('En Camino', 'Cancelado')
    when 'En Camino' then p_hasta = 'Entregado'
    when 'Entregado' then p_hasta = 'Cerrado'
    else false  -- Cancelado y Cerrado son estados finales
  end
$$;

comment on function public.transicion_pedido_permitida(public.estado_pedido, public.estado_pedido) is
  'true si el pedido puede pasar de p_desde a p_hasta. Un estado igual a sí mismo no es una transición.';

revoke all on function public.transicion_pedido_permitida(public.estado_pedido, public.estado_pedido)
  from public, anon;
grant execute on function public.transicion_pedido_permitida(public.estado_pedido, public.estado_pedido)
  to authenticated;

-- ------------------------------------------------------------------------------
-- 2. Trigger: nadie (ni pg_cron ni service_role) puede saltarse la matriz
-- ------------------------------------------------------------------------------
create or replace function public.trg_pedidos_validar_transicion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.estado is distinct from old.estado
     and not public.transicion_pedido_permitida(old.estado, new.estado) then
    raise exception 'TRANSICION_INVALIDA: no se puede pasar de "%" a "%".', old.estado, new.estado
      using errcode = '23514',
            hint = 'Revisa la matriz de transiciones en la migración 20261028100200_pedido_estados.sql.';
  end if;

  new.actualizado_en := now();
  return new;
end;
$$;

revoke all on function public.trg_pedidos_validar_transicion() from public, anon, authenticated;

create trigger trg_pedidos_validar_transicion
  before update on public.pedidos
  for each row
  execute function public.trg_pedidos_validar_transicion();

-- ------------------------------------------------------------------------------
-- 3. Integridad del modelo
-- ------------------------------------------------------------------------------
alter table public.pedidos
  add constraint pedidos_total_coherente check (total = subtotal + tarifa_domicilio);

-- Historial del solicitante, vistas del comercio, barridos de pg_cron (auto-cancelar /
-- auto-confirmar filtran por estado y fecha) y lectura de ítems por pedido.
create index if not exists idx_pedidos_solicitante_creado
  on public.pedidos (solicitante_id, creado_en desc);

create index if not exists idx_pedidos_comercio_id
  on public.pedidos (comercio_id);

create index if not exists idx_pedidos_estado_creado
  on public.pedidos (estado, creado_en);

create index if not exists idx_items_pedido_pedido_id
  on public.items_pedido (pedido_id);

-- ------------------------------------------------------------------------------
-- 4. Lectura protegida por RLS (la escritura solo ocurre por funciones SQL)
-- ------------------------------------------------------------------------------
grant select on public.pedidos, public.items_pedido to authenticated;

create policy pedidos_lectura
  on public.pedidos
  for select
  to authenticated
  using (
    solicitante_id = (select auth.uid())
    or repartidor_id = (select auth.uid())
    or exists (
      select 1
      from public.comercios c
      where c.id = pedidos.comercio_id
        and c.administrador_id = (select auth.uid())
    )
  );

-- Un ítem es visible si lo es su pedido (la subconsulta aplica la RLS de pedidos).
create policy items_pedido_lectura
  on public.items_pedido
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.pedidos p
      where p.id = items_pedido.pedido_id
    )
  );
