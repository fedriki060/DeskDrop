-- ==============================================================================
-- DESKDROP: NUEVOS ESTADOS DEL PAGO — EN CUSTODIA Y LIBERADO
-- ==============================================================================
-- Va en un archivo aparte porque Postgres no permite usar un valor nuevo de un enum en la
-- misma transacción que lo agrega. La lógica que los usa está en 20261111100500.
--
-- Ciclo del pago digital (transferencia):
--   pendiente -> en_custodia -> liberado      (el pedido llega a Entregado)
--                    └──────-> devuelto       (el pedido se cancela: reembolso)
-- El pago en efectivo sigue siendo pendiente -> cobrado (no pasa por custodia).
-- ==============================================================================
alter type public.estado_pago add value if not exists 'en_custodia';
alter type public.estado_pago add value if not exists 'liberado';
