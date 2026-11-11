import { supabase } from '../lib/supabase';
import { VERSION_LEGAL } from '../utils/legal';

// Al registrarse, la aceptación la guarda la base (trigger crear_perfil) con la versión que
// envía AuthContext.registrar. Estas funciones sirven para cuando cambie VERSION_LEGAL:
// pedirle al usuario con sesión que acepte la versión nueva.

export type Aceptacion = {
  version: string;
  fecha: string;
};

/** Aceptaciones del usuario con sesión, de la más reciente a la más antigua */
export async function listarAceptaciones(): Promise<Aceptacion[]> {
  const { data, error } = await supabase
    .from('consentimientos')
    .select('version, aceptado_en')
    .order('aceptado_en', { ascending: false });
  if (error) {
    console.warn('[consentimiento] listar:', error.code, error.message);
    return [];
  }
  return (data ?? []).map((f) => ({ version: f.version, fecha: f.aceptado_en }));
}

/** ¿El usuario con sesión ya aceptó la versión vigente de los términos? */
export async function aceptoVersionActual(): Promise<boolean> {
  const aceptaciones = await listarAceptaciones();
  return aceptaciones.some((a) => a.version === VERSION_LEGAL);
}

/** Registra que el usuario con sesión acepta la versión vigente. La fecha la pone la base. */
export async function aceptarVersionActual(): Promise<boolean> {
  const { error } = await supabase.from('consentimientos').insert({ version: VERSION_LEGAL });
  // 23505 = ya la había aceptado: para el usuario es lo mismo que aceptarla ahora
  if (error && error.code !== '23505') {
    console.warn('[consentimiento] aceptar:', error.code, error.message);
    return false;
  }
  return true;
}