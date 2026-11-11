-- ==============================================================================
-- DESKDROP: EL DOMICILIARIO LISTA LOS PEDIDOS DISPONIBLES (estado Creado)
-- ==============================================================================
-- La regla de lectura por rol YA vive en `roles_rls` (política ver_pedidos_por_rol) y no se
-- redefine aquí, para tener una sola fuente de verdad:
--
--   * Solicitante: los suyos.
--   * Repartidor : los asignados a él + los disponibles (estado Creado y sin repartidor).
--   * Comercio   : los de su comercio.
--   * Admin      : todos.
--
-- Esta migración solo agrega el índice que hace barata la consulta de "disponibles".
-- Los ítems y el pago de un pedido disponible se leen con las políticas
-- ver_items_de_mis_pedidos / ver_pagos_de_mis_pedidos (siguen la visibilidad del pedido).
--
-- Consulta desde la app (el domiciliario; RLS ya filtra, el .eq solo la hace explícita):
--   supabase.from('pedidos')
--     .select('id, total, creado_en, comercios(nombre), puntos_entrega(nombre), items_pedido(cantidad, productos(nombre))')
--     .eq('estado', 'Creado').is('repartidor_id', null)
--     .order('creado_en')
-- ==============================================================================

create index if not exists idx_pedidos_disponibles
  on public.pedidos (creado_en)
  where estado = 'Creado' and repartidor_id is null;
