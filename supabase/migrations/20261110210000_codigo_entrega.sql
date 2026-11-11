-- ==============================================================================
-- DESKDROP: CÓDIGO DE 4 DÍGITOS PARA CONFIRMAR LA ENTREGA (T-086, T-087, T-088, T-090)
-- ==============================================================================
-- Antes, el solicitante confirmaba la recepción con un botón (confirmar_recepcion, T-040).
-- Ahora cada pedido nace con un código de 4 dígitos que solo ve el solicitante, y es el
-- domiciliario quien lo digita para marcar el pedido como Entregado.
--
--   * Tabla `codigos_entrega`, aparte de `pedidos`: el domiciliario puede leer los pedidos que
--     tiene asignados (ver_pedidos_por_rol), y con el código en esa misma fila lo vería.
--     La tabla solo tiene política de lectura para el solicitante dueño.
--   * Un trigger crea el código al insertar el pedido (sin depender de crear_pedido).
--   * confirmar_entrega(pedido, código): solo el domiciliario asignado y habilitado (HU-19),
--     con el pedido En Camino. Un código equivocado NO lanza error: devuelve ok=false y los
--     intentos que quedan, porque un error revertiría el conteo. A los 5 fallos el código se
--     bloquea; el pedido se cierra entonces por la auto-confirmación (T-042).
--   * Se elimina confirmar_recepcion: ya no se confirma con un botón del solicitante.
--
-- Uso desde la app:
--   solicitante: supabase.from('codigos_entrega').select('codigo').eq('pedido_id', id)
--   domiciliario: supabase.rpc('confirmar_entrega', { p_pedido_id: id, p_codigo: '1234' })
--     -> { ok: true, pedido_id, estado: 'Entregado', entregado_en }
--     -> { ok: false, motivo: 'CODIGO_INCORRECTO', intentos_restantes: 4 }
--
-- Errores (error.message empieza por el código):
--   NO_AUTENTICADO 28000, ROL_NO_PERMITIDO 42501, CODIGO_INVALIDO 22023,
--   PEDIDO_NO_ENCONTRADO P0002, ESTADO_NO_PERMITIDO 55000, CODIGO_BLOQUEADO 55000
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Tabla de códigos
-- ------------------------------------------------------------------------------
create table if not exists public.codigos_entrega (
  pedido_id         uuid        primary key references public.pedidos (id) on delete cascade,
  codigo            text        not null check (codigo ~ '^[0-9]{4}$'),
  intentos_fallidos smallint    not null default 0 check (intentos_fallidos >= 0),
  creado_en         timestamptz not null default now()
);

comment on table public.codigos_entrega is
  'T-086. Código de 4 dígitos por pedido que ve el solicitante y digita el domiciliario al entregar. Solo lo lee el solicitante dueño.';

alter table public.codigos_entrega enable row level security;

revoke all on public.codigos_entrega from anon, authenticated;
grant select on public.codigos_entrega to authenticated;

drop policy if exists solicitante_ve_su_codigo on public.codigos_entrega;
create policy solicitante_ve_su_codigo on public.codigos_entrega
  for select to authenticated
  using (
    exists (
      select 1 from public.pedidos p
      where p.id = codigos_entrega.pedido_id
        and p.solicitante_id = (select auth.uid())
    )
  );

-- ------------------------------------------------------------------------------
-- 2. Cada pedido nuevo recibe su código
-- ------------------------------------------------------------------------------
create or replace function public.trg_pedidos_crear_codigo_entrega()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.codigos_entrega (pedido_id, codigo)
  values (new.id, lpad((floor(random() * 10000))::int::text, 4, '0'))
  on conflict (pedido_id) do nothing;
  return new;
end;
$$;

revoke all on function public.trg_pedidos_crear_codigo_entrega() from public, anon, authenticated;

drop trigger if exists trg_pedidos_crear_codigo_entrega on public.pedidos;
create trigger trg_pedidos_crear_codigo_entrega
  after insert on public.pedidos
  for each row
  execute function public.trg_pedidos_crear_codigo_entrega();

-- Pedidos que ya estaban en curso antes de esta migración
insert into public.codigos_entrega (pedido_id, codigo)
select p.id, lpad((floor(random() * 10000))::int::text, 4, '0')
from public.pedidos p
where p.estado in ('Creado', 'Asignado', 'En Camino')
on conflict (pedido_id) do nothing;

-- ------------------------------------------------------------------------------
-- 3. El domiciliario confirma la entrega con el código
-- ------------------------------------------------------------------------------
create or replace function public.confirmar_entrega(p_pedido_id uuid, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_intentos constant integer := 5;
  v_uid       uuid := (select auth.uid());
  v_codigo    text := btrim(p_codigo);
  v_estado    public.estado_pedido;
  v_correcto  text;
  v_intentos  integer;
  v_fecha     timestamptz;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO: Debes iniciar sesión.' using errcode = '28000';
  end if;

  if not public.es_repartidor_habilitado() then
    raise exception 'ROL_NO_PERMITIDO: Solo un domiciliario habilitado puede confirmar entregas.'
      using errcode = '42501';
  end if;

  if v_codigo is null or v_codigo !~ '^[0-9]{4}$' then
    raise exception 'CODIGO_INVALIDO: El código son 4 dígitos.' using errcode = '22023';
  end if;

  select p.estado
    into v_estado
  from public.pedidos p
  where p.id = p_pedido_id
    and p.repartidor_id = v_uid
  for update;

  if not found then
    raise exception 'PEDIDO_NO_ENCONTRADO: El pedido no existe o no lo tienes asignado.'
      using errcode = 'P0002';
  end if;

  if v_estado <> 'En Camino' then
    raise exception 'ESTADO_NO_PERMITIDO: Solo puedes confirmar la entrega de un pedido En Camino (estado actual: %).', v_estado
      using errcode = '55000';
  end if;

  select c.codigo, c.intentos_fallidos
    into v_correcto, v_intentos
  from public.codigos_entrega c
  where c.pedido_id = p_pedido_id
  for update;

  if not found then
    raise exception 'CODIGO_NO_ENCONTRADO: El pedido no tiene código de entrega.'
      using errcode = 'XX000';
  end if;

  if v_intentos >= c_max_intentos then
    raise exception 'CODIGO_BLOQUEADO: Se agotaron los intentos. El pedido se confirmará solo en unos minutos.'
      using errcode = '55000';
  end if;

  if v_codigo <> v_correcto then
    update public.codigos_entrega
    set intentos_fallidos = intentos_fallidos + 1
    where pedido_id = p_pedido_id;

    -- No se lanza error: revertiría el conteo de intentos
    return jsonb_build_object(
      'ok',                 false,
      'motivo',             'CODIGO_INCORRECTO',
      'intentos_restantes', c_max_intentos - (v_intentos + 1)
    );
  end if;

  -- En Camino -> Entregado. El trigger de transiciones valida el cambio y pone actualizado_en.
  update public.pedidos
  set estado = 'Entregado'
  where id = p_pedido_id
  returning actualizado_en into v_fecha;

  return jsonb_build_object(
    'ok',           true,
    'pedido_id',    p_pedido_id,
    'estado',       'Entregado',
    'entregado_en', v_fecha
  );
end;
$$;

comment on function public.confirmar_entrega(uuid, text) is
  'T-087 (HU-20). El domiciliario asignado digita el código de 4 dígitos del solicitante: En Camino -> Entregado. Máximo 5 intentos fallidos.';

revoke all on function public.confirmar_entrega(uuid, text) from public, anon;
grant execute on function public.confirmar_entrega(uuid, text) to authenticated;

-- ------------------------------------------------------------------------------
-- 4. Ya no se confirma con el botón del solicitante (T-090)
-- ------------------------------------------------------------------------------
drop function if exists public.confirmar_recepcion(uuid);
