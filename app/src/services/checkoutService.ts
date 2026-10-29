import { supabase } from '../lib/supabase';

// Regla de negocio del piloto (docs/reglas_negocio_piloto.md): tarifa fija de domicilio
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

export type NuevoPedido = {
  solicitante: string;
  comercioId: string;
  items: { nombre: string; cantidad: number; precio: number }[];
};

// SIMULADO: la app no puede escribir en pedidos (RLS de T-072). Esto se reemplaza por
// supabase.rpc('crear_pedido', ...) cuando exista la función de Aguas (T-023).
let siguienteNumero = 1001;
export async function crearPedido(_pedido: NuevoPedido): Promise<{ numero: number }> {
  await new Promise<void>((resolve) => setTimeout(resolve, 300));
  return { numero: siguienteNumero++ };
}