export const VERSION_LEGAL = '0.1-borrador';
export const FECHA_VERSION = '28/10/2026';
export const AVISO_BORRADOR =
  'Texto provisional. Pendiente de revisión por el área jurídica de la organización.';

export type SeccionLegal = {
  titulo: string;
  cuerpo: string;
};

export const TERMINOS: SeccionLegal[] = [
  {
    titulo: '1. Uso del servicio',
    cuerpo:
      'DeskDrop conecta a miembros de la comunidad universitaria con comercios y domiciliarios dentro del campus.',
  },
  {
    titulo: '2. Cuenta',
    cuerpo:
      'Debes registrarte con tu correo institucional y mantener tu contraseña en reserva.',
  },
  {
    titulo: '3. Pedidos y entregas',
    cuerpo:
      'Las entregas se hacen solo en las zonas habilitadas del campus. No se llevan pedidos a aulas ni a lugares cerrados.',
  },
  {
    titulo: '4. Pagos',
    cuerpo: 'Las condiciones de pago se informarán antes de abrir el servicio.',
  },
  {
    titulo: '5. Cambios',
    cuerpo:
      'Podemos actualizar estos términos. Cuando cambien, te pediremos aceptar la nueva versión.',
  },
];

export const PRIVACIDAD: SeccionLegal[] = [
  {
    titulo: '1. Qué datos guardamos',
    cuerpo:
      'Tu nombre, fecha de nacimiento, tipo y número de documento, correo institucional, historial de pedidos y la ubicación de entrega.',
  },
  {
    titulo: '2. Para qué los usamos',
    cuerpo: 'Para crear tu cuenta, gestionar tus pedidos y coordinar las entregas.',
  },
  {
    titulo: '3. Ubicación',
    cuerpo:
      'La ubicación de entrega solo se conserva el tiempo necesario para completar el pedido.',
  },
  {
    titulo: '4. Tus derechos',
    cuerpo: 'Puedes solicitar la eliminación de tu cuenta y de tus datos personales.',
  },
  {
    titulo: '5. Contacto',
    cuerpo: 'Canal de contacto por definir.',
  },
];
