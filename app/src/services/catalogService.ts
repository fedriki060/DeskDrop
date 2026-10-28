import { Comercio, Producto, TipoComercio } from '../types';
import { comerciosMock, productosMock } from './mocks/catalogo';

const esperar = (ms = 300) => new Promise<void>((resolve) => setTimeout(resolve, ms));

export async function listarComercios(tipo?: TipoComercio): Promise<Comercio[]> {
  await esperar();
  return tipo ? comerciosMock.filter((c) => c.tipo === tipo) : comerciosMock;
}

export async function obtenerComercio(id: string): Promise<Comercio | undefined> {
  await esperar();
  return comerciosMock.find((c) => c.id === id);
}

export async function listarProductos(comercioId: string): Promise<Producto[]> {
  await esperar();
  return productosMock.filter((p) => p.comercioId === comercioId);
}

export async function obtenerProducto(id: string): Promise<Producto | undefined> {
  await esperar();
  return productosMock.find((p) => p.id === id);
}