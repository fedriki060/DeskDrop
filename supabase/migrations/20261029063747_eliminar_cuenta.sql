-- T-076: eliminar la cuenta (anonimizando el perfil) y limpiar cuentas abandonadas con pg_cron.
--
-- Decisión: anonimizar en vez de borrar. Los pedidos y calificaciones apuntan al perfil y el
-- historial del comercio los necesita. Al borrar el usuario de auth.users ya nadie puede
-- entrar con esa cuenta; el perfil queda como "Usuario eliminado", sin correo ni teléfono.
-- La aceptación de los términos (consentimientos) se conserva como prueba (Ley 1581).

-- ============================================================================
-- 1. El perfil debe poder sobrevivir al usuario de auth.users
--    (antes: on delete cascade lo borraba, y fallaba si tenía pedidos)
-- ============================================================================
do $$
declare
  v_fk text;
begin
  select c.conname into v_fk
  from pg_constraint c
  where c.conrelid = 'public.perfiles'::regclass
    and c.contype = 'f'
    and c.confrelid = 'auth.users'::regclass;
  if v_fk is not null then
    execute format('alter table public.perfiles drop constraint %I', v_fk);
  end if;
end $$;

alter table public.perfiles alter column email drop not null;
alter table public.perfiles add column if not exists eliminado_en timestamptz;

-- ============================================================================
-- 2. Al borrar un usuario (desde la app, el panel o el job) se anonimiza su perfil
-- ============================================================================
create or replace function public.anonimizar_perfil() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.perfiles
  set email           = null,
      nombre_completo = 'Usuario eliminado',
      telefono        = null,
      rol             = 'solicitante',  -- pierde cualquier permiso especial
      eliminado_en    = now()
  where id = old.id;
  return old;
end $$;

revoke execute on function public.anonimizar_perfil() from public, anon, authenticated;

drop trigger if exists t_anonimizar_perfil on auth.users;
create trigger t_anonimizar_perfil before delete on auth.users
  for each row execute function public.anonimizar_perfil();

-- ============================================================================
-- 3. La app llama a esta función para que el usuario elimine su propia cuenta
--    Códigos de error propios (la app los traduce a mensajes):
--      DD001 = tiene un pedido en curso; DD002 = es el único admin
-- ============================================================================
create or replace function public.eliminar_mi_cuenta() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_usuario uuid := (select auth.uid());
begin
  if v_usuario is null then
    raise exception 'Debes iniciar sesión' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.pedidos p
    where (p.solicitante_id = v_usuario or p.repartidor_id = v_usuario)
      and p.estado in ('Creado', 'Asignado', 'En Camino')
  ) then
    raise exception 'Tienes un pedido en curso' using errcode = 'DD001';
  end if;

  if public.mi_rol() = 'admin' and not exists (
    select 1 from public.perfiles p
    where p.rol = 'admin' and p.id <> v_usuario and p.eliminado_en is null
  ) then
    raise exception 'Eres el único administrador' using errcode = 'DD002';
  end if;

  -- El trigger t_anonimizar_perfil limpia el perfil; Supabase borra en cascada
  -- las sesiones e identidades del usuario
  delete from auth.users where id = v_usuario;
end $$;

revoke execute on function public.eliminar_mi_cuenta() from public, anon;
grant execute on function public.eliminar_mi_cuenta() to authenticated;

-- ============================================================================
-- 4. Limpieza: cuentas que nunca verificaron el correo, de más de 7 días y sin pedidos.
--    Nunca llegaron a usarse, así que se borran del todo (perfil y aceptación incluidos).
-- ============================================================================
create or replace function public.limpiar_cuentas_sin_verificar() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_ids uuid[];
begin
  select coalesce(array_agg(u.id), '{}') into v_ids
  from auth.users u
  where u.email_confirmed_at is null
    and u.created_at < now() - interval '7 days'
    and not exists (
      select 1 from public.pedidos p
      where p.solicitante_id = u.id or p.repartidor_id = u.id
    );

  delete from public.perfiles where id = any (v_ids);  -- consentimientos se van en cascada
  delete from auth.users where id = any (v_ids);       -- el trigger ya no encuentra perfil
  return coalesce(array_length(v_ids, 1), 0);
end $$;

-- Solo la corre el job (o alguien desde el SQL Editor), nunca la app
revoke execute on function public.limpiar_cuentas_sin_verificar() from public, anon, authenticated;

-- ============================================================================
-- 5. Programarla todos los días a las 08:00 UTC (3:00 a. m. en Colombia)
--    cron.schedule con el mismo nombre reemplaza el job: la migración se puede repetir.
-- ============================================================================
create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'limpiar-cuentas-sin-verificar',
  '0 8 * * *',
  'select public.limpiar_cuentas_sin_verificar()'
);