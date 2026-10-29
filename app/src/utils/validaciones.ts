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