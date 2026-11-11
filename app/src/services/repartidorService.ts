import { supabase } from '../lib/supabase';
import { VERSION_CONDICIONES_REPARTIDOR } from '../utils/legal';

// HU-19: cualquier usuario puede usar la vista de domiciliario tras declarar una vez que tiene
// 18 años o más. La aceptación la guarda la base (tabla aceptaciones_repartidor).

type Resultado = { ok: true } | { ok: false; mensaje: string };

/** ¿El usuario con sesión ya aceptó la declaración de repartidor? */
export async function estaHabilitadoRepartidor(): Promise<boolean> {
  const { data, error } = await supabase.from('aceptaciones_repartidor').select('version').limit(1);
  if (error) {
    console.warn('[repartidor] habilitado:', error.code, error.message);
    return false;
  }
  return (data?.length ?? 0) > 0;
}

/** Registra la declaración de +18 y habilita la vista de domiciliario (idempotente). */
export async function activarModoRepartidor(): Promise<Resultado> {
  const { error } = await supabase.rpc('activar_modo_repartidor', {
    p_acepta_mayor_edad: true,
    p_version: VERSION_CONDICIONES_REPARTIDOR,
  });
  if (error) {
    console.warn('[repartidor] activar:', error.code, error.message);
    return { ok: false, mensaje: 'No se pudo activar la vista de domiciliario. Inténtalo de nuevo' };
  }
  return { ok: true };
}

/** ¿Tiene entregas sin terminar (Asignado o En Camino)? Impide volver a la vista de solicitante. */
export async function tieneEntregasEnCurso(): Promise<boolean> {
  const { count, error } = await supabase
    .from('pedidos')
    .select('id', { count: 'exact', head: true })
    .in('estado', ['Asignado', 'En Camino'])
    .eq('repartidor_id', (await supabase.auth.getUser()).data.user?.id ?? '');
  if (error) {
    console.warn('[repartidor] entregas en curso:', error.code, error.message);
    return false;
  }
  return (count ?? 0) > 0;
}
