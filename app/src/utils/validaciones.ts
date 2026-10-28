// Dominio tomado del diseño de referencia; confirmar con el equipo.
export const DOMINIO_INSTITUCIONAL = '@eia.edu.co';

export const LONGITUD_MINIMA_CONTRASENA = 8;

export const TIPOS_DOCUMENTO = ['CC', 'TI', 'CE', 'Pasaporte'] as const;
export type TipoDocumento = (typeof TIPOS_DOCUMENTO)[number];

export function esCorreoInstitucional(correo: string): boolean {
  const limpio = correo.trim().toLowerCase();
  return limpio.endsWith(DOMINIO_INSTITUCIONAL) && limpio.length > DOMINIO_INSTITUCIONAL.length;
}

// Convierte lo que escribe el usuario en DD/MM/AAAA mientras teclea
export function formatearFecha(texto: string): string {
  const d = texto.replace(/\D/g, '').slice(0, 8);
  if (d.length <= 2) return d;
  if (d.length <= 4) return `${d.slice(0, 2)}/${d.slice(2)}`;
  return `${d.slice(0, 2)}/${d.slice(2, 4)}/${d.slice(4)}`;
}

export function esFechaValida(texto: string): boolean {
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(texto);
  if (!m) return false;
  const dia = Number(m[1]);
  const mes = Number(m[2]);
  const anio = Number(m[3]);
  const fecha = new Date(anio, mes - 1, dia);
  return (
    anio >= 1900 &&
    fecha.getFullYear() === anio &&
    fecha.getMonth() === mes - 1 &&
    fecha.getDate() === dia &&
    fecha <= new Date()
  );
}

export function esDocumentoValido(numero: string): boolean {
  return /^[A-Za-z0-9]{5,15}$/.test(numero.trim());
}