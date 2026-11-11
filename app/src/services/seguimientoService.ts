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
