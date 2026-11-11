-- ==============================================================================
-- DESKDROP: CALIFICACIÓN DEL DOMICILIARIO (HU-15: T-064, T-065, T-095)
-- ==============================================================================
--   * La tabla `calificaciones` ya existe desde la migración inicial (una por pedido gracias
--     al UNIQUE sobre pedido_id; estrellas 1..5; comentario opcional) y es de solo lectura para
--     la app: se escribe únicamente con calificar_pedido().
--   * calificar_pedido(pedido, estrellas, comentario): el solicitante dueño califica al
--     domiciliario de un pedido Entregado o Cerrado, una sola vez y dentro del plazo
--     (configuracion.plazo_calificacion_horas, 24 h por defecto, contadas desde la última
--     actualización del pedido). Recalcula perfiles.calificacion_promedio (CU-005).
--   * datos_partes_pedido: la calificación que ve el solicitante pasa a calcularse desde
--     `calificaciones` y es null si el domiciliario todavía no tiene ninguna (antes salía el
--     valor por defecto 5.00 de perfiles).
--
-- NOTA: el pedido NO cambia de estado al calificar. En el flujo actual el pedido pasa a Cerrado
-- cuando el domiciliario registra el cobro en efectivo (registrar_cobro_efectivo), así que
-- calificar es un paso opcional posterior y no hace falta un job de cierre por plazo.
--
-- Uso desde la app:
--   supabase.rpc('calificar_pedido', { p_pedido_id, p_estrellas: 5, p_comentario: 'Muy amable' })
--   -> { ok: true, promedio: 4.5 }
--   supabase.from('calificaciones').select('estrellas').eq('pedido_id', id)   -- ¿ya calificó?
--
-- Errores: NO_AUTENTICADO 28000, ESTRELLAS_INVALIDAS 22023, COMENTARIO_DEMASIADO_LARGO 22023,
--          PEDIDO_NO_ENCONTRADO P0002, ESTADO_NO_PERMITIDO 55000, PLAZO_VENCIDO 55000,
--          YA_CALIFICADO 23505
-- ==============================================================================

insert into public.configuracion (clave, valor, descripcion)
values ('plazo_calificacion_horas', 24, 'Horas que tiene el solicitante para calificar al domiciliario (HU-15)')
on conflict (clave) do nothing;

create or replace function public.calificar_pedido(
  p_pedido_id  uuid,
  p_estrellas  integer,
  p_comentario text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := (select auth.uid());
  v_estado     public.estado_pedido;
  v_repartidor uuid;
  v_ultima     timestamptz;
  v_plazo      numeric;
  v_comentario text := nullif(btrim(p_comentario), '');
  v_promedio   numeric;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if p_estrellas is null or p_estrellas < 1 or p_estrellas > 5 then
    raise exception 'ESTRELLAS_INVALIDAS: La calificación va de 1 a 5 estrellas.' using errcode = '22023';
  end if;

  if length(coalesce(v_comentario, '')) > 300 then
    raise exception 'COMENTARIO_DEMASIADO_LARGO: Máximo 300 caracteres.' using errcode = '22023';
  end if;

  select p.estado, p.repartidor_id, p.actualizado_en
    into v_estado, v_repartidor, v_ultima
  from public.pedidos p
  where p.id = p_pedido_id
    and p.solicitante_id = v_uid
    and p.repartidor_id is not null
  for update;

  if not found then
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no es tuyo.' using errcode = 'P0002';
  end if;

  if v_estado not in ('Entregado', 'Cerrado') then
    raise exception 'ESTADO_NO_PERMITIDO: Solo puedes calificar un pedido ya entregado (estado actual: %).', v_estado
      using errcode = '55000';
  end if;

  select coalesce((select c.valor from public.configuracion c where c.clave = 'plazo_calificacion_horas'), 24)
    into v_plazo;
  if now() > v_ultima + make_interval(hours => v_plazo::int) then
    raise exception 'PLAZO_VENCIDO: Ya pasó el plazo para calificar este pedido.' using errcode = '55000';
  end if;

  begin
    insert into public.calificaciones (pedido_id, repartidor_id, solicitante_id, estrellas, comentario)
    values (p_pedido_id, v_repartidor, v_uid, p_estrellas, v_comentario);
  exception
    when unique_violation then
      raise exception 'YA_CALIFICADO: Ya calificaste este pedido.' using errcode = '23505';
  end;

  select round(avg(c.estrellas)::numeric, 2)
    into v_promedio
  from public.calificaciones c
  where c.repartidor_id = v_repartidor;

  update public.perfiles set calificacion_promedio = v_promedio where id = v_repartidor;

  return jsonb_build_object('ok', true, 'promedio', v_promedio);
end;
$$;

comment on function public.calificar_pedido(uuid, integer, text) is
  'HU-15, T-065. El solicitante dueño califica (1 a 5) al domiciliario de un pedido Entregado o Cerrado, una vez y dentro del plazo; recalcula el promedio del domiciliario.';

revoke all on function public.calificar_pedido(uuid, integer, text) from public, anon;
grant execute on function public.calificar_pedido(uuid, integer, text) to authenticated;

-- La calificación que ve el solicitante sale de las calificaciones reales (null si no hay)
create or replace function public.datos_partes_pedido(p_pedido_ids uuid[])
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
              then (select round(avg(c.estrellas)::numeric, 1)
                    from public.calificaciones c where c.repartidor_id = r.id) end
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

revoke all on function public.datos_partes_pedido(uuid[]) from public, anon;
grant execute on function public.datos_partes_pedido(uuid[]) to authenticated;
