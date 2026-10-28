-- ==============================================================================
-- DESKDROP: COBERTURA DEL CAMPUS (RN-002) + RN-001 BLINDADA EN crear_pedido
-- ==============================================================================
-- RN-002 (docs/zonas_campus_piloto.md §1): un pedido solo se entrega dentro del polígono
-- del campus EIA. El polígono vive en la tabla `cobertura_campus` (configurable sin
-- tocar código) y `crear_pedido` lo consulta con el punto de entrega elegido.
--
--   * Convención del polígono: x = longitud, y = latitud (tipo nativo `polygon`, sin PostGIS).
--   * El borde cuenta como dentro (operador `<@`).
--   * Falla cerrado: si no hay ningún polígono activo, no se crean pedidos.
--   * Varios polígonos activos = unión de áreas (basta estar dentro de uno).
--
-- RN-001 (un pedido activo por usuario): el índice único parcial
-- `idx_un_pedido_activo_por_usuario` ya existe desde la migración inicial; aquí solo se
-- reafirma de forma idempotente. La garantía bajo concurrencia es el índice; la
-- comprobación previa de crear_pedido únicamente da un error más claro.
--
-- Nuevos errores de crear_pedido (error.message empieza por el código):
--   FUERA_DE_COBERTURA, COBERTURA_NO_CONFIGURADA
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Polígono configurado
-- ------------------------------------------------------------------------------
create table if not exists public.cobertura_campus (
  id        uuid primary key default gen_random_uuid(),
  nombre    varchar(100) not null unique,
  poligono  polygon not null,                      -- x = longitud, y = latitud
  activo    boolean not null default true,
  creado_en timestamptz default now(),
  constraint cobertura_campus_poligono_valido check (npoints(poligono) >= 3)
);

comment on table public.cobertura_campus is
  'RN-002. Polígonos de cobertura (x = longitud, y = latitud). crear_pedido rechaza puntos fuera de los polígonos activos.';

-- Solo lo leen funciones SECURITY DEFINER: RLS activo y sin acceso desde la Data API.
alter table public.cobertura_campus enable row level security;
revoke all on public.cobertura_campus from anon, authenticated;

-- Vértices oficiales de docs/zonas_campus_piloto.md (V1 NO, V2 NE, V3 SE, V4 SO).
insert into public.cobertura_campus (nombre, poligono)
values (
  'Campus EIA - Sede Las Palmas',
  polygon '((-75.568500,6.169000),(-75.564500,6.169000),(-75.564500,6.164500),(-75.568500,6.164500))'
)
on conflict (nombre) do nothing;

-- ------------------------------------------------------------------------------
-- 2. ¿Un punto cae dentro de la cobertura? (interna, la usa crear_pedido)
-- ------------------------------------------------------------------------------
create or replace function public._punto_en_cobertura(p_latitud numeric, p_longitud numeric)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.cobertura_campus c
    where c.activo is true
      and point(p_longitud::float8, p_latitud::float8) <@ c.poligono
  )
$$;

comment on function public._punto_en_cobertura(numeric, numeric) is
  'RN-002. true si (latitud, longitud) está dentro o sobre el borde de algún polígono activo de cobertura_campus.';

revoke all on function public._punto_en_cobertura(numeric, numeric) from public, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 3. RN-001: índice único parcial (idempotente; ya lo crea la migración inicial)
-- ------------------------------------------------------------------------------
create unique index if not exists idx_un_pedido_activo_por_usuario
  on public.pedidos (solicitante_id)
  where estado in ('Creado', 'Asignado', 'En Camino');

-- ------------------------------------------------------------------------------
-- 4. crear_pedido con validación de cobertura (RN-002)
-- ------------------------------------------------------------------------------
create or replace function public.crear_pedido(
  p_punto_entrega_id uuid,
  p_items            jsonb,
  p_notas_entrega    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_notas constant int := 500;

  v_uid       uuid := (select auth.uid());
  v_rol       public.rol_usuario;
  v_notas     text := nullif(btrim(p_notas_entrega), '');
  v_eval      jsonb;
  v_pedido_id uuid;
  v_creado_en timestamptz;
  v_filas     int;
  v_latitud   numeric;
  v_longitud  numeric;
begin
  -- ---- Quién llama --------------------------------------------------------------
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  select rol into v_rol from public.perfiles where id = v_uid;
  if v_rol is distinct from 'solicitante' then
    raise exception 'ROL_NO_PERMITIDO: Solo un solicitante puede crear pedidos.'
      using errcode = '42501';
  end if;

  -- ---- Punto de entrega (ADR 002): predefinido y activo ---------------------------
  select pe.latitud, pe.longitud
    into v_latitud, v_longitud
  from public.puntos_entrega pe
  join public.zonas_campus z on z.id = pe.zona_id
  where pe.id = p_punto_entrega_id
    and pe.activo is true
    and z.activo is true;
  if not found then
    raise exception 'PUNTO_ENTREGA_INVALIDO: El punto de entrega no existe o no está activo.'
      using errcode = '22023';
  end if;

  -- ---- Cobertura (RN-002): el punto debe caer dentro del polígono configurado ------
  -- Se falla cerrado: sin polígono activo no se aceptan pedidos.
  if not exists (select 1 from public.cobertura_campus where activo is true) then
    raise exception 'COBERTURA_NO_CONFIGURADA: No hay un polígono de cobertura activo.'
      using errcode = '55000';
  end if;

  if not public._punto_en_cobertura(v_latitud, v_longitud) then
    raise exception 'FUERA_DE_COBERTURA: El punto de entrega está fuera del campus.'
      using errcode = '22023';
  end if;

  if char_length(v_notas) > c_max_notas then
    raise exception 'NOTAS_DEMASIADO_LARGAS: Las indicaciones admiten máximo % caracteres.', c_max_notas
      using errcode = '22001';
  end if;

  -- ---- Un solo pedido activo por usuario (comprobación previa; la garantía es el índice) --
  perform 1
  from public.pedidos
  where solicitante_id = v_uid
    and estado in ('Creado', 'Asignado', 'En Camino');
  if found then
    raise exception 'PEDIDO_ACTIVO_EXISTENTE: Ya tienes un pedido en curso.'
      using errcode = '23505';
  end if;

  -- ---- Carrito: inventario y un solo comercio, con bloqueo de filas ---------------
  v_eval := public._evaluar_carrito(p_items, true);
  if not (v_eval ->> 'valido')::boolean then
    raise exception 'CARRITO_INVALIDO: %', v_eval -> 'errores' -> 0 ->> 'mensaje'
      using errcode = '22023',
            detail  = (v_eval -> 'errores')::text;
  end if;

  -- ---- Pedido (total = SUM(precio * cantidad) + tarifa, T-032) --------------------
  begin
    insert into public.pedidos (
      solicitante_id, comercio_id, punto_entrega_id,
      subtotal, tarifa_domicilio, total, notas_entrega
    )
    values (
      v_uid,
      (v_eval ->> 'comercio_id')::uuid,
      p_punto_entrega_id,
      (v_eval ->> 'subtotal')::numeric,
      (v_eval ->> 'tarifa_domicilio')::numeric,
      (v_eval ->> 'total')::numeric,
      v_notas
    )
    returning id, creado_en into v_pedido_id, v_creado_en;
  exception
    when unique_violation then
      -- Otra solicitud simultánea del mismo usuario ganó la carrera.
      raise exception 'PEDIDO_ACTIVO_EXISTENTE: Ya tienes un pedido en curso.'
        using errcode = '23505';
  end;

  -- ---- Ítems con el precio vigente "congelado" ------------------------------------
  insert into public.items_pedido (pedido_id, producto_id, cantidad, precio_unitario)
  select v_pedido_id,
         (i ->> 'producto_id')::uuid,
         (i ->> 'cantidad')::int,
         (i ->> 'precio_unitario')::numeric
  from jsonb_array_elements(v_eval -> 'items') i;

  -- ---- Descuento de inventario ------------------------------------------------------
  -- El CHECK (inventario_disponible >= 0) de la tabla es la red de seguridad final.
  update public.productos p
  set inventario_disponible = p.inventario_disponible - x.cantidad
  from (
    select (i ->> 'producto_id')::uuid as producto_id,
           (i ->> 'cantidad')::int     as cantidad
    from jsonb_array_elements(v_eval -> 'items') i
  ) x
  where p.id = x.producto_id;

  get diagnostics v_filas = row_count;
  if v_filas <> jsonb_array_length(v_eval -> 'items') then
    raise exception 'INVENTARIO_INCONSISTENTE: No se pudo descontar el inventario.'
      using errcode = 'XX000';
  end if;

  return jsonb_build_object(
    'pedido_id',        v_pedido_id,
    'estado',           'Creado',
    'comercio_id',      v_eval -> 'comercio_id',
    'punto_entrega_id', p_punto_entrega_id,
    'items',            v_eval -> 'items',
    'subtotal',         v_eval -> 'subtotal',
    'tarifa_domicilio', v_eval -> 'tarifa_domicilio',
    'total',            v_eval -> 'total',
    'notas_entrega',    v_notas,
    'creado_en',        v_creado_en
  );
end;
$$;

comment on function public.crear_pedido(uuid, jsonb, text) is
  'RF-001/CU-001. Crea el pedido (estado Creado) y descuenta inventario en una sola transacción. Devuelve el pedido como jsonb.';

revoke all on function public.crear_pedido(uuid, jsonb, text) from public, anon;
grant execute on function public.crear_pedido(uuid, jsonb, text) to authenticated;
