# ADR 002: Método de Captura de Ubicación en el Campus para Pedidos

- **Estado:** Aceptado
- **Fecha:** 2026-10-27
- **Responsable:** Samuel
- **Historia / Tarea:** HU-04 / T-021 (Spike)
- **Impacto directo:** Fede (T-026 - Pantalla de Ubicación en Expo) y Aguas (T-024 - Validación RN-002)

---

## 1. Contexto y Problema
En DeskDrop, los domicilios se realizan exclusivamente dentro del campus universitario. Para que el repartidor entregue el pedido con éxito, se requiere saber el punto exacto de encuentro. 

Necesitamos definir qué mecanismo utilizará la app móvil (Expo / React Native) considerando:
1. Precisión dentro de edificios y aulas.
2. Costos de APIs externas.
3. Experiencia de usuario (UX) y facilidad técnica para el MVP.

---

## 2. Opciones Evaluadas

### Opción A: GPS Nativo del Dispositivo (`expo-location`)
- **Cómo funciona:** Lee latitud y longitud actuales del smartphone del estudiante.
- **Ventajas:** Automático; un solo botón de "Usar mi ubicación".
- **Desventajas:**
  - En interiores (salones, sótanos, laboratorios) el error del GPS oscila entre 15 y 40 metros.
  - No discrimina pisos ni números de aula (ej. Bloque 3 Piso 4 vs. Bloque 3 Piso 1).
  - Exige permisos de ubicación que los usuarios pueden denegar.

### Opción B: Mapa Interactivo con Pin (`react-native-maps` / Google Maps / Mapbox)
- **Cómo funciona:** El usuario arrastra un marcador sobre un mapa satelital.
- **Ventajas:** Visualmente atractivo y flexible.
- **Desventajas:**
  - Complejidad alta de configuración con Expo Go (requiere llaves de API nativas en Android/iOS).
  - Costo por consumo de API si se superan cuotas gratuitas.
  - Sigue sin resolver el problema de entrega en salones específicos o puntos techados.

### Opción C: Selección de Puntos de Entrega Predefinidos (Elegida)
- **Cómo funciona:** La app lista zonas del campus (ej. "Zona Norte", "Zona Deportiva") y puntos de encuentro autorizados con nombre claro (ej. "Bloque 3 - Entrada Principal", "Biblioteca - Graderías") acompañados de un campo opcional de texto: *"Notas adicionales"* (ej. "Mesa 4 al fondo").
- **Ventajas:**
  - **100% de precisión operativa:** El repartidor y el cliente se encuentran en un punto visible sin confusiones.
  - **Cero costo de APIs de mapas:** No se pagan llamadas a Google Maps ni Mapbox.
  - **Alineación directa con la Base de Datos:** Se conecta inmediatamente con las tablas `zonas_campus` y `puntos_entrega` creadas en Supabase (`T-007`).
  - **Cumplimiento RN-002:** Todo punto predefinido ya está validado dentro del perímetro del campus.

---

## 3. Decisión Adoptada
Se adopta la **Opción C: Lista de Puntos Predefinidos por Zonas**.

Para fases futuras (Entrega 2 o 3), se podrá complementar permitiendo que el GPS sugiera automáticamente el punto predefinido más cercano, pero la selección final siempre será sobre un punto de encuentro oficial.

---

## 4. Guía de Implementación para el Equipo

1. **Para Fede en Frontend (`T-026`):**
   - Diseñar la pantalla de selección con un selector desplegable o lista agrupada por Zona.
   - Cada tarjeta muestra el nombre del punto (ej. *Bloque 3 - Entrada*) y las indicaciones de referencia.
   - Incluir un campo `input` de texto: *"Indicaciones extra para el repartidor (opcional)"*.
2. **Para Aguas en Backend (`T-024`):**
   - Al llamar a `crear_pedido`, validar que el `punto_entrega_id` pertenezca a un punto con `activo = true` en la tabla `puntos_entrega`.
