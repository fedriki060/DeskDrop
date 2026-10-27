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