-- ==============================================================================
-- DESKDROP: PAGOS MANUALES Y COBRO EN EFECTIVO DEL DOMICILIARIO
-- ==============================================================================
-- La tabla `pagos` (método, monto, estado pendiente/cobrado/devuelto) ya existía desde la
-- migración inicial pero sin RLS ni permisos. Aquí se completa:
--
--   * Cada pedido nace con su pago: trigger que crea un pago `pendiente`, método
--     `efectivo`, monto = total del pedido.
--   * Lectura por RLS: ve el pago quien ve el pedido (solicitante, repartidor asignado,
--     comercio). Nadie escribe desde la Data API.
--   * registrar_cobro_efectivo(pedido): el domiciliario del pedido registra que cobró en
--     efectivo. Pasa el pago a `cobrado` y cierra el pedido (Entregado -> Cerrado).
--
--   supabase.rpc('registrar_cobro_efectivo', { p_pedido_id })
--
-- Errores (error.message empieza por el código):
--   NO_AUTENTICADO, ROL_NO_PERMITIDO, PEDIDO_NO_ENCONTRADO, PAGO_YA_COBRADO,
--   PAGO_NO_COBRABLE, ESTADO_NO_PERMITIDO, PAGO_NO_ENCONTRADO
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Integridad: un pago cobrado siempre dice quién lo registró y cuándo
-- ------------------------------------------------------------------------------
alter table public.pagos
  add constraint pagos_cobro_completo
  check (estado <> 'cobrado' or (registrado_por is not null and fecha_pago is not null));

-- ------------------------------------------------------------------------------
-- 2. Lectura protegida por RLS (la escritura solo ocurre por funciones SQL)
-- ------------------------------------------------------------------------------
grant select on public.pagos to authenticated;

-- La subconsulta sobre pedidos también pasa por RLS (pedidos_lectura, por rol).
create policy pagos_lectura
  on public.pagos
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.pedidos p
      where p.id = pagos.pedido_id
    )
  );

-- ------------------------------------------------------------------------------
-- 3. Cada pedido nuevo crea su pago pendiente (efectivo, monto = total)
-- ------------------------------------------------------------------------------
create or replace function public.trg_pedidos_crear_pago()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.pagos (pedido_id, metodo, monto, estado)
  values (new.id, 'efectivo', new.total, 'pendiente');
  return new;
end;
$$;

revoke all on function public.trg_pedidos_crear_pago() from public, anon, authenticated;

create trigger trg_pedidos_crear_pago
  after insert on public.pedidos
  for each row
  execute function public.trg_pedidos_crear_pago();

-- Pedidos vivos que ya existían sin pago.
insert into public.pagos (pedido_id, metodo, monto, estado)
select p.id, 'efectivo', p.total, 'pendiente'
from public.pedidos p
where p.estado not in ('Cancelado', 'Cerrado')
  and not exists (select 1 from public.pagos g where g.pedido_id = p.id);

-- ------------------------------------------------------------------------------
-- 4. Registrar el cobro en efectivo
-- ------------------------------------------------------------------------------
-- Solo el repartidor asignado al pedido y solo con el pedido Entregado (el solicitante
-- confirmó o corrió la auto-confirmación de 15 min). El monto es siempre el total del
-- pedido: el domiciliario no lo digita. Bloquea pedido y pago: un doble clic recibe
-- PAGO_YA_COBRADO en vez de registrar dos veces.
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

  if public.rol_actual() is distinct from 'repartidor' then
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

  -- Entregado -> Cerrado: cobro registrado / cierre (matriz de 20261028100200).
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
