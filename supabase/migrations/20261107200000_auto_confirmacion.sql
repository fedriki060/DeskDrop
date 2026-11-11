-- ==============================================================================
-- DESKDROP: AUTO-CONFIRMACIÓN DE ENTREGA (T-042)
-- ==============================================================================
-- Si el solicitante no presiona "Ya recibí mi pedido" (confirmar_recepcion, T-040), el
-- sistema asume entrega conforme cuando el pedido lleva el tiempo límite En Camino y lo pasa
-- a `Entregado` (docs/reglas_negocio_piloto.md: 15 minutos, T-014).
--
--   * Nueva columna `pedidos.en_camino_en`: un trigger la llena en el momento en que el
--     pedido pasa a `En Camino`, sin importar qué función haga el cambio (confirmar_recogida,
--     T-036). El tiempo se cuenta desde ahí y no desde `actualizado_en`, que cambia con
--     cualquier actualización del pedido.
--   * Un job de pg_cron corre cada minuto. Como compara contra `en_camino_en`, si el job se
--     retrasa la siguiente corrida confirma todos los pedidos vencidos.
--   * `for update skip locked`: si el solicitante está confirmando en ese mismo instante, el
--     job no toca el pedido; el segundo en llegar ve el estado ya cambiado.
--   * Con el pedido Entregado, el repartidor ya puede registrar el cobro (T-031).
--
-- Cambiar el tiempo límite:
--   update public.configuracion set valor = 20 where clave = 'minutos_auto_confirmacion';
-- Ver las últimas corridas del job:
--   select status, return_message, start_time from cron.job_run_details
--   where jobid = (select jobid from cron.job where jobname = 'confirmar-entregas-vencidas')
--   order by start_time desc limit 10;
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Cuándo salió el pedido (En Camino)
-- ------------------------------------------------------------------------------
alter table public.pedidos
  add column if not exists en_camino_en timestamptz;

comment on column public.pedidos.en_camino_en is
  'Momento en que el pedido pasó a En Camino. Lo llena el trigger trg_pedidos_marcar_en_camino; lo usa la auto-confirmación (T-042).';

-- Pedidos que ya estaban En Camino antes de esta migración: la mejor estimación es su
-- última actualización.
update public.pedidos
set en_camino_en = actualizado_en
where estado = 'En Camino' and en_camino_en is null;

create or replace function public.trg_pedidos_marcar_en_camino()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.estado = 'En Camino' and old.estado is distinct from 'En Camino' then
    new.en_camino_en := now();
  end if;
  return new;
end;
$$;

revoke all on function public.trg_pedidos_marcar_en_camino() from public, anon, authenticated;

drop trigger if exists trg_pedidos_marcar_en_camino on public.pedidos;
create trigger trg_pedidos_marcar_en_camino
  before update of estado on public.pedidos
  for each row
  execute function public.trg_pedidos_marcar_en_camino();

-- Barrido del job: pedidos En Camino ordenados por la hora de salida
create index if not exists idx_pedidos_en_camino_en
  on public.pedidos (en_camino_en)
  where estado = 'En Camino';

-- ------------------------------------------------------------------------------
-- 2. Tiempo límite configurable (T-014)
-- ------------------------------------------------------------------------------
insert into public.configuracion (clave, valor, descripcion)
values (
  'minutos_auto_confirmacion',
  15,
  'Minutos que un pedido puede estar En Camino antes de darse por entregado si el solicitante no confirma (T-014)'
)
on conflict (clave) do nothing;

-- ------------------------------------------------------------------------------
-- 3. Función que confirma las entregas vencidas
-- ------------------------------------------------------------------------------
create or replace function public.confirmar_entregas_vencidas()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_minutos     numeric;
  v_confirmados integer;
begin
  select valor into v_minutos
  from public.configuracion
  where clave = 'minutos_auto_confirmacion';

  -- Falla cerrado: sin un tiempo válido no se confirma nada y la corrida queda como
  -- fallida en cron.job_run_details.
  if v_minutos is null or v_minutos <= 0 then
    raise exception 'CONFIG_FALTANTE: falta un valor mayor que 0 para minutos_auto_confirmacion en configuracion.';
  end if;

  with vencidos as (
    select p.id
    from public.pedidos p
    where p.estado = 'En Camino'
      and p.en_camino_en <= now() - make_interval(secs => (v_minutos * 60)::double precision)
    for update skip locked
  )
  update public.pedidos p
  set estado = 'Entregado'
  from vencidos v
  where p.id = v.id;

  get diagnostics v_confirmados = row_count;
  return v_confirmados;
end;
$$;

comment on function public.confirmar_entregas_vencidas() is
  'T-042: pasa a Entregado los pedidos con más de minutos_auto_confirmacion En Camino sin confirmación del solicitante. Devuelve cuántos confirmó. La corre pg_cron cada minuto.';

-- Solo la corre el job (o alguien desde el SQL Editor), nunca la app
revoke execute on function public.confirmar_entregas_vencidas() from public, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 4. Programarla cada minuto
--    cron.schedule con el mismo nombre reemplaza el job: la migración se puede repetir.
-- ------------------------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'confirmar-entregas-vencidas',
  '* * * * *',
  'select public.confirmar_entregas_vencidas()'
);
