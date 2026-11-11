let contador = 0;

/**
 * Nombre único para un canal de Realtime. supabase-js devuelve el canal existente si el nombre
 * se repite; si ese canal ya está suscrito (por ejemplo al volver a montar una pantalla mientras
 * el anterior aún se cierra), agregarle un listener lanza error. Con un sufijo cada suscripción
 * tiene su propio canal.
 */
export function nombreCanal(base: string): string {
  contador += 1;
  return `${base}-${contador}`;
}
