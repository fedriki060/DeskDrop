-- ==============================================================================
-- DESKDROP: TABLA DE CONFIGURACIÓN + TARIFA DE DOMICILIO LEÍDA DE LA TABLA (T-014)
-- ==============================================================================
-- Hasta ahora la tarifa estaba escrita a mano en tarifa_domicilio_piloto() ($2.000 fijos).
-- Ahora vive en `configuracion` (clave/valor) y esa función la lee. Cambiarla es un UPDATE,
-- no una migración:
--
--   update public.configuracion set valor = 2500 where clave = 'tarifa_domicilio';
--
-- Efecto: validar_carrito y crear_pedido calculan  total = SUM(precio * cantidad) + tarifa.
-- Los pedidos ya creados conservan la tarifa con la que se crearon (pedidos.tarifa_domicilio).
-- Falla cerrado: si la clave no existe, crear_pedido rechaza con CONFIG_FALTANTE.
-- ==============================================================================

create table if not exists public.configuracion (
  clave          text primary key,
  valor          numeric not null,
  descripcion    text,
  actualizado_en timestamptz not null default now(),
  constraint configuracion_valor_no_negativo check (valor >= 0)
);

comment on table public.configuracion is
  'Parámetros de negocio del piloto (docs/reglas_negocio_piloto.md, T-014). Solo la leen funciones SECURITY DEFINER.';

-- Sin acceso desde la Data API: RLS activo y sin políticas ni grants.
alter table public.configuracion enable row level security;
revoke all on public.configuracion from anon, authenticated;

-- Valor oficial del MVP (T-014): tarifa fija de domicilio de $2.000 COP.
insert into public.configuracion (clave, valor, descripcion)
values ('tarifa_domicilio', 2000.00, 'Tarifa fija de domicilio en COP (T-014)')
on conflict (clave) do nothing;

-- Misma firma y mismos permisos que antes (sigue sin ser invocable desde la API);
-- ahora lee la tabla. SECURITY DEFINER para no depender de quién la llame.
create or replace function public.tarifa_domicilio_piloto()
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tarifa numeric;
begin
  select valor into v_tarifa
  from public.configuracion
  where clave = 'tarifa_domicilio';

  if v_tarifa is null then
    raise exception 'CONFIG_FALTANTE: Falta la tarifa de domicilio en la tabla configuracion.'
      using errcode = '55000';
  end if;

  return v_tarifa;
end;
$$;

comment on function public.tarifa_domicilio_piloto() is
  'Tarifa de domicilio vigente, leída de configuracion (clave tarifa_domicilio). Interna: la usa _evaluar_carrito.';

revoke all on function public.tarifa_domicilio_piloto() from public, anon, authenticated;
