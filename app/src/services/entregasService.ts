import { supabase } from '../lib/supabase';
import { Entrega, EstadoPedido } from '../types';

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
  PAGO_YA_COBRADO: 'Este pedido ya fue cobrado.',
  PEDIDO_NO_LISTO: 'El comercio aún no marca el pedido como listo para recoger.',
};

async function ejecutar(
  funcion: 'aceptar_pedido' | 'confirmar_recogida' | 'registrar_cobro_efectivo',
  pedidoId: string
): Promise<ResultadoEntrega> {
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

/** El domiciliario registra que cobró en efectivo el pedido entregado (Entregado -> Cerrado). */
export const registrarCobroEfectivo = (pedidoId: string) => ejecutar('registrar_cobro_efectivo', pedidoId);

type FilaEntrega = {
  id: string;
  numero: number;
  estado: EstadoPedido;
  listo_para_recoger: boolean | null;
  total: number;
  notas_entrega: string | null;
  repartidor_id: string | null;
  comercios: { nombre: string } | null;
  puntos_entrega: { nombre: string; indicaciones: string | null } | null;
  items_pedido: { cantidad: number; productos: { nombre: string } | null }[];
};

/**
 * Pedidos que el domiciliario puede aceptar (Creado, sin domiciliario) y los que ya tiene en
 * curso (Asignado, En Camino, o Entregado a la espera del cobro). Los suyos como solicitante se
 * excluyen: nadie se entrega su propio pedido. Lanza Error si no se pudieron leer.
 */
export async function listarEntregas(userId: string): Promise<Entrega[]> {
  const { data, error } = await supabase
    .from('pedidos')
    .select(
      'id, numero, estado, listo_para_recoger, total, notas_entrega, repartidor_id, comercios(nombre), puntos_entrega(nombre, indicaciones), items_pedido(cantidad, productos(nombre))'
    )
    .in('estado', ['Creado', 'Asignado', 'En Camino', 'Entregado'])
    .neq('solicitante_id', userId)
    .order('creado_en', { ascending: true })
    .limit(50)
    .returns<FilaEntrega[]>();
  if (error) {
    console.warn('[entregas] listar:', error.code, error.message);
    throw new Error('No se pudieron cargar los pedidos. Revisa tu conexión.');
  }
  return (data ?? []).map((f) => ({
    id: f.id,
    numero: f.numero,
    estado: f.estado,
    listoParaRecoger: f.listo_para_recoger ?? false,
    total: Number(f.total),
    comercio: f.comercios?.nombre ?? 'Comercio',
    puntoEntrega: f.puntos_entrega?.nombre ?? 'Punto de entrega',
    indicaciones: f.puntos_entrega?.indicaciones ?? null,
    notas: f.notas_entrega,
    items: f.items_pedido.map((i) => ({ nombre: i.productos?.nombre ?? 'Producto', cantidad: i.cantidad })),
    esMia: f.repartidor_id === userId,
  }));
}

/**
 * Avisa cuando aparece o cambia un pedido que el domiciliario puede ver (Realtime; la RLS filtra).
 * Si otro domiciliario toma un pedido, este deja de ser visible y quizá no llegue el aviso:
 * por eso la pantalla también recarga cada pocos segundos.
 */
export function escucharEntregas(alCambiar: () => void): () => void {
  const canal = supabase
    .channel('entregas-domiciliario')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'pedidos' }, () => alCambiar())
    .subscribe();
  return () => {
    supabase.removeChannel(canal);
  };
}
