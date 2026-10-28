-- Datos base de prueba para DeskDrop (seed.sql)

-- 1. Zonas del campus
INSERT INTO zonas_campus (id, nombre, descripcion) VALUES
('11111111-1111-1111-1111-111111111111', 'Zona Académica Norte', 'Bloques de aulas y laboratorios principales'),
('22222222-2222-2222-2222-222222222222', 'Zona Sur y Deportes', 'Coliseo, canchas y biblioteca');

-- 2. Puntos de entrega
INSERT INTO puntos_entrega (zona_id, nombre, latitud, longitud, indicaciones) VALUES
('11111111-1111-1111-1111-111111111111', 'Bloque 3 - Entrada Principal', 6.200100, -75.578100, 'Al lado de la recepción del bloque 3'),
('11111111-1111-1111-1111-111111111111', 'Laboratorio de Cómputo B', 6.200350, -75.578450, 'Puerta de vidrio exterior'),
('22222222-2222-2222-2222-222222222222', 'Biblioteca Central - Graderías', 6.198900, -75.577800, 'Bancas frente al ingreso principal');
