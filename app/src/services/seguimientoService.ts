import { supabase } from '../lib/supabase';
import { nombreCanal } from './realtime';
import { EstadoPedido, ItemPedido } from '../types';

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
    .channel(nombreCanal(`pedido-${pedidoId}`))
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
// Código de entrega de 4 dígitos (HU-20). El solicitante lo ve; el domiciliario lo digita.
// ---------------------------------------------------------------------------

/** Código que el solicitante dueño le dice al domiciliario al recibir. null si no se pudo leer. */
export async function obtenerCodigoEntrega(pedidoId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from('codigos_entrega')
    .select('codigo')
    .eq('pedido_id', pedidoId)
    .maybeSingle();
  if (error) {
    console.warn('[seguimiento] código de entrega:', error.code, error.message);
    return null;
  }
  return data?.codigo ?? null;
}

export type ResultadoConfirmarEntrega =
  | { ok: true; entregadoEn: string }
  | { ok: false; mensaje: string; intentosRestantes?: number; bloqueado?: boolean };

const MENSAJES_ENTREGA: Record<string, string> = {
  NO_AUTENTICADO: 'Tu sesión expiró. Vuelve a iniciar sesión.',
  ROL_NO_PERMITIDO: 'Activa la vista de domiciliario desde tu perfil.',
  CODIGO_INVALIDO: 'El código son 4 dígitos.',
  PEDIDO_NO_ENCONTRADO: 'No encontramos este pedido entre tus entregas.',
  ESTADO_NO_PERMITIDO: 'Solo puedes confirmar un pedido que ya va En Camino.',
  CODIGO_BLOQUEADO: 'Agotaste los intentos. El pedido se confirmará solo en unos minutos.',
};

/** El domiciliario asignado digita el código del solicitante para marcar el pedido Entregado. */
export async function confirmarEntrega(pedidoId: string, codigo: string): Promise<ResultadoConfirmarEntrega> {
  const { data, error } = await supabase.rpc('confirmar_entrega', {
    p_pedido_id: pedidoId,
    p_codigo: codigo,
  });
  if (error) {
    const clave = error.message.split(':')[0].trim();
    console.warn('[seguimiento] confirmar_entrega:', error.code, error.message);
    return {
      ok: false,
      mensaje: MENSAJES_ENTREGA[clave] ?? 'No se pudo confirmar la entrega. Intenta de nuevo.',
      bloqueado: clave === 'CODIGO_BLOQUEADO',
    };
  }
  if (!data.ok) {
    const restantes: number = data.intentos_restantes;
    return {
      ok: false,
      mensaje:
        restantes > 0
          ? `Código incorrecto. Te quedan ${restantes} ${restantes === 1 ? 'intento' : 'intentos'}.`
          : MENSAJES_ENTREGA.CODIGO_BLOQUEADO,
      intentosRestantes: restantes,
      bloqueado: restantes <= 0,
    };
  }
  return { ok: true, entregadoEn: data.entregado_en };
}

// ---------------------------------------------------------------------------
// Calificación del domiciliario (HU-15)
// ---------------------------------------------------------------------------

const MENSAJES_CALIFICAR: Record<string, string> = {
  NO_AUTENTICADO: 'Tu sesión expiró. Vuelve a iniciar sesión.',
  ESTRELLAS_INVALIDAS: 'Elige de 1 a 5 estrellas.',
  COMENTARIO_DEMASIADO_LARGO: 'El comentario puede tener máximo 300 caracteres.',
  PEDIDO_NO_ENCONTRADO: 'No encontramos este pedido.',
  ESTADO_NO_PERMITIDO: 'Solo puedes calificar un pedido ya entregado.',
  PLAZO_VENCIDO: 'Ya pasó el plazo para calificar este pedido.',
  YA_CALIFICADO: 'Ya calificaste este pedido.',
};

/** Estrellas que el solicitante dio a este pedido, o null si todavía no lo califica. */
export async function obtenerMiCalificacion(pedidoId: string): Promise<number | null> {
  const { data, error } = await supabase
    .from('calificaciones')
    .select('estrellas')
    .eq('pedido_id', pedidoId)
    .maybeSingle();
  if (error) {
    console.warn('[seguimiento] mi calificación:', error.code, error.message);
    return null;
  }
  return data?.estrellas ?? null;
}

/** Califica al domiciliario de un pedido entregado (1 a 5 estrellas, comentario opcional). */
export async function calificarPedido(
  pedidoId: string,
  estrellas: number,
  comentario?: string
): Promise<{ ok: true } | { ok: false; mensaje: string }> {
  const { error } = await supabase.rpc('calificar_pedido', {
    p_pedido_id: pedidoId,
    p_estrellas: estrellas,
    p_comentario: comentario?.trim() || null,
  });
  if (error) {
    const codigo = error.message.split(':')[0].trim();
    console.warn('[seguimiento] calificar:', error.code, error.message);
    return { ok: false, mensaje: MENSAJES_CALIFICAR[codigo] ?? 'No se pudo enviar tu calificación. Intenta de nuevo.' };
  }
  return { ok: true };
}

// ---------------------------------------------------------------------------
// Último pedido del solicitante, con lo que se muestra en el seguimiento (HU-11).
// ---------------------------------------------------------------------------

export type SeguimientoPedido = {
  id: string;
  numero: number;
  estado: EstadoPedido;
  listoParaRecoger: boolean;
  total: number;
  comercio: string;
  puntoEntrega: string;
  /** Primer nombre del domiciliario, una vez que alguien aceptó el pedido */
  repartidor: string | null;
  /** Celular del domiciliario: solo el solicitante, mientras el pedido está Asignado o En Camino */
  repartidorTelefono: string | null;
  /** Promedio de estrellas del domiciliario (null si todavía no tiene calificaciones) */
  repartidorCalificacion: number | null;
  items: ItemPedido[];
  creadoEn: string;
  /** Forma y estado del pago (pago físico: efectivo al domiciliario) */
  pago: { metodo: string; estado: string; monto: number } | null;
  /** Si está cancelado: quién lo canceló (solicitante, comercio o sistema) */
  canceladoPor: string | null;
};

type FilaSeguimiento = {
  id: string;
  numero: number;
  estado: EstadoPedido;
  listo_para_recoger: boolean | null;
  total: number;
  creado_en: string;
  cancelado_por: string | null;
  comercios: { nombre: string } | null;
  puntos_entrega: { nombre: string } | null;
  items_pedido: { cantidad: number; productos: { nombre: string } | null }[];
  pagos: { metodo: string; estado: string; monto: number }[] | { metodo: string; estado: string; monto: number } | null;
};

/** Pedido más reciente del solicitante (en curso o terminado). null si nunca ha pedido. Lanza Error si falla. */
export async function obtenerUltimoPedido(userId: string): Promise<SeguimientoPedido | null> {
  const { data, error } = await supabase
    .from('pedidos')
    .select(
      'id, numero, estado, listo_para_recoger, total, creado_en, cancelado_por, comercios(nombre), puntos_entrega(nombre), items_pedido(cantidad, productos(nombre)), pagos(metodo, estado, monto)'
    )
    .eq('solicitante_id', userId)
    .order('creado_en', { ascending: false })
    .limit(1)
    .returns<FilaSeguimiento[]>();
  if (error) {
    console.warn('[seguimiento] último pedido:', error.code, error.message);
    throw new Error('No se pudo cargar tu pedido. Revisa tu conexión.');
  }
  const f = data?.[0];
  if (!f) return null;

  let repartidor: string | null = null;
  let repartidorTelefono: string | null = null;
  let repartidorCalificacion: number | null = null;
  const { data: partes, error: errorPartes } = await supabase.rpc('datos_partes_pedido', {
    p_pedido_ids: [f.id],
  });
  if (errorPartes) console.warn('[seguimiento] nombres:', errorPartes.code, errorPartes.message);
  else {
    const parte = (
      partes as
        | { repartidor: string | null; repartidor_telefono: string | null; repartidor_calificacion: number | null }[]
        | null
    )?.[0];
    repartidor = parte?.repartidor || null;
    repartidorTelefono = parte?.repartidor_telefono || null;
    repartidorCalificacion = parte?.repartidor_calificacion != null ? Number(parte.repartidor_calificacion) : null;
  }

  return {
    id: f.id,
    numero: f.numero,
    estado: f.estado,
    listoParaRecoger: f.listo_para_recoger ?? false,
    total: Number(f.total),
    comercio: f.comercios?.nombre ?? 'Comercio',
    puntoEntrega: f.puntos_entrega?.nombre ?? 'Punto de entrega',
    repartidor,
    repartidorTelefono,
    repartidorCalificacion,
    items: f.items_pedido.map((i) => ({ nombre: i.productos?.nombre ?? 'Producto', cantidad: i.cantidad })),
    creadoEn: f.creado_en,
    pago: Array.isArray(f.pagos) ? (f.pagos[0] ?? null) : f.pagos,
    canceladoPor: f.cancelado_por,
  };
}

/**
 * Avisa cuando cambia cualquier pedido del solicitante (Realtime; la RLS filtra).
 * Devuelve una función para dejar de escuchar.
 */
export function escucharMisPedidos(userId: string, alCambiar: () => void): () => void {
  const canal = supabase
    .channel(nombreCanal(`mis-pedidos-${userId}`))
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'pedidos', filter: `solicitante_id=eq.${userId}` },
      () => alCambiar()
    )
    .subscribe();
  return () => {
    supabase.removeChannel(canal);
  };
}

/** El solicitante dueño pide un código de entrega nuevo (reinicia los intentos). null si no se pudo. */
export async function regenerarCodigoEntrega(pedidoId: string): Promise<string | null> {
  const { data, error } = await supabase.rpc('regenerar_codigo_entrega', { p_pedido_id: pedidoId });
  if (error) {
    console.warn('[seguimiento] regenerar código:', error.code, error.message);
    return null;
  }
  return data.codigo;
}

// ---------------------------------------------------------------------------
// Historial del solicitante (HU-25)
// ---------------------------------------------------------------------------

export type PedidoHistorial = {
  id: string;
  numero: number;
  estado: EstadoPedido;
  total: number;
  comercio: string;
  creadoEn: string;
  items: ItemPedido[];
};

type FilaHistorial = {
  id: string;
  numero: number;
  estado: EstadoPedido;
  total: number;
  creado_en: string;
  comercios: { nombre: string } | null;
  items_pedido: { cantidad: number; productos: { nombre: string } | null }[];
};

/** Pedidos del solicitante, del más reciente al más antiguo. Lanza Error si no se pudieron leer. */
export async function obtenerHistorial(userId: string): Promise<PedidoHistorial[]> {
  const { data, error } = await supabase
    .from('pedidos')
    .select('id, numero, estado, total, creado_en, comercios(nombre), items_pedido(cantidad, productos(nombre))')
    .eq('solicitante_id', userId)
    .order('creado_en', { ascending: false })
    .limit(50)
    .returns<FilaHistorial[]>();
  if (error) {
    console.warn('[seguimiento] historial:', error.code, error.message);
    throw new Error('No se pudo cargar tu historial. Revisa tu conexión.');
  }
  return (data ?? []).map((f) => ({
    id: f.id,
    numero: f.numero,
    estado: f.estado,
    total: Number(f.total),
    comercio: f.comercios?.nombre ?? 'Comercio',
    creadoEn: f.creado_en,
    items: f.items_pedido.map((i) => ({ nombre: i.productos?.nombre ?? 'Producto', cantidad: i.cantidad })),
  }));
}
