-- T-075: guardar qué versión de los Términos y la Política de privacidad aceptó cada usuario y cuándo
-- (prueba de la autorización, Ley 1581 de 2012). Una fila por versión aceptada: si los textos
-- cambian, el usuario acepta la nueva versión y el historial anterior se conserva.

-- 1. Tabla de aceptaciones
create table if not exists public.consentimientos (
  usuario_id  uuid        not null default auth.uid()
              references public.perfiles (id) on delete cascade,
  version     text        not null check (length(version) between 1 and 30),
  aceptado_en timestamptz not null default now(),  -- hora del servidor, no la del celular
  primary key (usuario_id, version)                -- cada versión se acepta una sola vez
);

alter table public.consentimientos enable row level security;

-- 2. Permisos: cada usuario ve solo lo suyo y solo puede aceptar a su nombre.
--    El insert se limita a la columna version: usuario_id y aceptado_en los pone la base.
--    Sin update ni delete: una aceptación no se edita ni se borra (se borra con la cuenta).
revoke all on public.consentimientos from anon, authenticated;
grant select on public.consentimientos to authenticated;
grant insert (version) on public.consentimientos to authenticated;

drop policy if exists ver_mis_consentimientos on public.consentimientos;
create policy ver_mis_consentimientos on public.consentimientos
  for select to authenticated
  using (usuario_id = (select auth.uid()));

drop policy if exists aceptar_terminos on public.consentimientos;
create policy aceptar_terminos on public.consentimientos
  for insert to authenticated
  with check (usuario_id = (select auth.uid()));

-- 3. Al registrarse, la app envía la versión aceptada en los metadatos del signUp
--    (terminos_version). El trigger crea el perfil y la aceptación en la misma transacción.
--    Los usuarios creados desde el panel (sin metadatos) quedan sin aceptación registrada.
create or replace function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_version text := nullif(trim(new.raw_user_meta_data->>'terminos_version'), '');
begin
  insert into public.perfiles (id, email, nombre_completo)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'nombre_completo', 'Usuario nuevo'))
  on conflict (id) do nothing;

  if v_version is not null then
    insert into public.consentimientos (usuario_id, version)
    values (new.id, v_version)
    on conflict do nothing;
  end if;

  return new;
end $$;