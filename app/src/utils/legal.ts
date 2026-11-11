export const VERSION_LEGAL = '0.2-borrador';
export const FECHA_VERSION = '11/11/2026';
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
      'Tu nombre, correo institucional, celular (opcional), historial de pedidos y punto de entrega. Si eres domiciliario, también tu calificación promedio y la declaración de mayoría de edad.',
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

// Declaración que se acepta una sola vez al activar la vista de domiciliario (HU-19).
// Cambiar la versión obliga a aceptarla de nuevo: súbela solo si cambia el sentido del texto.
export const VERSION_CONDICIONES_REPARTIDOR = '0.1-borrador';

export const CONDICIONES_REPARTIDOR: SeccionLegal[] = [
  {
    titulo: 'Mayoría de edad',
    cuerpo: 'Para entregar pedidos debes tener 18 años o más.',
  },
  {
    titulo: 'Entregas',
    cuerpo:
      'Entregas solo en los puntos habilitados del campus. Al recibir el pedido debes pedir al solicitante su código de 4 dígitos.',
  },
  {
    titulo: 'Pagos en efectivo',
    cuerpo: 'Si el pedido es en efectivo, debes cobrar el total y registrarlo en la app.',
  },
];
