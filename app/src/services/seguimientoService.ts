import { supabase } from '../lib/supabase';
import { EstadoPago, EstadoPedido, MetodoPago } from '../types';

// Detalle del pedido para la pantalla de seguimiento (RLS: el solicitante solo lee los suyos)
export type DetallePedido = {
  id: string;
  /** Código corto para mostrar (primeros 8 caracteres del id) */
  codigo: string;
  comercio: string;
  puntoEntrega: string;
  estado: EstadoPedido;
  listoParaRecoger: boolean;
  metodoPago: MetodoPago;
  estadoPago: EstadoPago;
  actualizadoEn: string;
  items: { nombre: string; cantidad: number; precioUnitario: number }[];
  subtotal: number;
  tarifaDomicilio: number;
  total: number;
};

type FilaDetalle = FilaPedido & {
  solicitante_id?: string;
  metodo_pago: MetodoPago;
  subtotal: number;
  tarifa_domicilio: number;
  total: number;
  comercios: { nombre: string } | null;
  puntos_entrega: { nombre: string } | null;
  items_pedido: { cantidad: number; precio_unitario: number; productos: { nombre: string } | null }[] | null;
};

/** Lee un pedido con su comercio, lugar de entrega, ítems y estado del pago. null si no existe o no es visible. */
export async function obtenerPedido(pedidoId: string): Promise<DetallePedido | null> {
  const { data, error } = await supabase
    .from('pedidos')
    .select(
      'id, estado, listo_para_recoger, metodo_pago, estado_pago, subtotal, tarifa_domicilio, total, actualizado_en, ' +
        'comercios ( nombre ), puntos_entrega ( nombre ), items_pedido ( cantidad, precio_unitario, productos ( nombre ) )'
    )
    .eq('id', pedidoId)
    .maybeSingle();
  if (error) {
    console.warn('[seguimiento] obtenerPedido:', error.code, error.message);
    throw new Error('No se pudo cargar el pedido.');
  }
  if (!data) return null;
  const f = data as unknown as FilaDetalle;
  return {
    id: f.id,
    codigo: f.id.slice(0, 8).toUpperCase(),
    comercio: f.comercios?.nombre ?? 'Comercio',
    puntoEntrega: f.puntos_entrega?.nombre ?? 'Punto de entrega',
    estado: f.estado,
    listoParaRecoger: f.listo_para_recoger ?? false,
    metodoPago: f.metodo_pago,
    estadoPago: f.estado_pago,
    actualizadoEn: f.actualizado_en,
    items: (f.items_pedido ?? []).map((i) => ({
      nombre: i.productos?.nombre ?? 'Producto',
      cantidad: i.cantidad,
      precioUnitario: Number(i.precio_unitario),
    })),
    subtotal: Number(f.subtotal),
    tarifaDomicilio: Number(f.tarifa_domicilio),
    total: Number(f.total),
  };
}

// Seguimiento en vivo con Supabase Realtime (T-046). La base solo envía los cambios de los
// pedidos que la RLS deja ver al usuario (migración realtime_pedidos).

export type CambioPedido = {
  id: string;
  estado: EstadoPedido;
  repartidorId: string | null;
  listoParaRecoger: boolean;
  estadoPago: EstadoPago;
  actualizadoEn: string;
};

type FilaPedido = {
  id: string;
  estado: EstadoPedido;
  repartidor_id: string | null;
  listo_para_recoger: boolean | null;
  estado_pago: EstadoPago;
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
          estadoPago: fila.estado_pago,
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