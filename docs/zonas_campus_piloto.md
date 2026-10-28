# Delimitación del Campus y Puntos de Entrega — DeskDrop (T-033)

**Historia de Usuario:** HU-07 / HU-04 (RN-002: Cobertura)  
**Institución:** Universidad EIA — Sede Las Palmas (Envigado, Antioquia)  
**Estado:** Aprobado para Piloto / MVP  

---

## 1. Polígono de Cobertura del Campus EIA (RN-002)

Para validar que un pedido se realice estrictamente dentro de las instalaciones autorizadas de la Universidad EIA (Sede Las Palmas), se establece el polígono envolvente mediante 4 vértices geográficos:

| Vértice | Ubicación de Referencia | Latitud | Longitud |
| :--- | :--- | :--- | :--- |
| **V1 (Noroeste)** | Límite Norte / Vía de Acceso Las Palmas | `6.169000` | `-75.568500` |
| **V2 (Noreste)** | Portería Principal y Parqueadero Visitantes | `6.169000` | `-75.564500` |
| **V3 (Sureste)** | Límite Bloque C y Canchas Deportivas | `6.164500` | `-75.564500` |
| **V4 (Suroeste)** | Reserva Forestal / Límite Occidental | `6.164500` | `-75.568500` |

*Cualquier coordenada seleccionada por la app móvil fuera de este cuadrante geográfico será rechazada automáticamente con error de cobertura según la regla de negocio RN-002.*

---

## 2. Catálogo Oficial de Zonas y Puntos de Entrega

De acuerdo con la arquitectura definida en el Spike de Ubicación (**T-021 / ADR 002**), el servicio opera mediante puntos predefinidos de fácil reconocimiento para el repartidor y el solicitante:

### Zona 1: Sector Aulas y Laboratorios
- **Punto 1:** Bloque A — Hall de Entrada
  - *Latitud / Longitud:* `6.167200`, `-75.567100`
  - *Indicaciones:* En el hall principal frente a los ascensores y torniquetes del Bloque A.
- **Punto 2:** Bloque B — Pasillo Central
  - *Latitud / Longitud:* `6.166800`, `-75.566800`
  - *Indicaciones:* Pasillo de conexión del Bloque B, bancas de descanso exteriores.
- **Punto 3:** Bloque C — Entrada Principal
  - *Latitud / Longitud:* `6.166100`, `-75.566300`
  - *Indicaciones:* Graderías de acceso y plazoleta frontal del Bloque C.

### Zona 2: Plazoleta de Comidas y Restaurantes
- **Punto 4:** Restaurante Lolita / Plazoleta Central
  - *Latitud / Longitud:* `6.166500`, `-75.566500`
  - *Indicaciones:* Zona de mesas frente al Restaurante Lolita y plazoleta comercial.
- **Punto 5:** Punto de Encuentro Cafetería y Kiosco
  - *Latitud / Longitud:* `6.166400`, `-75.566900`
  - *Indicaciones:* Bancas exteriores contiguas a la zona de mesas y café.

---

## 3. Integración con el Sistema y Frontend
- **Base de Datos (Supabase):** Estos puntos alimentan la tabla `puntos_entrega` vinculados a sus respectivas zonas en `zonas_campus`.
- **Frontend (Fede - T-026):** Se cargan como tarjetas agrupadas por zona (Aulas vs. Zona de Restaurantes) para que el estudiante elija con un solo toque.
- **Backend (Aguas - T-024):** Valida que el `punto_entrega_id` pertenezca al catálogo activo antes de permitir `crear_pedido`.
