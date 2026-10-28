-- Datos base de prueba para DeskDrop (seed.sql)
-- Zonas y puntos de entrega del catálogo oficial (docs/zonas_campus_piloto.md §2).
-- Todos caen dentro del polígono de cobertura RN-002 (migración 20261028100400).

-- 1. Zonas del campus
INSERT INTO zonas_campus (id, nombre, descripcion) VALUES
('11111111-1111-1111-1111-111111111111', 'Sector Aulas y Laboratorios', 'Bloques de aulas y laboratorios principales'),
('22222222-2222-2222-2222-222222222222', 'Plazoleta de Comidas y Restaurantes', 'Plazoleta central, restaurantes y cafetería');

-- 2. Puntos de entrega
INSERT INTO puntos_entrega (zona_id, nombre, latitud, longitud, indicaciones) VALUES
('11111111-1111-1111-1111-111111111111', 'Bloque A - Hall de Entrada',            6.167200, -75.567100, 'En el hall principal frente a los ascensores y torniquetes del Bloque A'),
('11111111-1111-1111-1111-111111111111', 'Bloque B - Pasillo Central',            6.166800, -75.566800, 'Pasillo de conexión del Bloque B, bancas de descanso exteriores'),
('11111111-1111-1111-1111-111111111111', 'Bloque C - Entrada Principal',          6.166100, -75.566300, 'Graderías de acceso y plazoleta frontal del Bloque C'),
('22222222-2222-2222-2222-222222222222', 'Restaurante Lolita - Plazoleta Central', 6.166500, -75.566500, 'Zona de mesas frente al Restaurante Lolita y plazoleta comercial'),
('22222222-2222-2222-2222-222222222222', 'Punto de Encuentro Cafetería y Kiosco', 6.166400, -75.566900, 'Bancas exteriores contiguas a la zona de mesas y café');
