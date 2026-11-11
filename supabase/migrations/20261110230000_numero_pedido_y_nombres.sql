-- ==============================================================================
-- DESKDROP: BANDEJA REAL DEL COMERCIO — NÚMERO DE PEDIDO Y NOMBRES (T-097, T-030)
-- ==============================================================================
--   * `pedidos.numero`: número corto y legible ("Pedido #1042") que se asigna solo. El id (uuid)
--     sigue siendo la llave; el número es para que el comercio y el domiciliario se entiendan.
--   * datos_partes_pedido(ids): devuelve el primer nombre del solicitante y del domiciliario de
--     cada pedido, porque `perfiles` solo deja leer el perfil propio (RLS). Solo responde por los
--     pedidos donde quien llama es parte:
--       - el solicitante dueño del pedido,
--       - el domiciliario asignado,
--       - el administrador del comercio del pedido (y el admin).
--     Un domiciliario NO ve el nombre del solicitante de un pedido que aún no aceptó.
--
-- Uso desde la app:
--   supabase.rpc('datos_partes_pedido', { p_pedido_ids: ['uuid', ...] })
--   -> [{ pedido_id, solicitante: 'Ana', repartidor: 'Carlos' | null }]
--
-- Errores: NO_AUTENTICADO 28000, DEMASIADOS_PEDIDOS 22023 (más de 100 ids)
-- ==============================================================================

alter table public.pedidos
  add column if not exists numero bigint generated always as identity (start with 1001);

create unique index if not exists idx_pedidos_numero on public.pedidos (numero);

comment on column public.pedidos.numero is
  'T-097. Número corto y legible del pedido, asignado solo. Se muestra como #numero.';

create or replace function public.datos_partes_pedido(p_pedido_ids uuid[])
returns table (pedido_id uuid, solicitante text, repartidor text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if coalesce(cardinality(p_pedido_ids), 0) > 100 then
    raise exception 'DEMASIADOS_PEDIDOS: Máximo 100 pedidos por consulta.' using errcode = '22023';
  end if;

  return query
  select p.id,
         split_part(btrim(s.nombre_completo), ' ', 1),
         split_part(btrim(r.nombre_completo), ' ', 1)
  from public.pedidos p
  join public.perfiles s on s.id = p.solicitante_id
  left join public.perfiles r on r.id = p.repartidor_id
  where p.id = any (p_pedido_ids)
    and (
      p.solicitante_id = v_uid
      or p.repartidor_id = v_uid
      or public.es_dueno_comercio(p.comercio_id)
      or public.es_admin()
    );
end;
$$;

comment on function public.datos_partes_pedido(uuid[]) is
  'T-030. Primer nombre del solicitante y del domiciliario de los pedidos donde quien llama es parte (solicitante, domiciliario asignado, dueño del comercio o admin).';

revoke all on function public.datos_partes_pedido(uuid[]) from public, anon;
grant execute on function public.datos_partes_pedido(uuid[]) to authenticated;
