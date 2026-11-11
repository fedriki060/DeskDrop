-- =============================================================================
-- Alta de la cuenta de un comercio (piloto)
-- NO es una migración: se corre a mano en Supabase -> SQL Editor (rol postgres).
--
-- Pasos:
--   0. Si el correo NO es del dominio institucional, descomenta el INSERT de abajo
--      (Supabase rechaza crear usuarios con dominios no permitidos, también desde el panel).
--   1. Supabase -> Authentication -> Users -> "Add user" -> "Create new user".
--      Correo del comercio + contraseña temporal + marcar "Auto Confirm User".
--   2. Edita v_correo y v_comercio y corre el bloque.
--   3. Entrégale al dueño correo + contraseña temporal; que la cambie con
--      "Olvidé mi contraseña" en el login.
--
-- Comercios del catálogo: 'Cafetería Central Bloque 1' y 'Papelería'.
-- Si el nombre no existe, el bloque crea un comercio nuevo (tipo 'restaurante' por defecto).
-- =============================================================================

-- insert into public.dominios_permitidos (dominio) values ('gmail.com') on conflict do nothing;

do $$
declare
  v_correo   text := 'cafeteria@eia.edu.co';          -- <-- correo de la cuenta (paso 1)
  v_comercio text := 'Cafetería Central Bloque 1';    -- <-- nombre exacto del comercio
  v_usuario  uuid;
  v_id       uuid;
begin
  select id into v_usuario from auth.users where lower(email) = lower(v_correo);
  if v_usuario is null then
    raise exception 'No existe el usuario %. Créalo primero en Authentication -> Users.', v_correo;
  end if;

  -- El usuario administra un solo comercio (la app toma el primero que encuentra)
  if exists (select 1 from public.comercios where administrador_id = v_usuario and nombre <> v_comercio) then
    raise exception 'Ese usuario ya administra otro comercio.';
  end if;

  select id into v_id from public.comercios where nombre = v_comercio limit 1;
  if v_id is null then
    insert into public.comercios (nombre, administrador_id, activo)
    values (v_comercio, v_usuario, true) returning id into v_id;
  else
    update public.comercios set administrador_id = v_usuario where id = v_id;
  end if;

  update public.perfiles set rol = 'comercio' where id = v_usuario;
  raise notice 'Listo: % administra % (%).', v_correo, v_comercio, v_id;
end $$;

-- Verificación: una fila por comercio con su dueño
select c.nombre, c.activo, p.email as dueno, p.rol
from public.comercios c
left join public.perfiles p on p.id = c.administrador_id
order by c.nombre;
