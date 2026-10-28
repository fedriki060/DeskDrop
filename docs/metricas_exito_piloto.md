# DeskDrop — Métricas de Éxito del Piloto (T-013)

**Historia de Usuario:** HU-02 — Fundamentos de Producto y Descubrimiento  
**Versión:** 1.0 (MVP)  
**Alcance del Piloto:** 1 cafetería piloto, 1 repartidor interno, comunidad de estudiantes/docentes del campus.

---

## 1. Objetivo del Piloto
Validar la viabilidad operativa y la aceptación del servicio de entregas internas en el campus universitario mediante un flujo con catálogo digital y pago manual en efectivo, asegurando tiempos de entrega competitivos y satisfacción de los usuarios.

---

## 2. Cuadro de Indicadores Clave de Rendimiento (KPIs)

| Dimensión | Métrica / KPI | Meta Mínima (MVP) | Justificación de Negocio |
| :--- | :--- | :--- | :--- |
| **Adopción** | Pedidos completados por día | $\ge 8$ pedidos/día | Demuestra demanda suficiente para mantener activo al repartidor. |
| **Retención** | Tasa de repetición de uso | $\ge 25\%$ | Usuarios que realizan más de 1 pedido durante la semana de prueba. |
| **Eficiencia Operativa** | Tiempo total de entrega (Lead Time) | $\le 20$ minutos | Desde que el pedido pasa a `Creado` hasta que queda en `Entregado`. |
| **Cumplimiento Logístico** | Tasa de cancelación | $\le 10\%$ de pedidos | Evitar cancelaciones por falta de repartidor disponible (RN-003). |
| **Calidad de Servicio** | Calificación promedio del repartidor | $\ge 4.2 / 5.0$ estrellas | Evalúa trato, puntualidad y estado del paquete al momento de la entrega. |
| **Económica** | Tasa de cobro exitoso (Efectivo) | $100\%$ | Ningún pedido entregado sin el registro de pago en la tabla `pagos`. |

---

## 3. Mecanismo Técnico de Medición (Consultas en Supabase)

Las métricas se calculan directamente desde las tablas PostgreSQL creadas en la migración inicial:

### A. Pedidos completados por día
```sql
SELECT 
    DATE(creado_en) AS fecha,
    COUNT(*) AS total_pedidos_entregados
FROM pedidos
WHERE estado = 'Entregado'
GROUP BY DATE(creado_en)
ORDER BY fecha DESC;

SELECT 
    AVG(EXTRACT(EPOCH FROM (actualizado_en - creado_en)) / 60)::NUMERIC(5,2) AS minutos_promedio_entrega
FROM pedidos
WHERE estado = 'Entregado';

SELECT 
    ROUND((COUNT(*) FILTER (WHERE estado = 'Cancelado')::NUMERIC / COUNT(*)) * 100, 2) AS porcentaje_cancelados
FROM pedidos;

SELECT 
    ROUND(AVG(estrellas), 2) AS calificacion_promedio_piloto,
    COUNT(*) AS total_evaluaciones
FROM calificaciones;
