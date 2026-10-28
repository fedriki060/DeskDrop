-- T-068: registro solo con correo institucional, perfil automático y ayuda para exigir correo verificado.
-- Pegar dentro de la migración creada con:  npx supabase migration new auth_registro
-- ANTES de correr db reset: reemplazar TU-DOMINIO.edu.co por el dominio institucional real.

-- 1. Rol y perfiles (si T-006/T-007 ya los crearon con estas columnas, no se duplican)
do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'rol'
  ) then
    create type public.rol as enum ('solicitante', 'domiciliario', 'comercio', 'administrador');
  end if;
end $$;

create table if not exists public.perfiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  rol public.rol not null default 'solicitante',
  creado_en timestamptz not null default now()
);
alter table public.perfiles enable row level security;
grant select on public.perfiles to authenticated;   -- sin update: nadie se cambia el rol (T-072 afina esto)
drop policy if exists ver_mi_perfil on public.perfiles;
create policy ver_mi_perfil on public.perfiles
  for select to authenticated using (id = (select auth.uid()));

-- 2. Dominios institucionales permitidos (una fila por dominio o subdominio)
create table if not exists public.dominios_permitidos (
  dominio text primary key check (dominio = lower(dominio))
);
alter table public.dominios_permitidos enable row level security;
revoke all on public.dominios_permitidos from anon, authenticated;   -- solo la función de abajo la lee

insert into public.dominios_permitidos (dominio) values ('eia.edu.co')
on conflict do nothing;

-- 3. Validación del dominio al registrarse y al cambiar el correo
create or replace function public.validar_dominio_correo() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_dominio text;
begin
  v_dominio := lower(substring(coalesce(new.email, '') from '@([^@]+)$'));
  if v_dominio is null
     or not exists (select 1 from public.dominios_permitidos d where d.dominio = v_dominio) then
    raise exception 'Solo se permiten correos institucionales';
  end if;
  return new;
end $$;

drop trigger if exists t_validar_dominio on auth.users;
create trigger t_validar_dominio before insert on auth.users
  for each row execute function public.validar_dominio_correo();

drop trigger if exists t_validar_dominio_cambio on auth.users;
create trigger t_validar_dominio_cambio before update of email on auth.users
  for each row when (new.email is distinct from old.email)
  execute function public.validar_dominio_correo();

-- 4. Perfil automático con rol solicitante
create or replace function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perfiles (id, email, nombre_completo) values (new.id, new.email, COALESCE(NEW.raw_user_meta_data->>'nombre_completo','Usuario nuevo'))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists t_crear_perfil on auth.users;
create trigger t_crear_perfil after insert on auth.users
  for each row execute function public.crear_perfil();

-- 5. Ayuda para T-023 (crear_pedido): ¿el usuario de la sesión verificó su correo?
create or replace function public.correo_verificado() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select u.email_confirmed_at is not null from auth.users u where u.id = auth.uid()),
    false
  )
$$;
revoke execute on function public.correo_verificado() from public, anon;
grant execute on function public.correo_verificado() to authenticated;