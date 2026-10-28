-- ==============================================================================
-- DESKDROP: CREAR PEDIDO (RF-001 / CU-001)
-- ==============================================================================
-- Crea el pedido con ID único (UUID) y descuenta el inventario de forma atómica.
--
-- Atomicidad: una función PL/pgSQL corre dentro de una única transacción. Si cualquier
-- paso falla (inventario, punto de entrega, pedido activo, CHECK de inventario >= 0),
-- se revierte TODO: no queda pedido a medias ni inventario descontado.
--
-- Concurrencia:
--   * Inventario: _evaluar_carrito(..., true) bloquea las filas de productos en orden de id
--     (FOR UPDATE). Dos pedidos simultáneos por la última unidad se serializan: el segundo
--     espera, lee el inventario ya descontado y recibe INVENTARIO_INSUFICIENTE.
--   * Pedido activo por usuario: lo garantiza el índice único parcial
--     idx_un_pedido_activo_por_usuario; la comprobación previa solo da un error más claro.
--
-- Llamada desde la app:
--   const { data, error } = await supabase.rpc('crear_pedido', {
--     p_punto_entrega_id: puntoId,
--     p_items: [{ producto_id: '...', cantidad: 2 }],
--     p_notas_entrega: 'Mesa 4 al fondo',          // opcional
--   });
--
-- Errores (error.message empieza por el código; error.details trae el JSON de errores del carrito):
--   NO_AUTENTICADO, ROL_NO_PERMITIDO, PUNTO_ENTREGA_INVALIDO, NOTAS_DEMASIADO_LARGAS,
--   PEDIDO_ACTIVO_EXISTENTE, CARRITO_INVALIDO
-- ==============================================================================

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

  -- ---- Punto de entrega (RN-002 / ADR 002): predefinido y activo ------------------
  perform 1
  from public.puntos_entrega pe
  join public.zonas_campus z on z.id = pe.zona_id
  where pe.id = p_punto_entrega_id
    and pe.activo is true
    and z.activo is true;
  if not found then
    raise exception 'PUNTO_ENTREGA_INVALIDO: El punto de entrega no existe o no está activo.'
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
