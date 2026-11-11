import { Rol, RolBase } from '../types';

export type RutaInicial = '/' | '/entregas' | '/bandeja';

export function rutaInicial(rol: Rol): RutaInicial {
  if (rol === 'domiciliario') return '/entregas';
  if (rol === 'comercio') return '/bandeja';
  return '/';
}

// Traduce el rol guardado en la base a los modos que la app puede mostrar.
// PROVISIONAL: la base tiene un solo rol por perfil; si el equipo decide varios roles por
// usuario, solo cambia esta función. Admin todavía no tiene pantallas propias.
export function rolesDesdeBase(rol: RolBase): Rol[] {
  switch (rol) {
    case 'repartidor':
      return ['solicitante', 'domiciliario'];
    case 'comercio':
      return ['comercio'];
    default:
      return ['solicitante'];
  }
}

export const etiquetasRol: Record<Rol, string> = {
  solicitante: 'Solicitante',
  domiciliario: 'Domiciliario',
  comercio: 'Comercio',
};