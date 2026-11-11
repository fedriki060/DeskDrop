import { supabase } from '../lib/supabase';
import { nombreCanal } from './realtime';
import { EstadoPedido, Pedido } from '../types';

// Bandeja del comercio con datos reales. La RLS deja ver solo los pedidos de los comercios que
// administra el usuario; los nombres salen de datos_partes_pedido porque `perfiles` es privado.

type FilaPedido = {
  id: string;
  numero: number;
  comercio_id: string;
  estado: EstadoPedido;
  listo_para_recoger: boolean | null;
  total: number;
  creado_en: string;
  items_pedido: { cantidad: number; productos: { nombre: string } | null }[];
};

export type ComercioDelUsuario = { id: string; nombre: string; activo: boolean };

/** Comercio que administra el usuario con sesión (null si no administra ninguno). */
export async function obtenerMiComercio(userId: string): Promise<ComercioDelUsuario | null> {
  const { data, error } = await supabase
    .from('comercios')
    .select('id, nombre, activo')
    .eq('administrador_id', userId)
    .limit(1)
    .maybeSingle();
  if (error) {
    console.warn('[pedidos] comercio:', error.code, error.message);
    return null;
  }
  return data ? { id: data.id, nombre: data.nombre, activo: data.activo !== false } : null;
}

/** Pedidos del comercio, del más reciente al más antiguo. Lanza Error si no se pudieron leer. */
export async function listarPedidosComercio(comercioId: string): Promise<Pedido[]> {
  const { data, error } = await supabase
    .from('pedidos')
    .select(
      'id, numero, comercio_id, estado, listo_para_recoger, total, creado_en, items_pedido(cantidad, productos(nombre))'
    )
    .eq('comercio_id', comercioId)
    .order('creado_en', { ascending: false })
    .limit(50)
    .returns<FilaPedido[]>();
  if (error) {
    console.warn('[pedidos] listar:', error.code, error.message);
    throw new Error('No se pudieron cargar los pedidos. Revisa tu conexión.');
  }
  const filas = data ?? [];

  const nombres = new Map<string, string>();
  if (filas.length > 0) {
    const { data: partes, error: errorNombres } = await supabase.rpc('datos_partes_pedido', {
      p_pedido_ids: filas.map((f) => f.id),
    });
    if (errorNombres) console.warn('[pedidos] nombres:', errorNombres.code, errorNombres.message);
    for (const p of (partes ?? []) as { pedido_id: string; solicitante: string }[]) {
      nombres.set(p.pedido_id, p.solicitante);
    }
  }

  return filas.map((f) => ({
    id: f.id,
    numero: f.numero,
    comercioId: f.comercio_id,
    solicitante: nombres.get(f.id) || 'Cliente',
    estado: f.estado,
    listoParaRecoger: f.listo_para_recoger ?? false,
    items: f.items_pedido.map((i) => ({ nombre: i.productos?.nombre ?? 'Producto', cantidad: i.cantidad })),
    total: Number(f.total),
    creadoEn: f.creado_en,
  }));
}

const MENSAJES: Record<string, string> = {
  NO_AUTENTICADO: 'Tu sesión expiró. Vuelve a iniciar sesión.',
  ROL_NO_PERMITIDO: 'Tu cuenta no puede marcar pedidos como listos.',
  PEDIDO_NO_ENCONTRADO: 'No encontramos este pedido en tu comercio.',
  ESTADO_NO_PERMITIDO: 'El pedido ya salió, no se puede marcar como listo.',
};

/** Solo cambia el indicador; el comercio nunca modifica el estado de logística. Lanza Error con mensaje para el usuario. */
export async function marcarListoParaRecoger(pedidoId: string): Promise<void> {
  const { error } = await supabase.rpc('marcar_listo_para_recoger', { p_pedido_id: pedidoId });
  if (error) {
    const codigo = error.message.split(':')[0].trim();
    console.warn('[pedidos] marcar listo:', error.code, error.message);
    throw new Error(MENSAJES[codigo] ?? 'No se pudo marcar el pedido. Intenta de nuevo.');
  }
}

export function puedeMarcarListo(pedido: Pedido): boolean {
  return !pedido.listoParaRecoger && (pedido.estado === 'Creado' || pedido.estado === 'Asignado');
}

/**
 * Avisa cuando llega un pedido nuevo o cambia uno del comercio (Realtime; la RLS filtra).
 * Devuelve una función para dejar de escuchar.
 */
export function escucharPedidosComercio(comercioId: string, alCambiar: () => void): () => void {
  const canal = supabase
    .channel(nombreCanal(`pedidos-comercio-${comercioId}`))
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'pedidos', filter: `comercio_id=eq.${comercioId}` },
      () => alCambiar()
    )
    .subscribe();
  return () => {
    supabase.removeChannel(canal);
  };
}

/** Pedidos nuevos: ya llegaron al comercio y aún no los marcó listos para recoger. */
export async function contarPedidosNuevos(comercioId: string): Promise<number> {
  const { count, error } = await supabase
    .from('pedidos')
    .select('id', { count: 'exact', head: true })
    .eq('comercio_id', comercioId)
    .in('estado', ['Creado', 'Asignado'])
    .eq('listo_para_recoger', false);
  if (error) {
    console.warn('[pedidos] contar nuevos:', error.code, error.message);
    return 0;
  }
  return count ?? 0;
}

/**
 * Abre o cierra el comercio ("Recibiendo pedidos"). Cerrado, no sale en el catálogo y no recibe
 * pedidos nuevos; los que ya tiene siguen su curso. La RLS solo deja al dueño cambiarlo.
 */
export async function cambiarRecibiendoPedidos(comercioId: string, recibiendo: boolean): Promise<boolean> {
  const { data, error } = await supabase
    .from('comercios')
    .update({ activo: recibiendo })
    .eq('id', comercioId)
    .select('id');
  if (error || !data || data.length === 0) {
    console.warn('[pedidos] recibiendo pedidos:', error?.code, error?.message);
    return false;
  }
  return true;
}
