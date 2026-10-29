// Modos de uso de la app (qué pestañas ve el usuario). Se derivan del rol de la base
// con rolesDesdeBase (utils/roles.ts); un repartidor puede usar la app como solicitante o domiciliario.
export type Rol = 'solicitante' | 'domiciliario' | 'comercio';

// Valores del enum rol_usuario en la base de datos (un rol por perfil)
export type RolBase = 'solicitante' | 'repartidor' | 'comercio' | 'admin';

export type Perfil = {
  id: string;
  email: string;
  nombreCompleto: string;
  rol: RolBase;
};

export type TipoComercio = 'restaurante' | 'utensilios';

export type Comercio = {
  id: string;
  tipo: TipoComercio;
  nombre: string;
  descripcion: string;
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
  numero: number;
  comercioId: string;
  solicitante: string;
  estado: EstadoPedido;
  listoParaRecoger: boolean;
  items: ItemPedido[];
  total: number;
  creadoEn: string;
};