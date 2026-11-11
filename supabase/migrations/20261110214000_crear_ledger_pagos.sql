-- 1. Definir los tipos de movimientos estrictos para el modelo de captura diferida
CREATE TYPE tipo_movimiento_financiero AS ENUM (
    'autorizacion', -- Congela el saldo en la tarjeta del usuario al crear pedido
    'captura',      -- Cobra el saldo efectivamente tras confirmar la entrega
    'anulacion',    -- Libera el saldo congelado si se cancela el pedido antes de la entrega
    'reembolso'     -- Devuelve el dinero si la captura ya se había ejecutado
);

-- 2. Crear la tabla inmutable de movimientos (Ledger)
CREATE TABLE ledger_pagos (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    pedido_id UUID NOT NULL REFERENCES pedidos(id) ON DELETE RESTRICT,
    tipo_movimiento tipo_movimiento_financiero NOT NULL,
    monto NUMERIC(10,2) NOT NULL CHECK (monto > 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'completado',
    referencia_pasarela VARCHAR(255) NOT NULL, -- ID devuelto por Wompi/Stripe
    creado_en TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now())
);

-- 3. Crear índice para optimizar las consultas por pedido
CREATE INDEX idx_ledger_pedido ON ledger_pagos(pedido_id);

-- 4. Aplicar Seguridad de Nivel de Fila (RLS)
ALTER TABLE ledger_pagos ENABLE ROW LEVEL SECURITY;

-- Políticas: Los usuarios solo pueden LEER los movimientos de sus propios pedidos.
-- La ESCRITURA queda bloqueada para la app; solo las Edge Functions (Service Role) insertarán datos aquí.
CREATE POLICY "Solicitantes leen movimientos de sus pedidos"
ON ledger_pagos FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM pedidos
        WHERE pedidos.id = ledger_pagos.pedido_id
     AND pedidos.solicitante_id = auth.uid()
    )
);
