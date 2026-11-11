-- ==============================================================================
-- DESKDROP: CELULAR DEL SOLICITANTE PARA EL DOMICILIARIO (T-095)
-- ==============================================================================
-- datos_partes_pedido(ids) devuelve ahora también `solicitante_telefono`, SOLO al domiciliario
-- asignado y SOLO mientras tiene el pedido en su poder (Asignado, En Camino o Entregado a la
-- espera del cobro). Así los dos pueden contactarse al momento de la entrega:
--   * el solicitante ve el celular del domiciliario (Asignado y En Camino),
--   * el domiciliario ve el del solicitante (Asignado, En Camino y Entregado).
-- El comercio, un domiciliario que no tomó el pedido y cualquier otro usuario reciben null.
-- ==============================================================================

drop function if exists public.datos_partes_pedido(uuid[]);

create function public.datos_partes_pedido(p_pedido_ids uuid[])
returns table (
  pedido_id uuid,
  solicitante text,
  repartidor text,
  repartidor_telefono text,
  repartidor_calificacion numeric,
  solicitante_telefono text
)
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
         split_part(btrim(r.nombre_completo), ' ', 1),
         case when p.solicitante_id = v_uid and p.estado in ('Asignado', 'En Camino')
              then r.telefono::text end,
         case when p.solicitante_id = v_uid and p.estado in ('Asignado', 'En Camino')
              then (select round(avg(c.estrellas)::numeric, 1)
                    from public.calificaciones c where c.repartidor_id = r.id) end,
         case when p.repartidor_id = v_uid and p.estado in ('Asignado', 'En Camino', 'Entregado')
              then s.telefono::text end
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
  'T-030, T-095. Primer nombre de las partes de los pedidos donde quien llama es parte. El celular y la calificación del domiciliario solo los recibe el solicitante dueño (Asignado y En Camino); el celular del solicitante solo lo recibe el domiciliario asignado (Asignado, En Camino y Entregado).';

revoke all on function public.datos_partes_pedido(uuid[]) from public, anon;
grant execute on function public.datos_partes_pedido(uuid[]) to authenticated;
