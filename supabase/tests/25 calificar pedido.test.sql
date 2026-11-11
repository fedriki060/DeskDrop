-- Pruebas de HU-15 (T-064, T-065, T-095): calificar al domiciliario.
begin;
create extension if not exists pgtap with schema extensions;

-- a1, a2 solicitantes; b1 domiciliario; c1 dueño del comercio.
-- Pedidos de a1 con b1: ca01 Entregado, ca02 Cerrado, ca03 En Camino, ca04 Entregado (se le vence el plazo)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Ana Gómez',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Beto Ruiz',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Carlos Pérez', 'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1', 'comercio')
on conflict (id) do update set nombre_completo = excluded.nombre_completo, rol = excluded.rol;

insert into public.aceptaciones_repartidor (usuario_id, version) values
  ('00000000-0000-0000-0000-0000000000b1', 'test');

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);
insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);
insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Entregado', 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ca02', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Cerrado', 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ca03', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000),
  ('00000000-0000-0000-0000-00000000ca04', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Entregado', 1000, 2000, 3000);

-- ca04 se entregó hace 25 horas: fuera del plazo de 24 h (el trigger renueva actualizado_en, se desactiva)
set local session_replication_role = replica;
update public.pedidos set actualizado_en = now() - interval '25 hours' where id = '00000000-0000-0000-0000-00000000ca04';
set local session_replication_role = origin;

create function pg_temp.como(p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $f$;

create function pg_temp.como_anon() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
end $f$;

select plan(16);

select has_function('public', 'calificar_pedido', array['uuid', 'integer', 'text'], 'existe calificar_pedido');
select ok(not has_function_privilege('anon', 'public.calificar_pedido(uuid,integer,text)', 'execute'),
  'anon no puede calificar');
select is((select valor from public.configuracion where clave = 'plazo_calificacion_horas'), 24::numeric,
  'el plazo para calificar es de 24 horas');

-- Calificar un pedido Entregado
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select (public.calificar_pedido('00000000-0000-0000-0000-00000000ca01', 5, '  Muy amable  ')) ->> 'promedio'),
  '5.00', 'el solicitante califica un pedido Entregado y recibe el promedio');
select is((select comentario from public.calificaciones where pedido_id = '00000000-0000-0000-0000-00000000ca01'),
  'Muy amable', 'el comentario se guarda sin espacios sobrantes');
select throws_ok($$ select public.calificar_pedido('00000000-0000-0000-0000-00000000ca01', 4) $$,
  '23505', 'YA_CALIFICADO: Ya calificaste este pedido.', 'solo se califica una vez por pedido');

-- Segundo pedido (Cerrado): el promedio se recalcula
select is((select (public.calificar_pedido('00000000-0000-0000-0000-00000000ca02', 4)) ->> 'promedio'),
  '4.50', 'un pedido Cerrado también se puede calificar y el promedio se recalcula');

-- Validaciones
select throws_ok($$ select public.calificar_pedido('00000000-0000-0000-0000-00000000ca03', 5) $$,
  '55000', null, 'un pedido que no está entregado no se puede calificar');
select throws_ok($$ select public.calificar_pedido('00000000-0000-0000-0000-00000000ca04', 0) $$,
  '22023', 'ESTRELLAS_INVALIDAS: La calificación va de 1 a 5 estrellas.', 'cero estrellas se rechaza');
select throws_ok($$ select public.calificar_pedido('00000000-0000-0000-0000-00000000ca04', 6) $$,
  '22023', 'ESTRELLAS_INVALIDAS: La calificación va de 1 a 5 estrellas.', 'seis estrellas se rechaza');
select throws_ok($$ select public.calificar_pedido('00000000-0000-0000-0000-00000000ca04', 5, repeat('x', 301)) $$,
  '22023', 'COMENTARIO_DEMASIADO_LARGO: Máximo 300 caracteres.', 'un comentario de más de 300 caracteres se rechaza');
select throws_ok($$ select public.calificar_pedido('00000000-0000-0000-0000-00000000ca04', 5) $$,
  '55000', 'PLAZO_VENCIDO: Ya pasó el plazo para calificar este pedido.', 'fuera del plazo no se puede calificar');

-- El promedio llega a datos_partes_pedido mientras el domiciliario lleva un pedido
select is((select repartidor_calificacion from public.datos_partes_pedido(array['00000000-0000-0000-0000-00000000ca03']::uuid[])),
  4.5::numeric, 'el solicitante ve el promedio real del domiciliario con el pedido En Camino');
reset role;

-- Quien no es el solicitante no puede calificar
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
select throws_ok($$ select public.calificar_pedido('00000000-0000-0000-0000-00000000ca04', 5) $$,
  'P0002', null, 'otro solicitante no puede calificar un pedido ajeno');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.calificar_pedido('00000000-0000-0000-0000-00000000ca04', 5) $$,
  'P0002', null, 'el domiciliario no puede calificarse a sí mismo');
select throws_ok($$ insert into public.calificaciones (pedido_id, repartidor_id, solicitante_id, estrellas)
  values ('00000000-0000-0000-0000-00000000ca04', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 5) $$,
  '42501', null, 'la app no puede insertar calificaciones directamente');
reset role;

select * from finish();
rollback;
