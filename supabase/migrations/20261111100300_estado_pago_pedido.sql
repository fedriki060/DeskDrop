-- ==============================================================================
-- DESKDROP: ESTADO DEL PAGO EN EL PEDIDO + PAGO DIGITAL EN EL CHECKOUT
-- ==============================================================================
-- 1. `pedidos.estado_pago` y `pedidos.metodo_pago`: copia del pago del pedido. La fuente de
--    verdad sigue siendo `pagos`; un trigger mantiene la copia al día. Se copia al pedido
--    porque Realtime solo publica `pedidos` (20261107183000): así el solicitante, el
--    comercio y el domiciliario ven el estado del pago en vivo, y con la misma RLS del pedido.
-- 2. crear_pedido recibe `p_metodo_pago` ('efectivo' por defecto, o 'transferencia').
--    `pasarela` se rechaza hasta que haya una pasarela integrada.
-- 3. Cobro:
--      efectivo      -> registrar_cobro_efectivo (domiciliario, pedido Entregado)  [ya existía]
--      transferencia -> confirmar_pago_digital   (admin, tras ver el comprobante)
--    Cada función rechaza el método que no le corresponde. Un pedido digital cobrado pasa a
--    Cerrado al quedar Entregado (o en el acto, si ya estaba Entregado).
-- 4. Cancelar un pedido ya cobrado deja el pago en `devuelto`.
--
-- Errores nuevos: METODO_PAGO_NO_DISPONIBLE (crear_pedido), PAGO_NO_ES_EFECTIVO,
--                 PAGO_NO_ES_DIGITAL, ESTADO_NO_PERMITIDO (confirmar_pago_digital).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Columnas en pedidos + copia desde pagos
-- ------------------------------------------------------------------------------
alter table public.pedidos
  add column if not exists metodo_pago public.metodo_pago not null default 'efectivo',
  add column if not exists estado_pago public.estado_pago not null default 'pendiente';

comment on column public.pedidos.estado_pago is
  'Copia de pagos.estado, la mantiene trg_pagos_sincronizar_pedido. Se lee junto al pedido y llega por Realtime.';
comment on column public.pedidos.metodo_pago is
  'Copia de pagos.metodo, la mantiene trg_pagos_sincronizar_pedido.';

update public.pedidos p
set estado_pago = g.estado, metodo_pago = g.metodo
from public.pagos g
where g.pedido_id = p.id
  and (p.estado_pago is distinct from g.estado or p.metodo_pago is distinct from g.metodo);

create or replace function public.trg_pagos_sincronizar_pedido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.pedidos
  set estado_pago = new.estado,
      metodo_pago = new.metodo
  where id = new.pedido_id
    and (estado_pago is distinct from new.estado or metodo_pago is distinct from new.metodo);
  return null;
end;
$$;

revoke all on function public.trg_pagos_sincronizar_pedido() from public, anon, authenticated;

drop trigger if exists trg_pagos_sincronizar_pedido on public.pagos;
create trigger trg_pagos_sincronizar_pedido
  after insert or update of estado, metodo on public.pagos
  for each row
  execute function public.trg_pagos_sincronizar_pedido();

-- El pago pendiente que nace con el pedido usa el método elegido en el checkout.
create or replace function public.trg_pedidos_crear_pago()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.pagos (pedido_id, metodo, monto, estado)
  values (new.id, new.metodo_pago, new.total, 'pendiente');
  return new;
end;
$$;

-- ------------------------------------------------------------------------------
-- 2. crear_pedido con método de pago
--    La firma cambia (parámetro nuevo con default): se elimina la anterior para no dejar
--    dos sobrecargas ambiguas. Las llamadas con 3 argumentos siguen funcionando.
-- ------------------------------------------------------------------------------
drop function if exists public.crear_pedido(uuid, jsonb, text);

create or replace function public.crear_pedido(
  p_punto_entrega_id uuid,
  p_items            jsonb,
  p_notas_entrega    text default null,
  p_metodo_pago      public.metodo_pago default 'efectivo'
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
  v_metodo    public.metodo_pago := coalesce(p_metodo_pago, 'efectivo');
  v_latitud   numeric;
  v_longitud  numeric;
begin
  -- ---- Quién llama --------------------------------------------------------------
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  v_rol := public.mi_rol();
  if v_rol is distinct from 'solicitante' then
    raise exception 'ROL_NO_PERMITIDO: Solo un solicitante puede crear pedidos.'
      using errcode = '42501';
  end if;

  -- ---- Método de pago: efectivo o transferencia (Nequi / Bancolombia) ---------------
  -- `pasarela` existe en el enum pero todavía no hay pasarela integrada: se rechaza.
  if v_metodo not in ('efectivo', 'transferencia') then
    raise exception 'METODO_PAGO_NO_DISPONIBLE: Ese método de pago aún no está disponible.'
      using errcode = '22023';
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
      subtotal, tarifa_domicilio, total, notas_entrega, metodo_pago
    )
    values (
      v_uid,
      (v_eval ->> 'comercio_id')::uuid,
      p_punto_entrega_id,
      (v_eval ->> 'subtotal')::numeric,
      (v_eval ->> 'tarifa_domicilio')::numeric,
      (v_eval ->> 'total')::numeric,
      v_notas,
      v_metodo
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
    'metodo_pago',      v_metodo,
    'estado_pago',      'pendiente',
    'creado_en',        v_creado_en
  );
end;
$$;

comment on function public.crear_pedido(uuid, jsonb, text, public.metodo_pago) is
  'RF-001/CU-001. Crea el pedido (estado Creado) y descuenta inventario en una sola transacción. Devuelve el pedido como jsonb.';

revoke all on function public.crear_pedido(uuid, jsonb, text, public.metodo_pago) from public, anon;
grant execute on function public.crear_pedido(uuid, jsonb, text, public.metodo_pago) to authenticated;

-- ------------------------------------------------------------------------------
-- 3a. Cobro en efectivo: ahora solo para pedidos pagados en efectivo
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
  v_metodo_pago public.metodo_pago;
  v_fecha       timestamptz := now();
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if public.mi_rol() is distinct from 'repartidor' then
    raise exception 'ROL_NO_PERMITIDO: Solo un repartidor puede registrar cobros.'
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

  select g.estado, g.metodo
    into v_estado_pago, v_metodo_pago
  from public.pagos g
  where g.pedido_id = p_pedido_id
  for update;

  if not found then
    raise exception 'PAGO_NO_ENCONTRADO: El pedido no tiene un pago registrado.'
      using errcode = 'XX000';
  end if;

  -- Un pedido pagado por transferencia no se cobra en efectivo (lo confirma confirmar_pago_digital).
  if v_metodo_pago <> 'efectivo' then
    raise exception 'PAGO_NO_ES_EFECTIVO: Este pedido se paga por %, no en efectivo.', v_metodo_pago
      using errcode = '55000';
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

comment on function public.registrar_cobro_efectivo(uuid) is
  'El repartidor asignado registra el cobro en efectivo de un pedido Entregado: pago a cobrado y pedido a Cerrado.';

revoke all on function public.registrar_cobro_efectivo(uuid) from public, anon;
grant execute on function public.registrar_cobro_efectivo(uuid) to authenticated;

-- ------------------------------------------------------------------------------
-- 3b. Confirmar el pago digital (transferencia)
-- ------------------------------------------------------------------------------
-- Solo un admin, tras verificar el comprobante. (Cuando haya pasarela, el webhook llamará
-- a esta misma lógica con service_role: hoy `pagos_cobro_completo` exige `registrado_por`.)
create or replace function public.confirmar_pago_digital(p_pedido_id uuid)
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
  v_metodo      public.metodo_pago;
  v_fecha       timestamptz := now();
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if not public.es_admin() then
    raise exception 'ROL_NO_PERMITIDO: Solo un administrador puede confirmar pagos digitales.'
      using errcode = '42501';
  end if;

  -- Mismo orden de bloqueo que registrar_cobro_efectivo: primero pedido, luego pago.
  select p.estado, p.total into v_estado, v_total
  from public.pedidos p where p.id = p_pedido_id for update;

  if not found then
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe.' using errcode = 'P0002';
  end if;

  select g.estado, g.metodo into v_estado_pago, v_metodo
  from public.pagos g where g.pedido_id = p_pedido_id for update;

  if not found then
    raise exception 'PAGO_NO_ENCONTRADO: El pedido no tiene un pago registrado.' using errcode = 'XX000';
  end if;

  if v_metodo = 'efectivo' then
    raise exception 'PAGO_NO_ES_DIGITAL: Este pedido se paga en efectivo.' using errcode = '55000';
  end if;

  if v_estado_pago = 'cobrado' then
    raise exception 'PAGO_YA_COBRADO: Este pedido ya fue cobrado.' using errcode = '23505';
  end if;

  if v_estado_pago <> 'pendiente' then
    raise exception 'PAGO_NO_COBRABLE: El pago está en estado %.', v_estado_pago using errcode = '55000';
  end if;

  if v_estado = 'Cancelado' then
    raise exception 'ESTADO_NO_PERMITIDO: No se cobra un pedido Cancelado.' using errcode = '55000';
  end if;

  update public.pagos
  set monto = v_total, estado = 'cobrado', registrado_por = v_uid, fecha_pago = v_fecha
  where pedido_id = p_pedido_id;

  -- Si el pedido ya estaba Entregado, el cobro lo cierra (Entregado -> Cerrado).
  if v_estado = 'Entregado' then
    update public.pedidos set estado = 'Cerrado' where id = p_pedido_id;
    v_estado := 'Cerrado';
  end if;

  return jsonb_build_object(
    'pedido_id',     p_pedido_id,
    'estado_pedido', v_estado,
    'estado_pago',   'cobrado',
    'metodo',        v_metodo,
    'monto',         v_total,
    'fecha_pago',    v_fecha
  );
end;
$$;

comment on function public.confirmar_pago_digital(uuid) is
  'Un admin confirma el pago por transferencia de un pedido; si ya estaba Entregado, lo cierra.';

revoke all on function public.confirmar_pago_digital(uuid) from public, anon;
grant execute on function public.confirmar_pago_digital(uuid) to authenticated;

-- Pedido digital ya pagado que queda Entregado (confirmó el solicitante o la auto-confirmación):
-- se cierra solo. El pedido en efectivo se sigue cerrando con registrar_cobro_efectivo.
create or replace function public.trg_pedidos_cerrar_si_pagado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.pagos g
    where g.pedido_id = new.id and g.estado = 'cobrado' and g.metodo <> 'efectivo'
  ) then
    update public.pedidos set estado = 'Cerrado' where id = new.id;
  end if;
  return null;
end;
$$;

revoke all on function public.trg_pedidos_cerrar_si_pagado() from public, anon, authenticated;

drop trigger if exists trg_pedidos_cerrar_si_pagado on public.pedidos;
create trigger trg_pedidos_cerrar_si_pagado
  after update of estado on public.pedidos
  for each row
  when (new.estado = 'Entregado' and old.estado is distinct from 'Entregado')
  execute function public.trg_pedidos_cerrar_si_pagado();

-- ------------------------------------------------------------------------------
-- 4. Cancelar un pedido ya cobrado: el pago queda `devuelto`
-- ------------------------------------------------------------------------------
create or replace function public.trg_pedidos_devolver_pago()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.pagos set estado = 'devuelto'
  where pedido_id = new.id and estado = 'cobrado';
  return null;
end;
$$;

revoke all on function public.trg_pedidos_devolver_pago() from public, anon, authenticated;

drop trigger if exists trg_pedidos_devolver_pago on public.pedidos;
create trigger trg_pedidos_devolver_pago
  after update of estado on public.pedidos
  for each row
  when (new.estado = 'Cancelado' and old.estado is distinct from 'Cancelado')
  execute function public.trg_pedidos_devolver_pago();
