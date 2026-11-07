import { supabase } from '../lib/supabase';

// Tarifa de respaldo para pintar la pantalla mientras llega la validación del servidor.
// La tarifa real la decide la base (tabla configuracion, T-014) y llega en validar_carrito.
export const TARIFA_DOMICILIO = 2000;

export type PuntoEntrega = {
  id: string;
  nombre: string;
  indicaciones: string;
  zona: string;
};

type FilaPunto = {
  id: string;
  nombre: string;
  indicaciones: string | null;
  zonas_campus: { nombre: string } | null;
};

/** Puntos de entrega activos (RLS), con el nombre de su zona */
export async function listarPuntosEntrega(): Promise<PuntoEntrega[]> {
  const { data, error } = await supabase
    .from('puntos_entrega')
    .select('id, nombre, indicaciones, zonas_campus ( nombre )')
    .order('nombre');
  if (error) {
    console.warn('[checkout] puntos de entrega:', error.code, error.message);
    throw new Error('No se pudieron cargar los lugares de entrega');
  }
  return ((data ?? []) as unknown as FilaPunto[]).map((f) => ({
    id: f.id,
    nombre: f.nombre,
    indicaciones: f.indicaciones ?? '',
    zona: f.zonas_campus?.nombre ?? '',
  }));
}

// ---------------------------------------------------------------------------
// Carrito y pedido (funciones SQL de T-023; contrato en docs/adr/004-carrito-estado-local.md)
// ---------------------------------------------------------------------------

/** Lo único que la base necesita del carrito: qué producto y cuántas unidades */
export type LineaCarrito = { productoId: string; cantidad: number };

export type ErrorCarrito = {
  codigo: string;
  mensaje: string;
  producto_id?: string;
  solicitado?: number;
  disponible?: number;
};

export type ValidacionCarrito = {
  valido: boolean;
  subtotal: number | null;
  tarifaDomicilio: number | null;
  total: number | null;
  errores: ErrorCarrito[];
};

export type PedidoCreado = {
  pedidoId: string;
  /** Código corto para mostrar al usuario (primeros 8 caracteres del id) */
  codigo: string;
  total: number;
};

/** Error de negocio de crear_pedido; `codigo` es el prefijo que manda la base (p. ej. PEDIDO_ACTIVO_EXISTENTE) */
export class ErrorPedido extends Error {
  codigo: string;
  constructor(codigo: string, mensaje: string) {
    super(mensaje);
    this.codigo = codigo;
  }
}

const MENSAJE_GENERICO = 'No se pudo crear el pedido. Intenta de nuevo.';
const SIN_SERVICIO = 'En este momento no estamos recibiendo pedidos.';

// Mensajes para el usuario según el código con el que empieza el error de crear_pedido.
// CARRITO_INVALIDO no está: su mensaje ya viene listo de la base (p. ej. 'No hay unidades suficientes de "Papas".').
const MENSAJES: Record<string, string> = {
  NO_AUTENTICADO: 'Tu sesión expiró. Vuelve a iniciar sesión.',
  ROL_NO_PERMITIDO: 'Tu cuenta no puede hacer pedidos. Solo los solicitantes pueden pedir.',
  PUNTO_ENTREGA_INVALIDO: 'Ese lugar de entrega ya no está disponible. Elige otro.',
  FUERA_DE_COBERTURA: 'Ese lugar de entrega está fuera del campus. Elige otro.',
  COBERTURA_NO_CONFIGURADA: SIN_SERVICIO,
  CONFIG_FALTANTE: SIN_SERVICIO,
  PEDIDO_ACTIVO_EXISTENTE: 'Ya tienes un pedido en curso. Espera a que termine para hacer otro.',
  NOTAS_DEMASIADO_LARGAS: 'Las indicaciones de entrega son demasiado largas.',
};

function aParametro(lineas: LineaCarrito[]) {
  return lineas.map((l) => ({ producto_id: l.productoId, cantidad: l.cantidad }));
}

/**
 * Revisa el carrito en la base (inventario, un solo comercio, productos vigentes) y
 * devuelve los totales con la tarifa vigente. Solo lectura: no reserva inventario.
 */
export async function validarCarrito(lineas: LineaCarrito[]): Promise<ValidacionCarrito> {
  const { data, error } = await supabase.rpc('validar_carrito', { p_items: aParametro(lineas) });
  if (error || !data) {
    console.warn('[checkout] validar_carrito:', error?.code, error?.message);
    throw new Error('No se pudo revisar el carrito');
  }
  return {
    valido: data.valido,
    subtotal: data.subtotal,
    tarifaDomicilio: data.tarifa_domicilio,
    total: data.total,
    errores: data.errores ?? [],
  };
}

/**
 * Crea el pedido (estado Creado) y descuenta el inventario en una sola transacción.
 * La base vuelve a validar todo; si algo falla lanza ErrorPedido con un mensaje para el usuario.
 */
export async function crearPedido(pedido: {
  puntoEntregaId: string;
  lineas: LineaCarrito[];
  notas?: string;
}): Promise<PedidoCreado> {
  const { data, error } = await supabase.rpc('crear_pedido', {
    p_punto_entrega_id: pedido.puntoEntregaId,
    p_items: aParametro(pedido.lineas),
    p_notas_entrega: pedido.notas ?? null,
  });

  if (error) {
    const codigo = error.message.split(':')[0].trim();
    console.warn('[checkout] crear_pedido:', error.code, error.message);
    if (codigo === 'CARRITO_INVALIDO') {
      const detalle = error.message.slice(error.message.indexOf(':') + 1).trim();
      throw new ErrorPedido(codigo, detalle || 'Revisa los productos del carrito.');
    }
    throw new ErrorPedido(codigo, MENSAJES[codigo] ?? MENSAJE_GENERICO);
  }

  return {
    pedidoId: data.pedido_id,
    codigo: String(data.pedido_id).slice(0, 8).toUpperCase(),
    total: data.total,
  };
}
