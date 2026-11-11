import { supabase } from '../lib/supabase';
import { EstadoPago, EstadoPedido, MetodoPago, PedidoEntrega } from '../types';

// Pedidos del domiciliario: los disponibles (estado Creado, sin repartidor) y los que ya
// aceptó. La base decide qué ve cada rol (política ver_pedidos_por_rol): un domiciliario solo
// recibe los disponibles y los suyos; el resto de los pedidos ni siquiera le llegan.
// Aceptar y recoger se hacen con funciones SQL (aceptar_pedido, confirmar_recogida).

const COLUMNAS =
  'id, estado, listo_para_recoger, total, metodo_pago, estado_pago, notas_entrega, creado_en, ' +
  'comercios ( nombre ), puntos_entrega ( nombre ), items_pedido ( cantidad, productos ( nombre ) )';

type FilaEntrega = {
  id: string;
  estado: EstadoPedido;
  listo_para_recoger: boolean | null;
  total: number;
  metodo_pago: MetodoPago;
  estado_pago: EstadoPago;
  notas_entrega: string | null;
  creado_en: string;
  comercios: { nombre: string } | null;
  puntos_entrega: { nombre: string } | null;
  items_pedido: { cantidad: number; productos: { nombre: string } | null }[] | null;
};

function aPedidoEntrega(f: FilaEntrega): PedidoEntrega {
  return {
    id: f.id,
    codigo: f.id.slice(0, 8).toUpperCase(),
    estado: f.estado,
    comercio: f.comercios?.nombre ?? 'Comercio',
    puntoEntrega: f.puntos_entrega?.nombre ?? 'Punto de entrega',
    notasEntrega: f.notas_entrega,
    listoParaRecoger: f.listo_para_recoger ?? false,
    items: (f.items_pedido ?? []).map((i) => ({
      nombre: i.productos?.nombre ?? 'Producto',
      cantidad: i.cantidad,
    })),
    total: Number(f.total),
    metodoPago: f.metodo_pago,
    estadoPago: f.estado_pago,
    creadoEn: f.creado_en,
  };
}

/** Pedidos disponibles para aceptar: Creado y sin repartidor, los más antiguos primero */
export async function listarPedidosDisponibles(): Promise<PedidoEntrega[]> {
  const { data, error } = await supabase
    .from('pedidos')
    .select(COLUMNAS)
    .eq('estado', 'Creado')
    .is('repartidor_id', null)
    .order('creado_en', { ascending: true });
  if (error) {
    console.warn('[entregas] disponibles:', error.code, error.message);
    throw new Error('No se pudieron cargar los pedidos disponibles');
  }
  return ((data ?? []) as unknown as FilaEntrega[]).map(aPedidoEntrega);
}

/** Pedidos que el domiciliario ya aceptó y todavía no entrega (Asignado o En Camino) */
export async function listarMisEntregas(repartidorId: string): Promise<PedidoEntrega[]> {
  const { data, error } = await supabase
    .from('pedidos')
    .select(COLUMNAS)
    .eq('repartidor_id', repartidorId)
    .in('estado', ['Asignado', 'En Camino'])
    .order('creado_en', { ascending: true });
  if (error) {
    console.warn('[entregas] mis entregas:', error.code, error.message);
    throw new Error('No se pudieron cargar tus entregas');
  }
  return ((data ?? []) as unknown as FilaEntrega[]).map(aPedidoEntrega);
}

const MENSAJES: Record<string, string> = {
  NO_AUTENTICADO: 'Tu sesión expiró. Vuelve a iniciar sesión.',
  ROL_NO_PERMITIDO: 'Tu cuenta no puede hacer entregas.',
  PEDIDO_NO_ENCONTRADO: 'No encontramos este pedido.',
  PEDIDO_PROPIO: 'No puedes aceptar tu propio pedido.',
  PEDIDO_NO_DISPONIBLE: 'Otro domiciliario ya tomó este pedido.',
  ESTADO_NO_PERMITIDO: 'Este pedido ya no está en un estado que permita esa acción.',
};

function aError(operacion: string, error: { code?: string; message: string }, generico: string): Error {
  const codigo = error.message.split(':')[0].trim();
  console.warn(`[entregas] ${operacion}:`, error.code, error.message);
  return new Error(MENSAJES[codigo] ?? generico);
}

/** Toma el pedido (Creado -> Asignado). Si otro domiciliario llegó antes, lanza un Error con el motivo. */
export async function aceptarPedido(pedidoId: string): Promise<void> {
  const { error } = await supabase.rpc('aceptar_pedido', { p_pedido_id: pedidoId });
  if (error) throw aError('aceptar_pedido', error, 'No se pudo aceptar el pedido. Intenta de nuevo.');
}

/** Confirma que recogió el pedido en el comercio (Asignado -> En Camino) */
export async function confirmarRecogida(pedidoId: string): Promise<void> {
  const { error } = await supabase.rpc('confirmar_recogida', { p_pedido_id: pedidoId });
  if (error) throw aError('confirmar_recogida', error, 'No se pudo confirmar la recogida. Intenta de nuevo.');
}

/**
 * Avisa cuando aparece o cambia un pedido que el domiciliario puede ver (Supabase Realtime).
 * Ojo: cuando OTRO domiciliario toma un pedido, este deja de ser visible para ti y por eso NO
 * llega ese cambio; la pantalla debe volver a cargar al volver a primer plano y tras un error
 * de aceptar_pedido. Devuelve una función para dejar de escuchar.
 */
export function escucharPedidosDelRepartidor(alCambiar: () => void): () => void {
  const canal = supabase
    .channel('pedidos-repartidor')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'pedidos' }, () => alCambiar())
    .subscribe();
  return () => {
    supabase.removeChannel(canal);
  };
}
