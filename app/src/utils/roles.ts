import { Rol, RolBase } from '../types';

export type RutaInicial = '/' | '/entregas' | '/bandeja';

export function rutaInicial(rol: Rol): RutaInicial {
  if (rol === 'domiciliario') return '/entregas';
  if (rol === 'comercio') return '/bandeja';
  return '/';
}

// Traduce el rol guardado en la base a los modos que la app puede mostrar.
// Cualquier solicitante (o repartidor heredado) puede ser domiciliario tras declarar que tiene
// 18 años o más (`habilitadoRepartidor`, HU-19). Admin todavía no tiene pantallas propias.
export function rolesDesdeBase(rol: RolBase, habilitadoRepartidor = false): Rol[] {
  switch (rol) {
    case 'repartidor':
    case 'solicitante':
      return habilitadoRepartidor ? ['solicitante', 'domiciliario'] : ['solicitante'];
    case 'comercio':
      return ['comercio'];
    default:
      return ['solicitante'];
  }
}

/** ¿Puede este rol de la base pedir la vista de domiciliario (aunque aún no la haya activado)? */
export function puedeActivarRepartidor(rol: RolBase): boolean {
  return rol === 'solicitante' || rol === 'repartidor';
}

export const etiquetasRol: Record<Rol, string> = {
  solicitante: 'Solicitante',
  domiciliario: 'Domiciliario',
  comercio: 'Comercio',
};