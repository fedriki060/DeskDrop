import { supabase } from '../lib/supabase';
import { Comercio, Producto, TipoComercio } from '../types';

// Las políticas RLS solo devuelven filas activas y exigen sesión iniciada.
// Aquí se traducen los nombres de la base (snake_case) a los del front.

type FilaComercio = {
  id: string;
  tipo: TipoComercio;
  nombre: string;
  descripcion: string | null;
};

type FilaProducto = {
  id: string;
  comercio_id: string;
  nombre: string;
  descripcion: string | null;
  precio: number | string;
  inventario_disponible: number;
  imagen_url: string | null;
};

const COLUMNAS_COMERCIO = 'id, tipo, nombre, descripcion';
const COLUMNAS_PRODUCTO =
  'id, comercio_id, nombre, descripcion, precio, inventario_disponible, imagen_url';

const aComercio = (f: FilaComercio): Comercio => ({
  id: f.id,
  tipo: f.tipo,
  nombre: f.nombre,
  descripcion: f.descripcion ?? '',
});

const aProducto = (f: FilaProducto): Producto => ({
  id: f.id,
  comercioId: f.comercio_id,
  nombre: f.nombre,
  descripcion: f.descripcion ?? '',
  precio: Number(f.precio),
  inventario: f.inventario_disponible,
  imagenUrl: f.imagen_url ?? undefined,
});

function fallo(operacion: string, error: { message: string; code?: string }): never {
  console.warn(`[catálogo] ${operacion}: ${error.code ?? ''} ${error.message}`);
  throw new Error('No se pudo cargar el catálogo. Revisa tu conexión e inténtalo de nuevo.');
}

export async function listarComercios(tipo?: TipoComercio): Promise<Comercio[]> {
  let consulta = supabase.from('comercios').select(COLUMNAS_COMERCIO).order('nombre');
  if (tipo) consulta = consulta.eq('tipo', tipo);

  const { data, error } = await consulta;
  if (error) fallo('listarComercios', error);
  return ((data ?? []) as FilaComercio[]).map(aComercio);
}

export async function obtenerComercio(id: string): Promise<Comercio | undefined> {
  const { data, error } = await supabase
    .from('comercios')
    .select(COLUMNAS_COMERCIO)
    .eq('id', id)
    .maybeSingle();
  if (error) fallo('obtenerComercio', error);
  return data ? aComercio(data as FilaComercio) : undefined;
}

export async function listarProductos(comercioId: string): Promise<Producto[]> {
  const { data, error } = await supabase
    .from('productos')
    .select(COLUMNAS_PRODUCTO)
    .eq('comercio_id', comercioId)
    .order('nombre');
  if (error) fallo('listarProductos', error);
  return ((data ?? []) as FilaProducto[]).map(aProducto);
}

export async function obtenerProducto(id: string): Promise<Producto | undefined> {
  const { data, error } = await supabase
    .from('productos')
    .select(COLUMNAS_PRODUCTO)
    .eq('id', id)
    .maybeSingle();
  if (error) fallo('obtenerProducto', error);
  return data ? aProducto(data as FilaProducto) : undefined;
}