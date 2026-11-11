-- ==============================================================================
-- DESKDROP: VISTA DE REPARTIDOR PARA CUALQUIER USUARIO, CON DECLARACIÓN DE +18 (T-078, T-079)
-- ==============================================================================
-- Hasta ahora solo un perfil con rol 'repartidor' (asignado por un admin) podía ver y tomar
-- pedidos. Ahora cualquier solicitante puede cambiar a la vista de repartidor desde Perfil,
-- siempre que haya declarado una vez que tiene 18 años o más.
--
--   * Tabla `aceptaciones_repartidor`: una fila por usuario y versión del texto aceptado,
--     con la hora del servidor. Sin insert/update/delete desde la Data API: solo se escribe
--     con activar_modo_repartidor().
--   * es_repartidor_habilitado(): true si el usuario (rol solicitante o repartidor) ya aceptó.
--     Comercio y admin nunca son repartidores. Es lo que ahora exigen las políticas y las
--     funciones de repartidor, en lugar de `perfiles.rol = 'repartidor'`.
--   * El rol en perfiles.rol de un solicitante NO cambia al activar la vista: por eso
--     crear_pedido sigue igual y el mismo usuario puede pedir y repartir (cierra BUG-19).
--     El rol 'repartidor' queda como valor heredado; ese usuario también debe aceptar.
--
-- Uso desde la app:
--   supabase.rpc('activar_modo_repartidor', { p_acepta_mayor_edad: true, p_version: '1.0' })
--   -> { habilitado: true, version, aceptado_en }
--
-- Errores (error.message empieza por el código):
--   NO_AUTENTICADO 28000, ROL_NO_PERMITIDO 42501, ACEPTACION_REQUERIDA 22023, VERSION_INVALIDA 22023
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Tabla de aceptaciones
-- ------------------------------------------------------------------------------
create table if not exists public.aceptaciones_repartidor (
  usuario_id  uuid        not null default auth.uid()
              references public.perfiles (id) on delete cascade,
  version     text        not null check (length(version) between 1 and 30),
  aceptado_en timestamptz not null default now(),  -- hora del servidor, no la del celular
  primary key (usuario_id, version)
);

comment on table public.aceptaciones_repartidor is
  'T-078. Declaración de mayoría de edad y condiciones del repartidor, una fila por usuario y versión. Solo se escribe con activar_modo_repartidor().';

alter table public.aceptaciones_repartidor enable row level security;

revoke all on public.aceptaciones_repartidor from anon, authenticated;
grant select on public.aceptaciones_repartidor to authenticated;

drop policy if exists ver_mis_aceptaciones_repartidor on public.aceptaciones_repartidor;
create policy ver_mis_aceptaciones_repartidor on public.aceptaciones_repartidor
  for select to authenticated
  using (usuario_id = (select auth.uid()));

drop policy if exists admin_ve_aceptaciones_repartidor on public.aceptaciones_repartidor;
create policy admin_ve_aceptaciones_repartidor on public.aceptaciones_repartidor
  for select to authenticated
  using ((select public.es_admin()));

-- ------------------------------------------------------------------------------
-- 2. ¿El usuario que llama puede actuar como repartidor?
-- ------------------------------------------------------------------------------
create or replace function public.es_repartidor_habilitado() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.mi_rol() in ('solicitante', 'repartidor'), false)
     and exists (
       select 1 from public.aceptaciones_repartidor a
       where a.usuario_id = (select auth.uid())
     )
$$;

comment on function public.es_repartidor_habilitado() is
  'T-078. true si quien llama es solicitante o repartidor y ya aceptó la declaración de +18 (activar_modo_repartidor).';

revoke execute on function public.es_repartidor_habilitado() from public, anon;
grant execute on function public.es_repartidor_habilitado() to authenticated;

-- ------------------------------------------------------------------------------
-- 3. Activar la vista de repartidor (la primera vez, con la declaración)
-- ------------------------------------------------------------------------------
create or replace function public.activar_modo_repartidor(
  p_acepta_mayor_edad boolean,
  p_version           text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_version text := nullif(btrim(p_version), '');
  v_fecha   timestamptz;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if public.mi_rol() is null or public.mi_rol() not in ('solicitante', 'repartidor') then
    raise exception 'ROL_NO_PERMITIDO: Tu cuenta no puede usar la vista de repartidor.'
      using errcode = '42501';
  end if;

  if p_acepta_mayor_edad is not true then
    raise exception 'ACEPTACION_REQUERIDA: Debes declarar que tienes 18 años o más.'
      using errcode = '22023';
  end if;

  if v_version is null or char_length(v_version) > 30 then
    raise exception 'VERSION_INVALIDA: Falta la versión del texto aceptado.'
      using errcode = '22023';
  end if;

  -- Idempotente: repetir la llamada con la misma versión conserva la fecha original.
  insert into public.aceptaciones_repartidor (usuario_id, version)
  values (v_uid, v_version)
  on conflict (usuario_id, version) do nothing;

  select a.aceptado_en
    into v_fecha
  from public.aceptaciones_repartidor a
  where a.usuario_id = v_uid and a.version = v_version;

  return jsonb_build_object(
    'habilitado',  true,
    'version',     v_version,
    'aceptado_en', v_fecha
  );
end;
$$;

comment on function public.activar_modo_repartidor(boolean, text) is
  'T-078 (HU-19). Registra la declaración de +18 y habilita la vista de repartidor. Idempotente.';

revoke all on function public.activar_modo_repartidor(boolean, text) from public, anon;
grant execute on function public.activar_modo_repartidor(boolean, text) to authenticated;

-- ------------------------------------------------------------------------------
-- 4. Pedidos disponibles: ahora los ve cualquier repartidor habilitado (T-079)
-- ------------------------------------------------------------------------------
-- Solicitante: los suyos. Repartidor habilitado: los asignados a él y los disponibles (Creado,
-- sin repartidor). Comercio: los de su comercio. Admin: todos.
drop policy if exists ver_pedidos_por_rol on public.pedidos;
create policy ver_pedidos_por_rol on public.pedidos
  for select to authenticated
  using (
    solicitante_id = (select auth.uid())
    or repartidor_id = (select auth.uid())
    or (
      (select public.es_repartidor_habilitado())
      and estado = 'Creado'
      and repartidor_id is null
    )
    or public.es_dueno_comercio(comercio_id)
    or (select public.es_admin())
  );

-- ------------------------------------------------------------------------------
-- 5. Registrar el cobro en efectivo: exige repartidor habilitado (T-079)
-- ------------------------------------------------------------------------------
create or replace function public.registrar_cobro_efectivo(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := (select auth.uid());
  v_estado      public.estado_pedido;
  v_total       numeric;
  v_estado_pago public.estado_pago;
  v_fecha       timestamptz := now();
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if not public.es_repartidor_habilitado() then
    raise exception 'ROL_NO_PERMITIDO: Solo un repartidor habilitado puede registrar cobros.'
      using errcode = '42501';
  end if;

  select p.estado, p.total
    into v_estado, v_total
  from public.pedidos p
  where p.id = p_pedido_id
    and p.repartidor_id = v_uid
  for update;

  if not found then
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no lo tienes asignado.'
      using errcode = 'P0002';
  end if;

  select g.estado
    into v_estado_pago
  from public.pagos g
  where g.pedido_id = p_pedido_id
  for update;

  if not found then
    raise exception 'PAGO_NO_ENCONTRADO: El pedido no tiene un pago registrado.'
      using errcode = 'XX000';
  end if;

  if v_estado_pago = 'cobrado' then
    raise exception 'PAGO_YA_COBRADO: Este pedido ya fue cobrado.' using errcode = '23505';
  end if;

  if v_estado_pago <> 'pendiente' then
    raise exception 'PAGO_NO_COBRABLE: El pago está en estado %.', v_estado_pago
      using errcode = '55000';
  end if;

  if v_estado <> 'Entregado' then
    raise exception 'ESTADO_NO_PERMITIDO: El cobro se registra cuando el pedido está Entregado (estado actual: %).', v_estado
      using errcode = '55000';
  end if;

  update public.pagos
  set metodo         = 'efectivo',
      monto          = v_total,
      estado         = 'cobrado',
      registrado_por = v_uid,
      fecha_pago     = v_fecha
  where pedido_id = p_pedido_id;

  -- Entregado -> Cerrado: cobro registrado / cierre (matriz de 20261107050200_pedido_estados).
  update public.pedidos
  set estado = 'Cerrado'
  where id = p_pedido_id;

  return jsonb_build_object(
    'pedido_id',     p_pedido_id,
    'estado_pedido', 'Cerrado',
    'estado_pago',   'cobrado',
    'metodo',        'efectivo',
    'monto',         v_total,
    'fecha_pago',    v_fecha
  );
end;
$$;

