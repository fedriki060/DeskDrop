import { createContext, ReactNode, useContext, useState } from 'react';
import { Producto } from '../types';

export type ItemCarrito = {
  producto: Producto;
  cantidad: number;
};

type CarritoContextType = {
  items: ItemCarrito[];
  comercioId?: string;
  totalUnidades: number;
  total: number;
  agregar: (producto: Producto, cantidad: number) => void;
  quitar: (productoId: string) => void;
  cambiarCantidad: (productoId: string, cantidad: number) => void;
  vaciar: () => void;
};

const CarritoContext = createContext<CarritoContextType | undefined>(undefined);

export function CarritoProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ItemCarrito[]>([]);

  const agregar = (producto: Producto, cantidad: number) => {
    setItems((prev) => {
      const existente = prev.find((i) => i.producto.id === producto.id);
      if (existente) {
        return prev.map((i) =>
          i.producto.id === producto.id
            ? { ...i, cantidad: Math.min(i.cantidad + cantidad, producto.inventario) }
            : i
        );
      }
      return [...prev, { producto, cantidad: Math.min(cantidad, producto.inventario) }];
    });
  };

  const quitar = (productoId: string) => {
    setItems((prev) => prev.filter((i) => i.producto.id !== productoId));
  };

  const cambiarCantidad = (productoId: string, cantidad: number) => {
    setItems((prev) =>
      cantidad <= 0
        ? prev.filter((i) => i.producto.id !== productoId)
        : prev.map((i) =>
            i.producto.id === productoId
              ? { ...i, cantidad: Math.min(cantidad, i.producto.inventario) }
              : i
          )
    );
  };

  const vaciar = () => setItems([]);

  const comercioId = items[0]?.producto.comercioId;
  const totalUnidades = items.reduce((suma, i) => suma + i.cantidad, 0);
  const total = items.reduce((suma, i) => suma + i.cantidad * i.producto.precio, 0);

  return (
    <CarritoContext.Provider
      value={{ items, comercioId, totalUnidades, total, agregar, quitar, cambiarCantidad, vaciar }}
    >
      {children}
    </CarritoContext.Provider>
  );
}

export function useCarrito() {
  const contexto = useContext(CarritoContext);
  if (!contexto) {
    throw new Error('useCarrito debe usarse dentro de CarritoProvider');
  }
  return contexto;
}