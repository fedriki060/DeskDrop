import { VERSION_LEGAL } from '../utils/legal';

export type Aceptacion = {
  usuario: string;
  fecha: string;
  version: string;
};

// SIMULADO: el registro real lo guarda el backend junto con el alta de la cuenta (T-068)
export async function registrarAceptacion(usuario: string): Promise<Aceptacion> {
  await new Promise<void>((resolve) => setTimeout(resolve, 300));
  return {
    usuario,
    fecha: new Date().toISOString(),
    version: VERSION_LEGAL,
  };
}
