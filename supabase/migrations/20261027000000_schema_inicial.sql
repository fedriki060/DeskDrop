-- ==============================================================================
-- DESKDROP: MIGRACIÓN INICIAL (T-007)
-- ==============================================================================

-- 1. Tipos ENUM
CREATE TYPE rol_usuario AS ENUM ('solicitante', 'repartidor', 'comercio', 'admin');
CREATE TYPE estado_pedido AS ENUM ('Creado', 'Asignado', 'En Camino', 'Entregado', 'Cancelado', 'Cerrado');
CREATE TYPE estado_pago AS ENUM ('pendiente', 'cobrado', 'devuelto');
CREATE TYPE metodo_pago AS ENUM ('efectivo', 'transferencia', 'pasarela');

-- 2. Perfiles (vía Supabase Auth)
CREATE TABLE IF NOT EXISTS perfiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL UNIQUE,
    nombre_completo VARCHAR(255) NOT NULL,
    telefono VARCHAR(20),
    rol rol_usuario NOT NULL DEFAULT 'solicitante',
    calificacion_promedio NUMERIC(3,2) DEFAULT 5.00,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Comercios (Cafeterías)
CREATE TABLE IF NOT EXISTS comercios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    administrador_id UUID NOT NULL REFERENCES perfiles(id),
    nombre VARCHAR(150) NOT NULL,
    descripcion TEXT,
    horario_apertura TIME,
    horario_cierre TIME,
    activo BOOLEAN DEFAULT TRUE,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Productos
CREATE TABLE IF NOT EXISTS productos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id UUID NOT NULL REFERENCES comercios(id) ON DELETE CASCADE,
    nombre VARCHAR(150) NOT NULL,
    descripcion TEXT,
    precio NUMERIC(10,2) NOT NULL CHECK (precio >= 0),
    inventario_disponible INT NOT NULL DEFAULT 0 CHECK (inventario_disponible >= 0),
    activo BOOLEAN DEFAULT TRUE,
    imagen_url TEXT,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Zonas y Puntos de Entrega (RN-002)
CREATE TABLE IF NOT EXISTS zonas_campus (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    activo BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS puntos_entrega (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zona_id UUID NOT NULL REFERENCES zonas_campus(id) ON DELETE RESTRICT,
    nombre VARCHAR(150) NOT NULL,
    latitud NUMERIC(10,8) NOT NULL,
    longitud NUMERIC(11,8) NOT NULL,
    indicaciones TEXT,
    activo BOOLEAN DEFAULT TRUE
);

-- 6. Pedidos
CREATE TABLE IF NOT EXISTS pedidos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    solicitante_id UUID NOT NULL REFERENCES perfiles(id),
    repartidor_id UUID REFERENCES perfiles(id),
    comercio_id UUID NOT NULL REFERENCES comercios(id),
    punto_entrega_id UUID NOT NULL REFERENCES puntos_entrega(id),
    estado estado_pedido NOT NULL DEFAULT 'Creado',
    listo_para_recoger BOOLEAN DEFAULT FALSE,
    subtotal NUMERIC(10,2) NOT NULL CHECK (subtotal >= 0),
    tarifa_domicilio NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    total NUMERIC(10,2) NOT NULL CHECK (total >= 0),
    notas_entrega TEXT,
    creado_en TIMESTAMPTZ DEFAULT NOW(),
    actualizado_en TIMESTAMPTZ DEFAULT NOW()
);

-- RN-001 (Concurrencia): Solo un pedido activo por usuario
CREATE UNIQUE INDEX idx_un_pedido_activo_por_usuario 
ON pedidos (solicitante_id) 
WHERE estado IN ('Creado', 'Asignado', 'En Camino');

-- 7. Items del Pedido
CREATE TABLE IF NOT EXISTS items_pedido (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pedido_id UUID NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
    producto_id UUID NOT NULL REFERENCES productos(id),
    cantidad INT NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0)
);

-- 8. Pagos
CREATE TABLE IF NOT EXISTS pagos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pedido_id UUID NOT NULL UNIQUE REFERENCES pedidos(id) ON DELETE CASCADE,
    metodo metodo_pago NOT NULL DEFAULT 'efectivo',
    monto NUMERIC(10,2) NOT NULL CHECK (monto >= 0),
    estado estado_pago NOT NULL DEFAULT 'pendiente',
    registrado_por UUID REFERENCES perfiles(id),
    fecha_pago TIMESTAMPTZ
);

-- 9. Calificaciones
CREATE TABLE IF NOT EXISTS calificaciones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pedido_id UUID NOT NULL UNIQUE REFERENCES pedidos(id) ON DELETE CASCADE,
    repartidor_id UUID NOT NULL REFERENCES perfiles(id),
    solicitante_id UUID NOT NULL REFERENCES perfiles(id),
    estrellas INT NOT NULL CHECK (estrellas BETWEEN 1 AND 5),
    comentario TEXT,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);
