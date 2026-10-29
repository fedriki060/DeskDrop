SET session_replication_role = replica;

--
-- PostgreSQL database dump
--

-- \restrict YeIROgGoGqjnBKNKlaEDw4d2FbIfxq5IABMDqBYRfEzKNrZVK5YoNvVgr0m8nox

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: comercios; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."comercios" ("id", "nombre", "descripcion", "horario_apertura", "horario_cierre", "activo", "creado_en", "tipo") VALUES
	('c0000000-0000-0000-0000-000000000001', 'Cafetería Central Bloque 1', 'Cafetería principal del campus: café, bebidas frías, empanadas, combos y snacks.', '07:00:00', '18:00:00', true, '2026-10-28 02:57:19.133525+00', 'restaurante');


--
-- Data for Name: zonas_campus; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."zonas_campus" ("id", "nombre", "descripcion", "activo") VALUES
	('11111111-1111-1111-1111-111111111111', 'Zona Aulas y Laboratorios', 'Bloques A, B y C del campus EIA', true),
	('22222222-2222-2222-2222-222222222222', 'Zona Restaurantes y Plazoleta', 'Restaurante Lolita, cafeterías y zonas comunes', true);


--
-- Data for Name: puntos_entrega; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."puntos_entrega" ("id", "zona_id", "nombre", "latitud", "longitud", "indicaciones", "activo") VALUES
	('adef3f9d-b6be-4b46-96fe-098278eb126d', '11111111-1111-1111-1111-111111111111', 'Bloque A - Hall de Entrada', 6.16720000, -75.56710000, 'Hall principal frente a ascensores del Bloque A', true),
	('68d8601a-8ee3-46cf-84d1-dedb68c51ea2', '11111111-1111-1111-1111-111111111111', 'Bloque B - Pasillo Central', 6.16680000, -75.56680000, 'Pasillo de conexión Bloque B, bancas exteriores', true),
	('e938da9e-2cea-45f1-aaf0-6ca3168460a8', '11111111-1111-1111-1111-111111111111', 'Bloque C - Entrada Principal', 6.16610000, -75.56630000, 'Graderías y plazoleta frontal Bloque C', true),
	('b560244f-2906-4db3-9bf5-9bf70de726fb', '22222222-2222-2222-2222-222222222222', 'Restaurante Lolita / Plazoleta', 6.16650000, -75.56650000, 'Zona de mesas frente a Restaurante Lolita', true),
	('3928a38a-89ba-4fc3-b54e-9ce8f8da3381', '22222222-2222-2222-2222-222222222222', 'Kiosco y Plazoleta de Comidas', 6.16640000, -75.56690000, 'Bancas exteriores contiguas a la zona de mesas', true);


--
-- Data for Name: pedidos; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: calificaciones; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: dominios_permitidos; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."dominios_permitidos" ("dominio") VALUES
	('eia.edu.co');


--
-- Data for Name: productos; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO "public"."productos" ("id", "comercio_id", "nombre", "descripcion", "precio", "inventario_disponible", "activo", "imagen_url", "creado_en") VALUES
	('52f064eb-dfe3-4516-ab2f-c4ba37c7e523', 'c0000000-0000-0000-0000-000000000001', 'Café Americano 8oz', 'Café negro caliente recién preparado', 2500.00, 30, true, 'https://images.unsplash.com/photo-1509042239860-f550ce710b93', '2026-10-28 02:57:19.133525+00'),
	('a168a1b9-298c-40be-bef4-3a864e52bfd1', 'c0000000-0000-0000-0000-000000000001', 'Café con Leche 8oz', 'Café tradicional con leche entera espumada', 3200.00, 25, true, 'https://images.unsplash.com/photo-1517256064527-09c73fc73e38', '2026-10-28 02:57:19.133525+00'),
	('a1221c5a-2ecc-45b9-9cd7-7fc1355fd859', 'c0000000-0000-0000-0000-000000000001', 'Capuchino Vainilla 12oz', 'Café expreso, leche vaporizada y toque de vainilla', 4500.00, 20, true, 'https://images.unsplash.com/photo-1534778101976-62847782c213', '2026-10-28 02:57:19.133525+00'),
	('12d35859-0700-45e2-9859-1efd3e98d6a6', 'c0000000-0000-0000-0000-000000000001', 'Empanada de Carne', 'Empanada crocante de maíz rellena de carne desmechada', 3000.00, 40, true, 'https://images.unsplash.com/photo-1628106235974-9842a129d280', '2026-10-28 02:57:19.133525+00'),
	('e6d9bce0-e2c4-452c-9b62-9c847f4b7997', 'c0000000-0000-0000-0000-000000000001', 'Empanada de Pollo y Champiñones', 'Empanada horneada con guiso suave de pollo', 3200.00, 35, true, 'https://images.unsplash.com/photo-1628106235974-9842a129d280', '2026-10-28 02:57:19.133525+00'),
	('cd167c5b-af6e-4cf3-8f46-7bfcc3f0a504', 'c0000000-0000-0000-0000-000000000001', 'Pastel de Pollo Hojaldrado', 'Hojaldre horneado relleno de pollo desmechado', 4200.00, 25, true, 'https://images.unsplash.com/photo-1608039829572-78524f79c4c7', '2026-10-28 02:57:19.133525+00'),
	('e704bb76-f1ef-4962-aa5c-ce028e00b9c9', 'c0000000-0000-0000-0000-000000000001', 'Sandwich Jamón y Queso Caliente', 'Pan artesanal, jamón seleccionado y doble queso mozzarella', 6500.00, 15, true, 'https://images.unsplash.com/photo-1528735602780-2552fd46c7af', '2026-10-28 02:57:19.133525+00'),
	('81abcbb5-0967-4bb4-9e4b-86844351e196', 'c0000000-0000-0000-0000-000000000001', 'Botella de Agua Cristal 600ml', 'Agua pura sin gas en botella PET', 2000.00, 50, true, 'https://images.unsplash.com/photo-1548839140-29a749e1bc4e', '2026-10-28 02:57:19.133525+00'),
	('cad35a77-b087-462f-9775-199ed499bb8b', 'c0000000-0000-0000-0000-000000000001', 'Jugo Natural en Agua 12oz', 'Sabores: Mora, Mango o Maracuyá', 4000.00, 20, true, 'https://images.unsplash.com/photo-1613478223719-2ab802602423', '2026-10-28 02:57:19.133525+00'),
	('7da7385c-dba6-4e4d-b00e-a232604c6a2d', 'c0000000-0000-0000-0000-000000000001', 'Gaseosa Coca-Cola Original 400ml', 'Bebida gaseosa personal bien fría', 3500.00, 30, true, 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97', '2026-10-28 02:57:19.133525+00');


--
-- Data for Name: items_pedido; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: pagos; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- PostgreSQL database dump complete
--

-- \unrestrict YeIROgGoGqjnBKNKlaEDw4d2FbIfxq5IABMDqBYRfEzKNrZVK5YoNvVgr0m8nox

RESET ALL;
