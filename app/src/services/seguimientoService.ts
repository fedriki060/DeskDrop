import { supabase } from '../lib/supabase';
import { EstadoPedido } from '../types';

// Seguimiento en vivo con Supabase Realtime (T-046). La base solo envía los cambios de los
// pedidos que la RLS deja ver al usuario (migración realtime_pedidos).

export type CambioPedido = {
  id: string;
  estado: EstadoPedido;
  repartidorId: string | null;
  listoParaRecoger: boolean;
  actualizadoEn: string;
};

type FilaPedido = {
  id: string;
  estado: EstadoPedido;
  repartidor_id: string | null;
  listo_para_recoger: boolean | null;
  actualizado_en: string;
};

/**
 * Escucha los cambios de un pedido (estado, repartidor asignado, listo para recoger).
 * Devuelve una función para dejar de escuchar; llámala al salir de la pantalla.
 *
 * Ejemplo en una pantalla:
 *   useEffect(() => escucharPedido(id, (c) => setEstado(c.estado)), [id]);
 */
export function escucharPedido(pedidoId: string, alCambiar: (cambio: CambioPedido) => void): () => void {
  const canal = supabase
    .channel(`pedido-${pedidoId}`)
    .on(
      'postgres_changes',
      { event: 'UPDATE', schema: 'public', table: 'pedidos', filter: `id=eq.${pedidoId}` },
      (evento) => {
        const fila = evento.new as FilaPedido;
        alCambiar({
          id: fila.id,
          estado: fila.estado,
          repartidorId: fila.repartidor_id,
          listoParaRecoger: fila.listo_para_recoger ?? false,
          actualizadoEn: fila.actualizado_en,
        });
      }
    )
    .subscribe();

  return () => {
    supabase.removeChannel(canal);
  };
}


// ---------------------------------------------------------------------------
// Confirmar que el pedido llegó (T-040). Solo el solicitante dueño y con el pedido En Camino.
// ---------------------------------------------------------------------------

const MENSAJES_CONFIRMAR: Record<string, string> = {
  NO_AUTENTICADO: 'Tu sesión expiró. Vuelve a iniciar sesión.',
  PEDIDO_NO_ENCONTRADO: 'No encontramos este pedido en tu cuenta.',
  ESTADO_NO_PERMITIDO: 'Solo puedes confirmar el pedido cuando ya va en camino.',
};

/** Pasa el pedido a Entregado. Si la base lo rechaza, lanza un Error con un mensaje para el usuario. */
export async function confirmarRecepcion(pedidoId: string): Promise<{ estado: EstadoPedido; entregadoEn: string }> {
  const { data, error } = await supabase.rpc('confirmar_recepcion', { p_pedido_id: pedidoId });
  if (error) {
    const codigo = error.message.split(':')[0].trim();
    console.warn('[seguimiento] confirmar_recepcion:', error.code, error.message);
    throw new Error(MENSAJES_CONFIRMAR[codigo] ?? 'No se pudo confirmar la entrega. Intenta de nuevo.');
  }
  return { estado: data.estado, entregadoEn: data.entregado_en };
}