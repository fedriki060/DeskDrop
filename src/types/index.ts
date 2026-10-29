export type Rol = 'solicitante' | 'domiciliario' | 'comercio';

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