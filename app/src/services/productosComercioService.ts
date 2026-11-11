import { supabase } from '../lib/supabase';

// Gestión del catálogo por el dueño del comercio (T-030). Las políticas RLS ya limitan
// cada operación a los productos de su propio comercio.

export type ProductoGestion = {
  id: string;
  nombre: string;
  descripcion: string;
  precio: number;
  inventario: number;
  activo: boolean;
};

export type DatosProducto = {
  nombre: string;
  descripcion: string;
  precio: number;
  inventario: number;
};

type Fila = {
  id: string;
  nombre: string;
  descripcion: string | null;
  precio: number | string;
  inventario_disponible: number;
  activo: boolean | null;
};

const COLUMNAS = 'id, nombre, descripcion, precio, inventario_disponible, activo';
const MENSAJE = 'No se pudo completar la operación. Revisa tu conexión e inténtalo de nuevo.';

const aProducto = (f: Fila): ProductoGestion => ({
  id: f.id,
  nombre: f.nombre,
  descripcion: f.descripcion ?? '',
  precio: Number(f.precio),
  inventario: f.inventario_disponible,
  activo: f.activo !== false,
});

/** Valida el formulario; devuelve el mensaje de error o undefined si todo está bien. */
export function validarProducto(nombre: string, precio: string, inventario: string): string | undefined {
  if (!nombre.trim()) return 'El nombre es obligatorio.';
  if (nombre.trim().length > 150) return 'El nombre es demasiado largo (máximo 150).';
  if (!/^\d+$/.test(precio.trim())) return 'El precio debe ser un número entero mayor o igual a 0.';
  if (!/^\d+$/.test(inventario.trim())) return 'El inventario debe ser un número entero mayor o igual a 0.';
  return undefined;
}

export async function listarProductosComercio(comercioId: string): Promise<ProductoGestion[]> {
  const { data, error } = await supabase
    .from('productos')
    .select(COLUMNAS)
    .eq('comercio_id', comercioId)
    .order('nombre');
  if (error) {
    console.warn('[productos] listar', error.message);
    throw new Error('No se pudieron cargar tus productos.');
  }
  return ((data ?? []) as Fila[]).map(aProducto);
}

/** Devuelve un mensaje de error, o undefined si salió bien. */
export async function crearProducto(comercioId: string, d: DatosProducto): Promise<string | undefined> {
  const { error } = await supabase.from('productos').insert({
    comercio_id: comercioId,
    nombre: d.nombre.trim(),
    descripcion: d.descripcion.trim() || null,
    precio: d.precio,
    inventario_disponible: d.inventario,
    activo: true,
  });
  if (error) {
    console.warn('[productos] crear', error.message);
    return MENSAJE;
  }
}

export async function actualizarProducto(id: string, d: DatosProducto): Promise<string | undefined> {
  const { error } = await supabase
    .from('productos')
    .update({
      nombre: d.nombre.trim(),
      descripcion: d.descripcion.trim() || null,
      precio: d.precio,
      inventario_disponible: d.inventario,
    })
    .eq('id', id);
  if (error) {
    console.warn('[productos] actualizar', error.message);
    return MENSAJE;
  }
}

export async function cambiarDisponibilidadProducto(id: string, activo: boolean): Promise<string | undefined> {
  const { error } = await supabase.from('productos').update({ activo }).eq('id', id);
  if (error) {
    console.warn('[productos] disponibilidad', error.message);
    return MENSAJE;
  }
}

/**
 * Elimina el producto. Si ya forma parte de pedidos (llave foránea 23503) no se puede borrar
 * sin perder el historial: en ese caso se desactiva y se devuelve 'desactivado'.
 */
export async function eliminarProducto(id: string): Promise<'eliminado' | 'desactivado' | string> {
  const { error } = await supabase.from('productos').delete().eq('id', id);
  if (!error) return 'eliminado';
  if (error.code === '23503') {
    const fallo = await cambiarDisponibilidadProducto(id, false);
    return fallo ?? 'desactivado';
  }
  console.warn('[productos] eliminar', error.message);
  return MENSAJE;
}
