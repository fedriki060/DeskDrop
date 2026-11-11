-- ==============================================================================
-- DESKDROP: AUTO-CANCELACIÓN DE PEDIDOS SIN DOMICILIARIO (T-043, RN-003)
-- ==============================================================================
-- Un pedido en estado `Creado` que ningún domiciliario toma dentro del tiempo límite
-- pasa a `Cancelado`. El tiempo límite vive en `configuracion` (clave
-- minutos_auto_cancelacion, 10 min según docs/reglas_negocio_piloto.md, T-014).
--
--   * Un job de pg_cron corre cada minuto. Como compara contra `creado_en` (y no contra
--     la hora del último barrido), si el job se retrasa o se salta corridas, la siguiente
--     cancela todos los pedidos vencidos.
--   * `for update skip locked`: si un domiciliario está aceptando el pedido en ese mismo
--     instante (T-036), el job no lo toca y lo revisa en la siguiente corrida.
--   * El cambio de estado pasa por el trigger de transiciones (20261107050200), así que
--     solo se cancelan pedidos que la matriz permite cancelar.
--   * Reponer el inventario NO se hace aquí: es T-044 (trigger al pasar a `Cancelado`),
--     para que aplique a cualquier cancelación, no solo a la automática.
--
-- Cambiar el tiempo límite:
--   update public.configuracion set valor = 15 where clave = 'minutos_auto_cancelacion';
-- Ver las últimas corridas del job:
--   select status, return_message, start_time from cron.job_run_details
--   where jobid = (select jobid from cron.job where jobname = 'cancelar-pedidos-vencidos')
--   order by start_time desc limit 10;
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Tiempo límite configurable (T-014)
-- ------------------------------------------------------------------------------
insert into public.configuracion (clave, valor, descripcion)
values (
  'minutos_auto_cancelacion',
  10,
  'Minutos que un pedido puede estar en Creado sin domiciliario antes de cancelarse (RN-003, T-014)'
)
on conflict (clave) do nothing;

-- ------------------------------------------------------------------------------
-- 2. Función que cancela los pedidos vencidos
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
  set estado = 'Cancelado'
  from vencidos v
  where p.id = v.id;

  get diagnostics v_cancelados = row_count;
  return v_cancelados;
end;
$$;

comment on function public.cancelar_pedidos_vencidos() is
  'RN-003 (T-043): pasa a Cancelado los pedidos Creados sin domiciliario con más de minutos_auto_cancelacion. Devuelve cuántos canceló. La corre pg_cron cada minuto.';

-- Solo la corre el job (o alguien desde el SQL Editor), nunca la app
revoke execute on function public.cancelar_pedidos_vencidos() from public, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 3. Programarla cada minuto
--    cron.schedule con el mismo nombre reemplaza el job: la migración se puede repetir.
-- ------------------------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'cancelar-pedidos-vencidos',
  '* * * * *',
  'select public.cancelar_pedidos_vencidos()'
);
