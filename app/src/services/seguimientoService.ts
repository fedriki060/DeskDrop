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
