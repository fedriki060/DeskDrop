-- Migración sincronizada con Supabase Cloud: Zonas, Puntos EIA y Comercios
CREATE TABLE IF NOT EXISTS public.zonas_campus (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    activo BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS public.puntos_entrega (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zona_id UUID NOT NULL REFERENCES public.zonas_campus(id) ON DELETE RESTRICT,
    nombre VARCHAR(150) NOT NULL,
    latitud NUMERIC(10,8) NOT NULL,
    longitud NUMERIC(11,8) NOT NULL,
    indicaciones TEXT,
    activo BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS public.comercios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(150) NOT NULL,
    descripcion TEXT,
    horario_apertura TIME,
    horario_cierre TIME,
    activo BOOLEAN DEFAULT TRUE,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.productos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id UUID NOT NULL REFERENCES public.comercios(id) ON DELETE CASCADE,
    nombre VARCHAR(150) NOT NULL,
    descripcion TEXT,
    precio NUMERIC(10,2) NOT NULL CHECK (precio >= 0),
    inventario_disponible INT NOT NULL DEFAULT 0 CHECK (inventario_disponible >= 0),
    activo BOOLEAN DEFAULT TRUE,
    imagen_url TEXT,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);
