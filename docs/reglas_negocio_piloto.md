# DeskDrop — Reglas y Valores de Negocio del Piloto (T-014)

**Historia de Usuario:** HU-02 — Fundamentos de Producto y Descubrimiento  
**Dependencia:** T-011 (Entrevistas a Solicitantes)  
**Impacto en Desarrollo:** Aguas (T-032 - Cálculo de Totales, T-042 - Auto-confirmación, T-043 - Auto-cancelación)  
**Estado:** Aprobado para MVP (Entrega 1)

---

## 1. Definición de Parámetros Operativos y Financieros

Con base en los hallazgos del levantamiento con estudiantes en el campus EIA (T-011), se fijan los siguientes valores oficiales:

| Parámetro de Negocio | Valor Oficial (MVP) | Justificación de Negocio / Técnico |
| :--- | :---: | :--- |
| **Tarifa de Domicilio Fija** | **$2.000 COP** | Valor consensuado en entrevistas (T-011) como accesible para el estudiante y atractivo para el repartidor. |
| **Reparto de la Tarifa de Envío** | **80% Repartidor / 20% Plataforma** | De los $2.000 COP: **$1.600 COP** para el domiciliario por carrera interna y **$400 COP** de fondo operativo de plataforma. |
| **Margen sobre Comercio / Alimentos** | **0% (Fase Piloto)** | Para incentivar la vinculación de la cafetería/restaurante piloto sin fricción comercial inicial. |
| **Tiempo límite de auto-cancelación** | **10 minutos** | Si un pedido en estado `Creado` no es tomado por ningún repartidor en 10 min, pasa a `Cancelado` (RN-003) y se libera el inventario. |
| **Tiempo límite de auto-confirmación** | **15 minutos** | Tras pasar a `En Camino`, si el solicitante no presiona *"Ya recibí mi pedido"*, el sistema asume entrega conforme y lo pasa a `Entregado`. |

---

## 2. Parámetros Técnicos para Base de Datos y Backend

Para que Aguas implemente las funciones SQL y tareas programadas (`pg_cron`):

1. **Cálculo del Total (`T-032`):**
   ```text
   total_pedido = SUM(precio_unitario * cantidad) + 2000.00

   Condición: estado = 'Creado' AND creado_en <= NOW() - INTERVAL '10 minutes'
Acción: Transición atómica a 'Cancelado' y reposición de inventario_disponible en tabla productos.

Condición: estado = 'En Camino' AND actualizado_en <= NOW() - INTERVAL '15 minutes'
Acción: Transición atómica a 'Entregado' habilitando el flujo de cobro/cierre.
