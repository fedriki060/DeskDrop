-- ==============================================================================
-- DESKDROP: CUSTODIA, LIBERACIÓN Y REEMBOLSO DEL PAGO DIGITAL
-- ==============================================================================
-- Tareas:
--   2) Al aprobarse el pago, los fondos quedan RETENIDOS (estado `en_custodia`) y se
--      registra el movimiento. Lo dispara la Edge Function `retener-pago` (webhook de la
--      pasarela o un admin) a través de retener_pago(), que solo puede ejecutar service_role.
--   3) Al pasar el pedido a Entregado (RN-004) los fondos se LIBERAN al domiciliario
--      (`liberado`) y el pedido queda Cerrado. Lo hace un trigger: sirve igual si confirma
--      el solicitante, si corre la auto-confirmación (T-042) o si es un UPDATE manual.
--   4) Al pasar el pedido a Cancelado con el pago retenido, se REEMBOLSA al solicitante
--      (`devuelto`). Un trigger, así que cubre cancelar_pedidos_vencidos (T-043) y
--      cualquier otra cancelación, igual que la reposición de inventario (T-044).
--
-- Todo queda en `movimientos_pago`, un libro de movimientos: máximo UNO de cada tipo
-- (retencion / liberacion / reembolso) por pago, lo que hace idempotentes los reintentos
-- del webhook.
--
-- SUPUESTO sobre RN-004 (no está escrita en docs/): se libera el monto completo retenido
-- al domiciliario, igual que en efectivo él recibe el total. El desglose (80 % de la tarifa
-- al domiciliario, 20 % a la plataforma, subtotal al comercio) queda en
-- movimientos_pago.detalle, con el porcentaje en configuracion.porcentaje_tarifa_repartidor.
--
-- Errores nuevos: PAGO_YA_RETENIDO (23505). Se mantienen PAGO_NO_ES_DIGITAL,
-- PAGO_NO_COBRABLE, PAGO_NO_ENCONTRADO, PEDIDO_NO_ENCONTRADO y ESTADO_NO_PERMITIDO.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Configuración y libro de movimientos
-- ------------------------------------------------------------------------------
insert into public.configuracion (clave, valor, descripcion)
values (
  'porcentaje_tarifa_repartidor',
  80,
  'Porcentaje de la tarifa de domicilio que le corresponde al domiciliario; el resto es de la plataforma (T-014)'
)
on conflict (clave) do nothing;

alter table public.pagos
  add constraint pagos_custodia_con_fecha
  check (estado not in ('en_custodia', 'liberado') or fecha_pago is not null);

create table if not exists public.movimientos_pago (
  id              uuid primary key default gen_random_uuid(),
  pago_id         uuid not null references public.pagos(id) on delete cascade,
  pedido_id       uuid not null references public.pedidos(id) on delete cascade,
  tipo            text not null check (tipo in ('retencion', 'liberacion', 'reembolso')),
  monto           numeric(10,2) not null check (monto >= 0),
  destinatario_id uuid references public.perfiles(id),
  referencia      text,
  detalle         jsonb not null default '{}'::jsonb,
  registrado_por  uuid references public.perfiles(id),
  creado_en       timestamptz not null default now(),
  constraint movimientos_pago_un_tipo_por_pago unique (pago_id, tipo)
);

comment on table public.movimientos_pago is
  'Libro de movimientos del pago digital: retención, liberación al domiciliario y reembolso. Solo lo escriben funciones SECURITY DEFINER.';
comment on column public.movimientos_pago.destinatario_id is
  'Quién recibe el dinero: el domiciliario en una liberación, el solicitante en un reembolso. null en la retención.';
comment on column public.movimientos_pago.referencia is
  'Referencia externa (id de la transacción en la pasarela o del comprobante). No se expone a la app.';

create index if not exists idx_movimientos_pago_pedido on public.movimientos_pago (pedido_id);

-- Lectura: ve los movimientos quien ve el pedido (misma RLS), sin `referencia` ni `detalle`.
-- Nadie escribe desde la Data API.
alter table public.movimientos_pago enable row level security;
revoke all on public.movimientos_pago from anon, authenticated;
grant select (id, pago_id, pedido_id, tipo, monto, destinatario_id, creado_en)
  on public.movimientos_pago to authenticated;

drop policy if exists ver_movimientos_de_mis_pedidos on public.movimientos_pago;
create policy ver_movimientos_de_mis_pedidos on public.movimientos_pago
  for select to authenticated
  using (exists (select 1 from public.pedidos p where p.id = movimientos_pago.pedido_id));

-- ------------------------------------------------------------------------------
-- 2. Liberar los fondos (en_custodia -> liberado). Interna: la llaman triggers y
--    _retener_pago, siempre con el pedido ya bloqueado.
-- ------------------------------------------------------------------------------
create or replace function public._liberar_pago(p_pedido_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pago_id   uuid;
  v_monto     numeric;
  v_estado    public.estado_pago;
  v_tarifa    numeric;
  v_subtotal  numeric;
  v_repartidor uuid;
  v_pct       numeric;
  v_part_rep  numeric;
begin
  select g.id, g.monto, g.estado
    into v_pago_id, v_monto, v_estado
  from public.pagos g
  where g.pedido_id = p_pedido_id
  for update;

  -- Solo se libera lo que está en custodia (el efectivo y los pagos ya liberados no).
  if not found or v_estado <> 'en_custodia' then
    return;
  end if;

  select p.tarifa_domicilio, p.subtotal, p.repartidor_id
    into v_tarifa, v_subtotal, v_repartidor
  from public.pedidos p
  where p.id = p_pedido_id;

  select valor into v_pct
  from public.configuracion
  where clave = 'porcentaje_tarifa_repartidor';
  -- Nunca se bloquea una entrega por un parámetro faltante: se usa el valor del piloto.
  v_pct := least(greatest(coalesce(v_pct, 80), 0), 100);
  v_part_rep := round(v_tarifa * v_pct / 100, 2);

  update public.pagos set estado = 'liberado' where id = v_pago_id;

  insert into public.movimientos_pago (pago_id, pedido_id, tipo, monto, destinatario_id, detalle)
  values (
    v_pago_id, p_pedido_id, 'liberacion', v_monto, v_repartidor,
    jsonb_build_object(
      'regla',                 'RN-004',
      'subtotal_comercio',     v_subtotal,
      'tarifa_domicilio',      v_tarifa,
      'tarifa_repartidor',     v_part_rep,
      'tarifa_plataforma',     v_tarifa - v_part_rep,
      'porcentaje_repartidor', v_pct
    )
  )
  on conflict (pago_id, tipo) do nothing;
end;
$$;

revoke all on function public._liberar_pago(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 3. Retener el pago aprobado (pendiente -> en_custodia). Interna.
--    Si el pedido ya estaba Entregado, los fondos se retienen y se liberan en el acto.
-- ------------------------------------------------------------------------------
create or replace function public._retener_pago(
  p_pedido_id  uuid,
  p_actor      uuid,
  p_referencia text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_estado      public.estado_pedido;
  v_total       numeric;
  v_pago_id     uuid;
  v_estado_pago public.estado_pago;
  v_metodo      public.metodo_pago;
  v_fecha       timestamptz := now();
  v_ref         text := nullif(btrim(p_referencia), '');
begin
  -- Mismo orden de bloqueo que registrar_cobro_efectivo: primero el pedido, luego el pago.
  select p.estado, p.total
    into v_estado, v_total
  from public.pedidos p
  where p.id = p_pedido_id
  for update;

  if not found then
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe.' using errcode = 'P0002';
  end if;

  select g.id, g.estado, g.metodo
    into v_pago_id, v_estado_pago, v_metodo
  from public.pagos g
  where g.pedido_id = p_pedido_id
  for update;

  if not found then
    raise exception 'PAGO_NO_ENCONTRADO: El pedido no tiene un pago registrado.' using errcode = 'XX000';
  end if;

  if v_metodo = 'efectivo' then
    raise exception 'PAGO_NO_ES_DIGITAL: Este pedido se paga en efectivo.' using errcode = '55000';
  end if;

  if v_estado_pago in ('en_custodia', 'liberado') then
    raise exception 'PAGO_YA_RETENIDO: Este pago ya fue aprobado y retenido.' using errcode = '23505';
  end if;

  if v_estado_pago = 'cobrado' then
    raise exception 'PAGO_YA_COBRADO: Este pedido ya fue cobrado.' using errcode = '23505';
  end if;

  if v_estado_pago <> 'pendiente' then
    raise exception 'PAGO_NO_COBRABLE: El pago está en estado %.', v_estado_pago using errcode = '55000';
  end if;

  if v_estado = 'Cancelado' then
    raise exception 'ESTADO_NO_PERMITIDO: No se retiene el pago de un pedido Cancelado.' using errcode = '55000';
  end if;

  update public.pagos
  set monto          = v_total,
      estado         = 'en_custodia',
      registrado_por = p_actor,
      fecha_pago     = v_fecha
  where id = v_pago_id;

  insert into public.movimientos_pago (pago_id, pedido_id, tipo, monto, referencia, registrado_por, detalle)
  values (v_pago_id, p_pedido_id, 'retencion', v_total, v_ref, p_actor,
          jsonb_build_object('metodo', v_metodo));

  -- Pedido ya entregado antes de aprobarse el pago: se libera y se cierra de una vez.
  if v_estado = 'Entregado' then
    perform public._liberar_pago(p_pedido_id);
    update public.pedidos set estado = 'Cerrado' where id = p_pedido_id;
    v_estado := 'Cerrado';
  end if;

  return jsonb_build_object(
    'pedido_id',     p_pedido_id,
    'estado_pedido', v_estado,
    'estado_pago',   (select g.estado from public.pagos g where g.id = v_pago_id),
    'metodo',        v_metodo,
    'monto',         v_total,
    'fecha_pago',    v_fecha
  );
end;
$$;

revoke all on function public._retener_pago(uuid, uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 4. Puertas de entrada
-- ------------------------------------------------------------------------------
-- 4a. La usa la Edge Function `retener-pago` (con la service_role key). No es invocable desde la app.
create or replace function public.retener_pago(
  p_pedido_id  uuid,
  p_referencia text default null,
  p_actor      uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public._retener_pago(p_pedido_id, p_actor, p_referencia);
end;
$$;

comment on function public.retener_pago(uuid, text, uuid) is
  'Tarea 2: aprueba un pago digital y retiene los fondos (en_custodia). Solo service_role, desde la Edge Function retener-pago.';

revoke all on function public.retener_pago(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.retener_pago(uuid, text, uuid) to service_role;

-- 4b. Un admin aprueba el pago a mano (comprobante) desde SQL / la app. Misma lógica.
create or replace function public.confirmar_pago_digital(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if not public.es_admin() then
    raise exception 'ROL_NO_PERMITIDO: Solo un administrador puede confirmar pagos digitales.'
      using errcode = '42501';
  end if;

  return public._retener_pago(p_pedido_id, v_uid, 'manual');
end;
$$;

comment on function public.confirmar_pago_digital(uuid) is
  'Un admin aprueba el pago por transferencia: los fondos quedan en custodia (y se liberan si el pedido ya estaba Entregado).';

revoke all on function public.confirmar_pago_digital(uuid) from public, anon;
grant execute on function public.confirmar_pago_digital(uuid) to authenticated;

-- ------------------------------------------------------------------------------
-- 5. Pedido Entregado: liberar los fondos y cerrar (RN-004)
--    Reemplaza a trg_pedidos_cerrar_si_pagado (20261111100300), que solo cerraba.
-- ------------------------------------------------------------------------------
drop trigger if exists trg_pedidos_cerrar_si_pagado on public.pedidos;
drop function if exists public.trg_pedidos_cerrar_si_pagado();

create or replace function public.trg_pedidos_liberar_fondos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public._liberar_pago(new.id);

  -- Pago digital ya resuelto (liberado, o `cobrado` de antes de la custodia): se cierra solo.
  -- El pedido en efectivo se sigue cerrando con registrar_cobro_efectivo.
  if exists (
    select 1 from public.pagos g
    where g.pedido_id = new.id
      and g.metodo <> 'efectivo'
      and g.estado in ('liberado', 'cobrado')
  ) then
    update public.pedidos set estado = 'Cerrado' where id = new.id;
  end if;
  return null;
end;
$$;

revoke all on function public.trg_pedidos_liberar_fondos() from public, anon, authenticated;

drop trigger if exists trg_pedidos_liberar_fondos on public.pedidos;
create trigger trg_pedidos_liberar_fondos
  after update of estado on public.pedidos
  for each row
  when (new.estado = 'Entregado' and old.estado is distinct from 'Entregado')
  execute function public.trg_pedidos_liberar_fondos();

-- ------------------------------------------------------------------------------
-- 6. Pedido Cancelado: reembolso automático (T-043 cancela, este trigger devuelve)
--    Reemplaza a la versión de 20261111100300, que no conocía la custodia ni el libro.
-- ------------------------------------------------------------------------------
create or replace function public.trg_pedidos_devolver_pago()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pago_id uuid;
  v_monto   numeric;
  v_estado  public.estado_pago;
begin
  select g.id, g.monto, g.estado
    into v_pago_id, v_monto, v_estado
  from public.pagos g
  where g.pedido_id = new.id
    and g.estado in ('en_custodia', 'cobrado')
  for update;

  -- Pago pendiente (nunca se aprobó) o ya devuelto: no hay nada que reembolsar.
  if not found then
    return null;
  end if;

  update public.pagos set estado = 'devuelto' where id = v_pago_id;

  insert into public.movimientos_pago (pago_id, pedido_id, tipo, monto, destinatario_id, detalle)
  values (
    v_pago_id, new.id, 'reembolso', v_monto, new.solicitante_id,
    jsonb_build_object('motivo', 'pedido_cancelado', 'estado_previo_pago', v_estado)
  )
  on conflict (pago_id, tipo) do nothing;

  return null;
end;
$$;

revoke all on function public.trg_pedidos_devolver_pago() from public, anon, authenticated;
-- El trigger trg_pedidos_devolver_pago ya existe (20261111100300) y apunta a esta función.
