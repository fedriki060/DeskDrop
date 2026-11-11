-- ==============================================================================
-- DESKDROP: TELÉFONO DEL USUARIO Y DATOS DE CONTACTO DEL DOMICILIARIO (T-101, T-095)
-- ==============================================================================
--   * perfiles.telefono: cada usuario ya podía editar su teléfono (grant update de columna).
--     Se agrega la validación de formato: celular colombiano, 10 dígitos, empieza por 3
--     (la app guarda solo dígitos). Es NOT VALID para no fallar si hay datos viejos; aplica a
--     toda escritura nueva.
--   * datos_partes_pedido(ids) devuelve ahora también el teléfono y la calificación del
--     domiciliario, SOLO al solicitante dueño del pedido y SOLO mientras el domiciliario está
--     en camino a entregarlo (estados Asignado y En Camino). Al comercio, al propio
--     domiciliario y a cualquier otro usuario les sale null.
--     La calificación es perfiles.calificacion_promedio; hoy no hay flujo de calificaciones,
--     así que la app no la muestra todavía.
--
-- Uso desde la app:
--   supabase.from('perfiles').update({ telefono: '3001234567' }).eq('id', userId)
--   supabase.rpc('datos_partes_pedido', { p_pedido_ids: [...] })
--   -> [{ pedido_id, solicitante, repartidor, repartidor_telefono, repartidor_calificacion }]
-- ==============================================================================

alter table public.perfiles drop constraint if exists perfiles_telefono_formato;
alter table public.perfiles
  add constraint perfiles_telefono_formato
  check (telefono is null or telefono ~ '^3[0-9]{9}$') not valid;

-- Cambia el tipo de retorno: hay que recrear la función
drop function if exists public.datos_partes_pedido(uuid[]);

create function public.datos_partes_pedido(p_pedido_ids uuid[])
returns table (
  pedido_id uuid,
  solicitante text,
  repartidor text,
  repartidor_telefono text,
  repartidor_calificacion numeric
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
              then r.calificacion_promedio::numeric end
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
  'T-030, T-095. Primer nombre del solicitante y del domiciliario de los pedidos donde quien llama es parte. El teléfono y la calificación del domiciliario solo los recibe el solicitante dueño, mientras el pedido está Asignado o En Camino.';

revoke all on function public.datos_partes_pedido(uuid[]) from public, anon;
grant execute on function public.datos_partes_pedido(uuid[]) to authenticated;
