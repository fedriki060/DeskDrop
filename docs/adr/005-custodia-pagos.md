# ADR 005: Custodia, liberación y reembolso del pago digital

- **Estado:** Propuesto
- **Migraciones:** `20261111100400` (enum) y `20261111100500` (lógica)
- **Edge Function:** `supabase/functions/retener-pago`

## Contexto

El pago por transferencia debe protegerse: el dinero no puede llegar al domiciliario hasta
que el pedido se entregue, ni quedarse en la plataforma si el pedido se cancela.

## Decisión

Ciclo del pago digital (el efectivo sigue siendo `pendiente -> cobrado`):

```
pendiente --(pago aprobado)--> en_custodia --(pedido Entregado)--> liberado
                                    └--------(pedido Cancelado)--> devuelto
```

| Paso | Quién lo dispara | Dónde |
|---|---|---|
| Retener | Webhook de la pasarela o un admin, vía la Edge Function `retener-pago` | `retener_pago()` (solo `service_role`) |
| Liberar (RN-004) | Trigger al pasar el pedido a `Entregado` (lo confirme el solicitante, la auto-confirmación o un UPDATE) | `trg_pedidos_liberar_fondos` |
| Reembolsar | Trigger al pasar a `Cancelado`, incluida la auto-cancelación de T-043 | `trg_pedidos_devolver_pago` |

Cada paso queda en `movimientos_pago` (máximo un movimiento de cada tipo por pago, lo que hace
idempotentes los reintentos del webhook). Los triggers corren en la misma transacción que el
cambio de estado: si fallan, el cambio se revierte.

## Supuestos a confirmar

- **RN-004 no está escrita en `docs/`.** Se interpretó como: al `Entregado` se libera al
  domiciliario el monto retenido. El desglose (80 % de la tarifa al domiciliario, 20 % a la
  plataforma, subtotal al comercio) queda en `movimientos_pago.detalle`.
- **Todavía no hay pasarela.** Los movimientos son el registro contable; mover dinero real
  (devolver por Nequi/Bancolombia, pagar al domiciliario) es un paso manual o de la pasarela
  que se integre. `pasarela` sigue rechazado en `crear_pedido`.

## Configuración de la Edge Function

```bash
cp supabase/functions/.env.example supabase/functions/.env   # y pon PAGOS_WEBHOOK_SECRET
npx supabase functions serve --env-file supabase/functions/.env
npx supabase secrets set PAGOS_WEBHOOK_SECRET=<valor>        # staging / producción
npx supabase functions deploy retener-pago
```

Prueba local:

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/retener-pago \
  -H "x-webhook-secret: <PAGOS_WEBHOOK_SECRET>" -H "Content-Type: application/json" \
  -d '{"pedido_id":"<uuid>","referencia":"PASARELA-001"}'
```
