-- Pruebas de la auto-confirmación de entrega (T-042): en_camino_en, confirmar_entregas_vencidas() y su job.
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1-a6 solicitantes, b1 repartidor, c1 admin de comercio, d1 zona, e1 comercio, 11 punto.
-- Pedidos (ad0N es del solicitante aN), todos de 1.000 + 2.000 = 3.000, repartidor b1:
--   ad01 En Camino hace 16 min        -> se confirma
--   ad02 En Camino hace 14 min        -> no se confirma (aún no vence)
--   ad03 En Camino hace 3 horas       -> se confirma (el job se retrasó)
--   ad04 Asignado                     -> no se confirma; se usa para probar el trigger
--   ad05 Entregado                    -> no cambia
--   ad06 En Camino hace justo 15 min  -> se confirma (el límite es inclusivo)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000a6', 'sol6@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co');

insert into public.perfiles (id, email, nombre_completo, rol) values
  ('00000000-0000-0000-0000-0000000000a1', 'sol1@eia.edu.co', 'Solicitante Uno',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a2', 'sol2@eia.edu.co', 'Solicitante Dos',    'solicitante'),
  ('00000000-0000-0000-0000-0000000000a3', 'sol3@eia.edu.co', 'Solicitante Tres',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000a4', 'sol4@eia.edu.co', 'Solicitante Cuatro', 'solicitante'),
  ('00000000-0000-0000-0000-0000000000a5', 'sol5@eia.edu.co', 'Solicitante Cinco',  'solicitante'),
  ('00000000-0000-0000-0000-0000000000a6', 'sol6@eia.edu.co', 'Solicitante Seis',   'solicitante'),
  ('00000000-0000-0000-0000-0000000000b1', 'rep1@eia.edu.co', 'Repartidor Uno',     'repartidor'),
  ('00000000-0000-0000-0000-0000000000c1', 'com1@eia.edu.co', 'Admin Comercio 1',   'comercio')
on conflict (id) do update set rol = excluded.rol;

-- El repartidor de prueba ya aceptó la declaración de +18 (HU-19); sin ella no ve ni cobra pedidos.
insert into public.aceptaciones_repartidor (usuario_id, version) values
  ('00000000-0000-0000-0000-0000000000b1', 'test');

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);

insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);

insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total, en_camino_en) values
  ('00000000-0000-0000-0000-00000000ad01', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000, now() - interval '16 minutes'),
  ('00000000-0000-0000-0000-00000000ad02', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000, now() - interval '14 minutes'),
  ('00000000-0000-0000-0000-00000000ad03', '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000, now() - interval '3 hours'),
  ('00000000-0000-0000-0000-00000000ad04', '00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Asignado',  1000, 2000, 3000, null),
  ('00000000-0000-0000-0000-00000000ad05', '00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Entregado', 1000, 2000, 3000, now() - interval '2 hours'),
  ('00000000-0000-0000-0000-00000000ad06', '00000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000, now() - interval '15 minutes');

create function pg_temp.estado(p_id uuid) returns text language sql as $f$
  select estado::text from public.pedidos where id = p_id
$f$;

create function pg_temp.como(p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $f$;

select plan(26);

-- ---------------------------------------------------------------------------
-- Estructura, configuración y permisos
-- ---------------------------------------------------------------------------
select has_column('public', 'pedidos', 'en_camino_en', 'pedidos tiene la columna en_camino_en');
select has_trigger('public', 'pedidos', 'trg_pedidos_marcar_en_camino',
  'existe el trigger que marca la hora de salida');
select has_function('public', 'confirmar_entregas_vencidas', array[]::name[],
  'existe public.confirmar_entregas_vencidas()');
select is_definer('public', 'confirmar_entregas_vencidas', array[]::name[],
  'confirmar_entregas_vencidas() es SECURITY DEFINER');
select is(
  (select valor from public.configuracion where clave = 'minutos_auto_confirmacion'),
  15::numeric,
  'el tiempo límite por defecto es de 15 minutos (T-014)');
select ok(
  not has_function_privilege('anon', 'public.confirmar_entregas_vencidas()', 'execute')
  and not has_function_privilege('authenticated', 'public.confirmar_entregas_vencidas()', 'execute'),
  'ni anon ni authenticated pueden ejecutar confirmar_entregas_vencidas()');
select is(
  (select schedule from cron.job where jobname = 'confirmar-entregas-vencidas'),
  '* * * * *',
  'el job confirmar-entregas-vencidas corre cada minuto');
select is(
  (select command from cron.job where jobname = 'confirmar-entregas-vencidas'),
  'select public.confirmar_entregas_vencidas()',
  'el job llama a confirmar_entregas_vencidas()');

-- ---------------------------------------------------------------------------
-- El trigger marca la hora en que el pedido sale
-- ---------------------------------------------------------------------------
update public.pedidos set estado = 'En Camino' where id = '00000000-0000-0000-0000-00000000ad04';
select is(
  (select en_camino_en from public.pedidos where id = '00000000-0000-0000-0000-00000000ad04'),
  now(),
  'al pasar a En Camino se guarda la hora en en_camino_en');

update public.pedidos set notas_entrega = 'Timbre 2' where id = '00000000-0000-0000-0000-00000000ad02';
select is(
  (select en_camino_en from public.pedidos where id = '00000000-0000-0000-0000-00000000ad02'),
  now() - interval '14 minutes',
  'actualizar otra columna no cambia en_camino_en');

-- ---------------------------------------------------------------------------
-- Primera corrida
-- ---------------------------------------------------------------------------
select is(public.confirmar_entregas_vencidas(), 3, 'la primera corrida confirma 3 pedidos');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ad01'), 'Entregado',
  'se confirma el pedido que lleva 16 minutos En Camino');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ad03'), 'Entregado',
  'se confirma el pedido vencido hace horas aunque el job se haya retrasado');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ad06'), 'Entregado',
  'se confirma el pedido que cumple justo el tiempo límite');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ad02'), 'En Camino',
  'no se confirma el pedido que lleva 14 minutos En Camino');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ad04'), 'En Camino',
  'no se confirma el pedido que acaba de salir');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ad05'), 'Entregado',
  'un pedido ya Entregado no cambia');

select is(public.confirmar_entregas_vencidas(), 0, 'una segunda corrida no confirma nada más');

-- ---------------------------------------------------------------------------
-- Después de la auto-confirmación
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_like(
  $$ select public.confirmar_recepcion('00000000-0000-0000-0000-00000000ad01') $$,
  'ESTADO_NO_PERMITIDO%',
  'el solicitante ya no puede confirmar un pedido auto-confirmado');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select lives_ok(
  $$ select public.registrar_cobro_efectivo('00000000-0000-0000-0000-00000000ad01') $$,
  'el repartidor puede registrar el cobro de un pedido auto-confirmado');
reset role;

-- ---------------------------------------------------------------------------
-- El tiempo límite es configurable
-- ---------------------------------------------------------------------------
update public.configuracion set valor = 10 where clave = 'minutos_auto_confirmacion';
select is(public.confirmar_entregas_vencidas(), 1, 'con 10 minutos se confirma el pedido de 14 minutos');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ad02'), 'Entregado',
  'el pedido de 14 minutos queda Entregado al bajar el tiempo límite');

-- ---------------------------------------------------------------------------
-- Falla cerrado sin configuración válida
-- ---------------------------------------------------------------------------
update public.configuracion set valor = 0 where clave = 'minutos_auto_confirmacion';
select throws_like(
  $$ select public.confirmar_entregas_vencidas() $$,
  'CONFIG_FALTANTE%',
  'con 0 minutos falla en vez de confirmar todo');

delete from public.configuracion where clave = 'minutos_auto_confirmacion';
select throws_like(
  $$ select public.confirmar_entregas_vencidas() $$,
  'CONFIG_FALTANTE%',
  'sin la clave en configuracion falla en vez de confirmar');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ad04'), 'En Camino',
  'una corrida fallida no cambia ningún pedido');

-- ---------------------------------------------------------------------------
-- La app no puede llamarla
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a4');
select throws_ok(
  $$ select public.confirmar_entregas_vencidas() $$,
  '42501', null,
  'un usuario autenticado no puede llamar confirmar_entregas_vencidas()');
reset role;

select * from finish();
rollback;
