-- ==============================================================================
-- DESKDROP: AL CANCELAR UN PEDIDO SE REPONE EL INVENTARIO (T-044)
-- ==============================================================================
-- Trigger AFTER UPDATE OF estado sobre `pedidos`: cuando un pedido pasa a `Cancelado`
-- devuelve a cada producto las unidades de sus ítems.
--
--   * Misma transacción: un trigger corre dentro de la sentencia que cancela. Si la
--     reposición falla, la cancelación se revierte; no queda cancelado sin inventario.
--   * Aplica a CUALQUIER cancelación (cancelar_pedidos_vencidos, un UPDATE manual,
--     una función futura), como anticipa 20261107174000_auto_cancelacion.
--   * Una sola vez: Cancelado es final (matriz de transiciones) y el trigger solo se
--     dispara al ENTRAR a Cancelado, así que un pedido no repone dos veces.
--   * Sin deadlocks: bloquea los productos ordenados por id, igual que crear_pedido
--     (_evaluar_carrito), de modo que una compra y una cancelación simultáneas toman
--     los bloqueos en el mismo orden.
-- ==============================================================================

create or replace function public.trg_pedidos_reponer_inventario()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform 1
  from public.productos p
  where p.id in (select i.producto_id from public.items_pedido i where i.pedido_id = new.id)
  order by p.id
  for update;

  update public.productos p
  set inventario_disponible = p.inventario_disponible + x.cantidad
  from (
    select i.producto_id, sum(i.cantidad)::int as cantidad
    from public.items_pedido i
    where i.pedido_id = new.id
    group by i.producto_id
  ) x
  where p.id = x.producto_id;

  return null;
end;
$$;

revoke all on function public.trg_pedidos_reponer_inventario() from public, anon, authenticated;

drop trigger if exists trg_pedidos_reponer_inventario on public.pedidos;
create trigger trg_pedidos_reponer_inventario
  after update of estado on public.pedidos
  for each row
  when (new.estado = 'Cancelado' and old.estado is distinct from 'Cancelado')
  execute function public.trg_pedidos_reponer_inventario();
