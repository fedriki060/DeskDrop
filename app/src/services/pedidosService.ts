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

export type ComercioDelUsuario = { id: string; nombre: string; activo: boolean; imagenUrl: string | null };

/** Comercio que administra el usuario con sesión (null si no administra ninguno). */
export async function obtenerMiComercio(userId: string): Promise<ComercioDelUsuario | null> {
  const { data, error } = await supabase
    .from('comercios')
    .select('id, nombre, activo, imagen_url')
    .eq('administrador_id', userId)
    .limit(1)
    .maybeSingle();
  if (error) {
    console.warn('[pedidos] comercio:', error.code, error.message);
    return null;
  }
  return data
    ? { id: data.id, nombre: data.nombre, activo: data.activo !== false, imagenUrl: data.imagen_url ?? null }
    : null;
}

// ---------------------------------------------------------------------------
// Foto del comercio (bucket público `comercios`, carpeta con el id del comercio)
// ---------------------------------------------------------------------------

const BUCKET_FOTOS = 'comercios';
const TIPOS_FOTO = ['image/jpeg', 'image/png', 'image/webp'];
const MAXIMO_FOTO_BYTES = 2 * 1024 * 1024; // igual que el límite del bucket

export type ResultadoFoto = { ok: true; url: string | null } | { ok: false; mensaje: string };

/** Sube la foto elegida (reemplaza la anterior) y la deja como foto del comercio. */
export async function subirFotoComercio(comercioId: string, uri: string, mimeType?: string | null): Promise<ResultadoFoto> {
  try {
    const respuesta = await fetch(uri);
    const contenido = await respuesta.arrayBuffer();
    const tipo = mimeType || respuesta.headers.get('content-type') || 'image/jpeg';
    if (!TIPOS_FOTO.includes(tipo)) return { ok: false, mensaje: 'Elige una imagen JPG, PNG o WebP.' };
    if (contenido.byteLength > MAXIMO_FOTO_BYTES) return { ok: false, mensaje: 'La foto pesa más de 2 MB. Elige una más liviana.' };

    const ruta = `${comercioId}/foto`;
    const { error } = await supabase.storage
      .from(BUCKET_FOTOS)
      .upload(ruta, contenido, { contentType: tipo, upsert: true, cacheControl: '3600' });
    if (error) throw error;

    // ?v= evita que se siga viendo la foto anterior guardada en caché
    const url = `${supabase.storage.from(BUCKET_FOTOS).getPublicUrl(ruta).data.publicUrl}?v=${Date.now()}`;
    const { data, error: errorUrl } = await supabase
      .from('comercios')
      .update({ imagen_url: url })
      .eq('id', comercioId)
      .select('id');
    if (errorUrl || !data || data.length === 0) throw errorUrl ?? new Error('sin permiso');
    return { ok: true, url };
  } catch (e) {
    console.warn('[pedidos] subir foto:', e instanceof Error ? e.message : e);
    return { ok: false, mensaje: 'No se pudo guardar la foto. Revisa tu conexión e inténtalo de nuevo.' };
  }
}

/** Quita la foto del comercio: la lista de tiendas vuelve a mostrar la letra inicial. */
export async function quitarFotoComercio(comercioId: string): Promise<ResultadoFoto> {
  const { data, error } = await supabase
    .from('comercios')
    .update({ imagen_url: null })
    .eq('id', comercioId)
    .select('id');
  if (error || !data || data.length === 0) {
    console.warn('[pedidos] quitar foto:', error?.code, error?.message);
    return { ok: false, mensaje: 'No se pudo quitar la foto. Inténtalo de nuevo.' };
  }
  await supabase.storage.from(BUCKET_FOTOS).remove([`${comercioId}/foto`]); // si falla, no importa
  return { ok: true, url: null };
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
  const repartidores = new Map<string, string>();
  if (filas.length > 0) {
    const { data: partes, error: errorNombres } = await supabase.rpc('datos_partes_pedido', {
      p_pedido_ids: filas.map((f) => f.id),
    });
    if (errorNombres) console.warn('[pedidos] nombres:', errorNombres.code, errorNombres.message);
    for (const p of (partes ?? []) as {
      pedido_id: string;
      solicitante: string;
      repartidor: string | null;
    }[]) {
      nombres.set(p.pedido_id, p.solicitante);
      if (p.repartidor) repartidores.set(p.pedido_id, p.repartidor);
    }
  }

  return filas.map((f) => ({
    id: f.id,
    numero: f.numero,
    comercioId: f.comercio_id,
    solicitante: nombres.get(f.id) || 'Cliente',
    repartidor: repartidores.get(f.id),
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

const MENSAJES_CANCELAR: Record<string, string> = {
  NO_AUTENTICADO: 'Tu sesión expiró. Vuelve a iniciar sesión.',
  PEDIDO_NO_ENCONTRADO: 'No encontramos este pedido.',
  ESTADO_NO_PERMITIDO: 'El pedido ya salió y no se puede cancelar.',
  MOTIVO_INVALIDO: 'El motivo es demasiado largo.',
};

/**
 * Cancela un pedido Creado o Asignado: el solicitante dueño ("Cancelar pedido") o el comercio
 * ("Rechazar pedido"). La base repone el inventario en la misma transacción.
 * Devuelve null si salió bien, o el mensaje de error para el usuario.
 */
export async function cancelarPedido(pedidoId: string, motivo?: string): Promise<string | null> {
  const { error } = await supabase.rpc('cancelar_pedido', {
    p_pedido_id: pedidoId,
    p_motivo: motivo ?? null,
  });
  if (error) {
    const codigo = error.message.split(':')[0].trim();
    console.warn('[pedidos] cancelar:', error.code, error.message);
    return MENSAJES_CANCELAR[codigo] ?? 'No se pudo cancelar el pedido. Intenta de nuevo.';
  }
  return null;
}
