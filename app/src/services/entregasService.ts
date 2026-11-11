import { supabase } from '../lib/supabase';

// Acciones del domiciliario sobre un pedido (HU-21). La app no escribe en `pedidos`: el cambio
// de estado lo hacen estas funciones de la base, que validan quién y cuándo.

export type ResultadoEntrega = { ok: true } | { ok: false; mensaje: string };

const MENSAJES: Record<string, string> = {
  NO_AUTENTICADO: 'Tu sesión expiró. Vuelve a iniciar sesión.',
  ROL_NO_PERMITIDO: 'Activa la vista de domiciliario desde tu perfil.',
  PEDIDO_NO_ENCONTRADO: 'No encontramos este pedido entre tus entregas.',
  PEDIDO_PROPIO: 'No puedes entregarte tu propio pedido.',
  PEDIDO_NO_DISPONIBLE: 'Otro domiciliario ya tomó este pedido.',
  ESTADO_NO_PERMITIDO: 'El pedido ya cambió de estado. Actualiza la lista.',
  PEDIDO_NO_LISTO: 'El comercio aún no marca el pedido como listo para recoger.',
};

async function ejecutar(funcion: 'aceptar_pedido' | 'confirmar_recogida', pedidoId: string): Promise<ResultadoEntrega> {
  const { error } = await supabase.rpc(funcion, { p_pedido_id: pedidoId });
  if (error) {
    const codigo = error.message.split(':')[0].trim();
    console.warn(`[entregas] ${funcion}:`, error.code, error.message);
    return { ok: false, mensaje: MENSAJES[codigo] ?? 'No se pudo completar la acción. Intenta de nuevo.' };
  }
  return { ok: true };
}

/** El domiciliario toma un pedido disponible (Creado -> Asignado). */
export const aceptarPedido = (pedidoId: string) => ejecutar('aceptar_pedido', pedidoId);

/** El domiciliario confirma que recogió el pedido en el comercio (Asignado -> En Camino). */
export const confirmarRecogida = (pedidoId: string) => ejecutar('confirmar_recogida', pedidoId);
