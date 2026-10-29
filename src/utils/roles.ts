import { Rol } from '../types';

export type RutaInicial = '/' | '/entregas' | '/bandeja';

export function rutaInicial(rol: Rol): RutaInicial {
  if (rol === 'domiciliario') return '/entregas';
  if (rol === 'comercio') return '/bandeja';
  return '/';
}

export const etiquetasRol: Record<Rol, string> = {
  solicitante: 'Solicitante',
  domiciliario: 'Domiciliario',
  comercio: 'Comercio',
};