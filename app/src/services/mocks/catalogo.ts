import { Comercio, Producto } from '../../types';

export const comerciosMock: Comercio[] = [
  { id: 'c1', tipo: 'restaurante', nombre: 'El Corral', descripcion: 'Hamburguesas y comidas rápidas' },
  { id: 'c2', tipo: 'restaurante', nombre: 'La Miguería', descripcion: 'Postres, tortas y bebidas' },
  { id: 'c3', tipo: 'utensilios', nombre: 'Papelería', descripcion: 'Útiles y papelería del campus' },
  { id: 'c4', tipo: 'utensilios', nombre: 'Librería Universitaria', descripcion: 'Calculadoras, libros y más' },
];

export const productosMock: Producto[] = [
  { id: 'p1', comercioId: 'c1', nombre: 'Hamburguesa Corral', descripcion: 'Carne, queso, lechuga y tomate', precio: 22000, inventario: 15 },
  { id: 'p2', comercioId: 'c1', nombre: 'Papas medianas', descripcion: 'Porción mediana de papas fritas', precio: 8000, inventario: 30 },
  { id: 'p3', comercioId: 'c1', nombre: 'Gaseosa 400 ml', descripcion: 'Variedad de sabores', precio: 5000, inventario: 0 },
  { id: 'p4', comercioId: 'c2', nombre: 'Torta Casera', descripcion: '10 porciones', precio: 42000, inventario: 5 },
  { id: 'p5', comercioId: 'c2', nombre: 'Malteada de Vainilla', descripcion: 'Tamaño mediano', precio: 16000, inventario: 12 },
  { id: 'p6', comercioId: 'c2', nombre: 'Galletas de avena', descripcion: 'Paquete de 6 unidades', precio: 9000, inventario: 20 },
  { id: 'p7', comercioId: 'c3', nombre: 'Cuaderno 100 hojas', descripcion: 'Rayado, tapa dura', precio: 7500, inventario: 40 },
  { id: 'p8', comercioId: 'c3', nombre: 'Lapicero negro', descripcion: 'Punta fina', precio: 2000, inventario: 100 },
  { id: 'p9', comercioId: 'c4', nombre: 'Calculadora científica', descripcion: 'Con 240 funciones', precio: 65000, inventario: 8 },
  { id: 'p10', comercioId: 'c4', nombre: 'Resaltadores x4', descripcion: 'Colores surtidos', precio: 12000, inventario: 25 },
];