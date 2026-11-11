# Demo del flujo físico (pago en efectivo + código de entrega)

## Antes de empezar

1. Aplicar las migraciones a staging (`supabase db push`). Deben estar todas, en especial las de
   `20261110200000` a `20261110250000` (modo repartidor, código de entrega, aceptar/recoger,
   número de pedido, entrega en curso, cancelar pedido). Sin ellas la app falla.
2. Cuentas de prueba (todas con contraseña temporal, dominio permitido):
   - **Comercio:** crear con `supabase/alta_comercio.sql` (ver pasos al inicio del archivo).
   - **Solicitante:** registrarse desde la app con un correo institucional.
   - **Domiciliario:** un segundo usuario solicitante que active "Modo domiciliario" en Perfil
     (declaración de mayoría de edad, 18+). Para el demo conviene tener dos dispositivos o dos
     sesiones: no se puede aceptar el propio pedido.
3. El comercio debe tener "Recibiendo pedidos" activado y productos con inventario.

## Guion (≈ 5 minutos)

| # | Quién | Acción | Qué se ve |
|---|-------|--------|-----------|
| 1 | Solicitante | Elegir comercio, agregar productos, escoger punto de entrega y confirmar | Pedido creado; en Inicio aparece el seguimiento |
| 2 | Comercio | Abrir Pedidos | El pedido llega solo (sin recargar) y suma en la insignia |
| 3 | Comercio | "Listo para recoger" | El estado se actualiza en la bandeja |
| 4 | Domiciliario | Cambiar a vista Domiciliario → Entregas → "Aceptar" | Solicitante ve **Asignado** en vivo |
| 5 | Domiciliario | "Ya lo recogí" | Solicitante ve **En camino** en vivo |
| 6 | Solicitante | Ver el código de 4 dígitos en el seguimiento | Solo él puede verlo |
| 7 | Domiciliario | Escribir un código incorrecto | "Código incorrecto. Te quedan 4 intentos." |
| 8 | Domiciliario | Escribir el código correcto | Pedido **Entregado** |
| 9 | Domiciliario | "Ya cobré" (efectivo) | Pago registrado como cobrado |
| 10 | Domiciliario | Pestaña "Mis entregas" | Total estimado ganado y efectivo cobrado |
| 11 | Solicitante | En Inicio, calificar al domiciliario (1 a 5 estrellas y comentario) | "¡Gracias por calificar!"; la próxima vez que pida, verá su promedio con el contacto |

## Casos extra para mostrar

- **Rechazo del comercio:** "Rechazar pedido" → el solicitante ve el pedido cancelado con el motivo y el
  inventario se repone.
- **Cancelación del solicitante:** desde el seguimiento, mientras el pedido no esté en camino.
- **Código perdido:** el solicitante usa "Generar nuevo código".
- **Cinco intentos fallidos:** el código se bloquea; se puede regenerar o el pedido se confirma solo a los 60 min.
- **Una entrega a la vez:** un domiciliario con entrega en curso no puede aceptar otra.

## Prueba automática

`npm run test:db` (pgTAP) y `npm run test:integration` (incluye `tests/integration/flujo_fisico.test.ts`,
el flujo completo con Realtime). Requieren `npx supabase start`.
