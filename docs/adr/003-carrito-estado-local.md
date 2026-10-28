# ADR 003: Carrito en estado local y contrato de pedidos

- **Estado:** Propuesta
- **Fecha:** 2026-10-28
- **Relacionado con:** RF-001 / CU-001 (crear pedido), RN-001, RN-002 (ADR 002), RN-003, T-024, T-032, T-043
- **Código:** `supabase/migrations/20261028100000` a `20261028100300`

---

## 1. Contexto

El solicitante arma un pedido con productos de **un solo comercio**. Hay que decidir dónde vive el carrito antes de confirmar y cómo se garantiza que el inventario alcance cuando varias personas piden a la vez. El piloto tiene 1 cafetería y presupuesto $0, así que se prefiere la solución más simple que no comprometa la integridad.

## 2. Decisión

**El carrito vive en el estado local de la app** (`CarritoContext`, ya implementado) y no se guarda en la base. La base solo conoce el pedido cuando el usuario lo confirma. Por eso **nunca confía en el carrito**: vuelve a leer precios, existencia e inventario.

Forma del carrito al enviarlo (arreglo JSON):

```ts
type ItemCarritoRpc = { producto_id: string; cantidad: number }; // cantidad: entero 1..999999

const payload = items.map((i) => ({ producto_id: i.producto.id, cantidad: i.cantidad }));
```

Dos funciones SQL, con responsabilidades distintas:

| Función | Para qué | Bloquea inventario | Quién la llama |
| :--- | :--- | :---: | :--- |
| `validar_carrito(p_items)` | Avisar al usuario **antes** de pagar (inventario, un solo comercio, productos vigentes). Solo lectura. | No | App, al abrir/confirmar el carrito |
| `crear_pedido(p_punto_entrega_id, p_items, p_notas_entrega)` | Crear el pedido y descontar inventario en **una sola transacción**. Es la validación que manda. | Sí (`FOR UPDATE`) | App, al confirmar |

`validar_carrito` puede dar "válido" y que `crear_pedido` igual falle si otra persona se llevó la última unidad entre las dos llamadas. Es esperado: la app debe tratar el error de `crear_pedido` como definitivo.

### Respuesta de `validar_carrito`

```json
{ "valido": true, "comercio_id": "…", "subtotal": 47000, "tarifa_domicilio": 2000, "total": 49000,
  "items": [{ "producto_id": "…", "nombre": "…", "cantidad": 2, "precio_unitario": 22000, "subtotal": 44000 }],
  "errores": [] }
```

Si no es válido, `subtotal`/`total` vienen en `null` y `errores` trae objetos `{ codigo, mensaje, producto_id?, solicitado?, disponible? }`.

| Código | Significado |
| :--- | :--- |
| `CARRITO_VACIO` | Arreglo vacío o nulo |
| `FORMATO_INVALIDO` | No es un arreglo |
| `ITEM_INVALIDO` | `producto_id` no es UUID o `cantidad` no es entero > 0 |
| `CARRITO_DEMASIADO_GRANDE` | Más de 50 líneas |
| `PRODUCTO_NO_DISPONIBLE` | No existe, está inactivo o su comercio está inactivo |
| `INVENTARIO_INSUFICIENTE` | `solicitado` > `disponible` (suma las líneas repetidas) |
| `COMERCIOS_DISTINTOS` | Productos de más de un comercio |

### Errores de `crear_pedido`

Llegan como excepción: `error.message` empieza por el código y, en `CARRITO_INVALIDO`, `error.details` trae el JSON de `errores`.

`NO_AUTENTICADO` · `ROL_NO_PERMITIDO` · `PUNTO_ENTREGA_INVALIDO` · `NOTAS_DEMASIADO_LARGAS` (máx. 500) · `PEDIDO_ACTIVO_EXISTENTE` · `CARRITO_INVALIDO`

Total del pedido: `SUM(precio_unitario * cantidad) + 2.000` (tarifa fija del piloto, `docs/reglas_negocio_piloto.md`).

### Estados del pedido

```
Creado ──► Asignado ──► En Camino ──► Entregado ──► Cerrado
  │           │
  └───────────┴──────► Cancelado        (Cancelado y Cerrado son finales)
```

`transicion_pedido_permitida(desde, hasta)` define la matriz y un trigger en `pedidos` la hace cumplir para **todos** los roles (incluidos `pg_cron` y `service_role`). Una transición inválida lanza `TRANSICION_INVALIDA` (SQLSTATE `23514`). El mismo trigger renueva `actualizado_en`.

## 3. Alternativas consideradas

| Opción | Por qué no |
| :--- | :--- |
| **Carrito en una tabla (`carritos`, `items_carrito`)** | Más tablas, RLS y limpieza de carritos abandonados, para un piloto de 1 comercio. El valor (retomar el carrito en otro dispositivo) no lo justifica ahora. |
| **Reservar inventario al agregar al carrito** | Los carritos abandonados bloquearían stock y haría falta un job de expiración. |
| **Validar solo en la app** | La app puede estar desactualizada o ser manipulada; el ADR 001 exige que las reglas críticas vivan en la base. |

## 4. Consecuencias y pendientes

- El carrito **se pierde al cerrar la app**. Si molesta, guardarlo localmente en el dispositivo no cambia el contrato.
- El inventario que muestra la app puede estar desactualizado; por eso `validar_carrito` debe llamarse antes de "Ir a pagar".
- **Cancelar no repone inventario por sí solo.** La tarea de auto-cancelación (T-043) debe sumar de vuelta `items_pedido.cantidad` en la misma transacción que pasa el pedido a `Cancelado`.
- `Asignado → Cancelado` es un **supuesto** (los documentos solo definen `Creado → Cancelado`). Si no se desea, se quita de `transicion_pedido_permitida`.
- Aún sin políticas (denegado por defecto): `perfiles`, `zonas_campus`, `puntos_entrega`, `pagos`, `calificaciones`, y la lectura de pedidos `Creado` por parte de los repartidores. Cada una llega con su tarea.
- La app todavía usa mocks (`catalogService.ts`). Al conectarla a Supabase los ids pasan a ser UUID y `inventario_disponible` reemplaza a `inventario`.
