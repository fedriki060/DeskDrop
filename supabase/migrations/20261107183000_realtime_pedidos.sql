-- ==============================================================================
-- DESKDROP: CAMBIOS DE ESTADO DEL PEDIDO EN VIVO CON SUPABASE REALTIME (T-046)
-- ==============================================================================
-- Se publica la tabla `pedidos` en `supabase_realtime`. Cada vez que se crea un pedido o
-- cambia su estado, Realtime (Postgres Changes) lo envía a los clientes suscritos.
--
-- Quién recibe cada evento lo decide la política de lectura `ver_pedidos_por_rol`
-- (roles_rls): Realtime revisa la RLS de cada suscriptor contra la fila NUEVA.
--   * Solicitante: solo sus pedidos.
--   * Repartidor: los que tiene asignados y los disponibles (Creado sin repartidor).
--   * Comercio: los pedidos de sus comercios.
--   * Admin: todos.
--   * anon: nada (no tiene SELECT sobre pedidos).
--
-- Consecuencia a tener en cuenta en la app: cuando un repartidor toma un pedido, los
-- demás repartidores dejan de poder verlo y por eso NO reciben ese UPDATE. La lista de
-- disponibles debe quitar el pedido si aceptar_pedido falla o refrescarse al volver.
--
-- Uso desde la app (supabase-js):
--   supabase.channel(`pedido-${id}`)
--     .on('postgres_changes',
--         { event: 'UPDATE', schema: 'public', table: 'pedidos', filter: `id=eq.${id}` },
--         (cambio) => console.log(cambio.new.estado))
--     .subscribe();
--
-- No se publican items_pedido ni pagos: el seguimiento solo necesita el estado.
-- ==============================================================================

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  -- `alter publication ... add table` falla si la tabla ya está: la migración se puede repetir.
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pedidos'
  ) then
    alter publication supabase_realtime add table public.pedidos;
  end if;
end $$;
