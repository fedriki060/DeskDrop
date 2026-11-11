// Modos de uso de la app (qué pestañas ve el usuario). Se derivan del rol de la base
// con rolesDesdeBase (utils/roles.ts); un repartidor puede usar la app como solicitante o domiciliario.
export type Rol = 'solicitante' | 'domiciliario' | 'comercio';

// Valores del enum rol_usuario en la base de datos (un rol por perfil)
export type RolBase = 'solicitante' | 'repartidor' | 'comercio' | 'admin';

export type Perfil = {
  id: string;
  email: string;
  nombreCompleto: string;
  /** Celular de contacto (10 dígitos) o null si no lo ha registrado */
  telefono: string | null;
  rol: RolBase;
};

export type TipoComercio = 'restaurante' | 'utensilios';

export type Comercio = {
  id: string;
  tipo: TipoComercio;
  nombre: string;
  descripcion: string;
  /** Foto del comercio; si no tiene, la app muestra la letra inicial */
  imagenUrl?: string;
};

export type Producto = {
  id: string;
  comercioId: string;
  nombre: string;
  descripcion: string;
  precio: number;
  inventario: number;
  imagenUrl?: string;
};

export type EstadoPedido =
  | 'Creado'
  | 'Asignado'
  | 'En Camino'
  | 'Entregado'
  | 'Cerrado'
  | 'Cancelado';

export type ItemPedido = {
  nombre: string;
  cantidad: number;
};

export type Pedido = {
  id: string;
  /** Número corto que asigna la base (pedidos.numero) */
  numero: number;
  comercioId: string;
  solicitante: string;
  /** Primer nombre del domiciliario, cuando ya aceptó el pedido */
  repartidor?: string;
  estado: EstadoPedido;
  listoParaRecoger: boolean;
  items: ItemPedido[];
  total: number;
  creadoEn: string;
};

// Pedido visto por el domiciliario: lo que necesita para aceptarlo, recogerlo, entregarlo y cobrarlo
export type Entrega = {
  id: string;
  numero: number;
  estado: EstadoPedido;
  listoParaRecoger: boolean;
  total: number;
  comercio: string;
  puntoEntrega: string;
  indicaciones: string | null;
  notas: string | null;
  items: ItemPedido[];
  /** true si ya lo tiene asignado este domiciliario; false si está disponible para aceptar */
  esMia: boolean;
  /** Primer nombre y celular del solicitante: solo en los pedidos que ya tomó este domiciliario */
  solicitante: string | null;
  solicitanteTelefono: string | null;
};
