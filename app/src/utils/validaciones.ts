// Debe coincidir con la tabla dominios_permitidos de la base de datos.
export const DOMINIO_INSTITUCIONAL = '@eia.edu.co';

// Deben coincidir con [auth] de supabase/config.toml y con el panel de staging:
// minimum_password_length = 8 y password_requirements = "lower_upper_letters_digits"
export const LONGITUD_MINIMA_CONTRASENA = 8;
export const REQUISITOS_CONTRASENA = 'Mínimo 8 caracteres, con mayúscula, minúscula y número';

export function esCorreoInstitucional(correo: string): boolean {
  const limpio = correo.trim().toLowerCase();
  return limpio.endsWith(DOMINIO_INSTITUCIONAL) && limpio.length > DOMINIO_INSTITUCIONAL.length;
}

export function esContrasenaSegura(contrasena: string): boolean {
  return (
    contrasena.length >= LONGITUD_MINIMA_CONTRASENA &&
    /[a-z]/.test(contrasena) &&
    /[A-Z]/.test(contrasena) &&
    /\d/.test(contrasena)
  );
}

// Celular colombiano: 10 dígitos que empiezan por 3. Debe coincidir con perfiles_telefono_formato.
export function normalizarTelefono(texto: string): string {
  const digitos = texto.replace(/\D/g, '');
  return digitos.length === 12 && digitos.startsWith('57') ? digitos.slice(2) : digitos;
}

export function esTelefonoValido(texto: string): boolean {
  return /^3\d{9}$/.test(normalizarTelefono(texto));
}
