-- Pruebas de la auto-cancelación (T-043, RN-003): cancelar_pedidos_vencidos() y su job de pg_cron.
begin;
create extension if not exists pgtap with schema extensions;

-- Ids: a1-a6 solicitantes, b1 repartidor, c1 admin de comercio, d1 zona, e1 comercio, 11 punto.
-- Pedidos (ab0N es del solicitante aN), todos de 1.000 + 2.000 = 3.000:
--   ab01 Creado hace 11 min              -> se cancela
--   ab02 Creado hace 9 min               -> no se cancela (aún no vence)
--   ab03 Asignado hace 20 min (b1)       -> no se cancela (ya tiene domiciliario)
--   ab04 Creado hace 3 horas             -> se cancela (el job se retrasó)
--   ab05 Creado hace justo 10 min        -> se cancela (el límite es inclusivo)
--   ab06 En Camino hace 30 min (b1)      -> no se cancela
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

insert into public.comercios (id, administrador_id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Cafetería Test', true);

insert into public.zonas_campus (id, nombre, activo) values
  ('00000000-0000-0000-0000-0000000000d1', 'Zona Test Activa', true);

insert into public.puntos_entrega (id, zona_id, nombre, latitud, longitud, activo) values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000d1', 'Dentro del campus', 6.1670, -75.5670, true);

insert into public.pedidos (id, solicitante_id, repartidor_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total, creado_en) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-0000000000a1', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',    1000, 2000, 3000, now() - interval '11 minutes'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-0000000000a2', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',    1000, 2000, 3000, now() - interval '9 minutes'),
  ('00000000-0000-0000-0000-00000000ab03', '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Asignado',  1000, 2000, 3000, now() - interval '20 minutes'),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-0000000000a4', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',    1000, 2000, 3000, now() - interval '3 hours'),
  ('00000000-0000-0000-0000-00000000ab05', '00000000-0000-0000-0000-0000000000a5', null,
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'Creado',    1000, 2000, 3000, now() - interval '10 minutes'),
  ('00000000-0000-0000-0000-00000000ab06', '00000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000011', 'En Camino', 1000, 2000, 3000, now() - interval '30 minutes');

create function pg_temp.estado(p_id uuid) returns text language sql as $f$
  select estado::text from public.pedidos where id = p_id
$f$;

create function pg_temp.como(p_uid uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $f$;

select plan(22);

-- ---------------------------------------------------------------------------
-- Estructura, configuración y permisos
-- ---------------------------------------------------------------------------
select has_function('public', 'cancelar_pedidos_vencidos', array[]::name[],
  'existe public.cancelar_pedidos_vencidos()');
select is_definer('public', 'cancelar_pedidos_vencidos', array[]::name[],
  'cancelar_pedidos_vencidos() es SECURITY DEFINER');
select is(
  (select valor from public.configuracion where clave = 'minutos_auto_cancelacion'),
  10::numeric,
  'el tiempo límite por defecto es de 10 minutos (T-014)');
select ok(
  not has_function_privilege('anon', 'public.cancelar_pedidos_vencidos()', 'execute'),
  'anon no puede ejecutar cancelar_pedidos_vencidos()');
select ok(
  not has_function_privilege('authenticated', 'public.cancelar_pedidos_vencidos()', 'execute'),
  'authenticated no puede ejecutar cancelar_pedidos_vencidos()');
select is(
  (select schedule from cron.job where jobname = 'cancelar-pedidos-vencidos'),
  '* * * * *',
  'el job cancelar-pedidos-vencidos corre cada minuto');
select is(
  (select command from cron.job where jobname = 'cancelar-pedidos-vencidos'),
  'select public.cancelar_pedidos_vencidos()',
  'el job llama a cancelar_pedidos_vencidos()');

-- ---------------------------------------------------------------------------
-- Primera corrida
-- ---------------------------------------------------------------------------
select is(public.cancelar_pedidos_vencidos(), 3, 'la primera corrida cancela 3 pedidos');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ab01'), 'Cancelado',
  'se cancela el pedido Creado hace 11 minutos');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ab04'), 'Cancelado',
  'se cancela el pedido vencido hace horas aunque el job se haya retrasado');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ab05'), 'Cancelado',
  'se cancela el pedido que cumple justo el tiempo límite');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ab02'), 'Creado',
  'no se cancela el pedido Creado hace 9 minutos');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ab03'), 'Asignado',
  'no se cancela un pedido que ya tiene domiciliario');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ab06'), 'En Camino',
  'no se cancela un pedido En Camino');

select is(public.cancelar_pedidos_vencidos(), 0, 'una segunda corrida no cancela nada más');

-- El solicitante del pedido cancelado ya no tiene un pedido activo (RN-001) y puede pedir de nuevo
select lives_ok(
  $$ insert into public.pedidos (solicitante_id, comercio_id, punto_entrega_id, estado, subtotal, tarifa_domicilio, total)
     values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e1',
             '00000000-0000-0000-0000-000000000011', 'Creado', 1000, 2000, 3000) $$,
  'el solicitante del pedido cancelado puede crear otro');

-- ---------------------------------------------------------------------------
-- El tiempo límite es configurable
-- ---------------------------------------------------------------------------
update public.configuracion set valor = 5 where clave = 'minutos_auto_cancelacion';
select is(public.cancelar_pedidos_vencidos(), 1, 'con 5 minutos se cancela el pedido de 9 minutos');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ab02'), 'Cancelado',
  'el pedido de 9 minutos queda Cancelado al bajar el tiempo límite');

-- ---------------------------------------------------------------------------
-- Falla cerrado sin configuración válida
-- ---------------------------------------------------------------------------
update public.configuracion set valor = 0 where clave = 'minutos_auto_cancelacion';
select throws_like(
  $$ select public.cancelar_pedidos_vencidos() $$,
  'CONFIG_FALTANTE%',
  'con 0 minutos falla en vez de cancelar todo');

delete from public.configuracion where clave = 'minutos_auto_cancelacion';
select throws_like(
  $$ select public.cancelar_pedidos_vencidos() $$,
  'CONFIG_FALTANTE%',
  'sin la clave en configuracion falla en vez de cancelar');
select is(pg_temp.estado('00000000-0000-0000-0000-00000000ab03'), 'Asignado',
  'una corrida fallida no cambia ningún pedido');

-- ---------------------------------------------------------------------------
-- La app no puede llamarla
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select throws_ok(
  $$ select public.cancelar_pedidos_vencidos() $$,
  '42501', null,
  'un usuario autenticado no puede llamar cancelar_pedidos_vencidos()');
reset role;

select * from finish();
rollback;
