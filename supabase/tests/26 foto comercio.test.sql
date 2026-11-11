-- Pruebas de la foto del comercio: solo su dueño cambia imagen_url.
begin;
create extension if not exists pgtap with schema extensions;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c2', 'com2@eia.edu.co');
insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Ana Gómez', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1', 'comercio'),
  ('00000000-0000-0000-0000-0000000000c2', 'com2@eia.edu.co', 'Admin Comercio 2', 'comercio')
on conflict (id) do update set nombre_completo = excluded.nombre_completo, rol = excluded.rol;
insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c2', 'Papelería Test', true);

create function pg_temp.como(p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $f$;

select plan(6);

select has_column('public', 'comercios', 'imagen_url', 'comercios tiene imagen_url');
select is((select imagen_url from public.comercios where id = '00000000-0000-0000-0000-0000000000e1'),
  null, 'por defecto el comercio no tiene foto (la app muestra la letra inicial)');

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
update public.comercios set imagen_url = 'https://ejemplo.test/comercios/e1/foto.jpg'
  where id = '00000000-0000-0000-0000-0000000000e1';
select is((select imagen_url from public.comercios where id = '00000000-0000-0000-0000-0000000000e1'),
  'https://ejemplo.test/comercios/e1/foto.jpg', 'el dueño cambia la foto de su comercio');
update public.comercios set imagen_url = 'https://ejemplo.test/robada.jpg'
  where id = '00000000-0000-0000-0000-0000000000e2';
reset role;
select is((select imagen_url from public.comercios where id = '00000000-0000-0000-0000-0000000000e2'),
  null, 'el dueño de otro comercio no puede cambiar su foto');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
update public.comercios set imagen_url = 'https://ejemplo.test/robada.jpg'
  where id = '00000000-0000-0000-0000-0000000000e1';
select is((select imagen_url from public.comercios where id = '00000000-0000-0000-0000-0000000000e1'),
  'https://ejemplo.test/comercios/e1/foto.jpg', 'un solicitante no puede cambiar la foto de un comercio');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
update public.comercios set imagen_url = null where id = '00000000-0000-0000-0000-0000000000e1';
select is((select imagen_url from public.comercios where id = '00000000-0000-0000-0000-0000000000e1'),
  null, 'el dueño puede quitar la foto');
reset role;

select * from finish();
rollback;
