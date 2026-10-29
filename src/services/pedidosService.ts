import { Pedido } from '../types';
import { pedidosMock } from './mocks/pedidos';

const esperar = (ms = 300) => new Promise<void>((resolve) => setTimeout(resolve, ms));

// SIMULADO: reemplazar por la API de pedidos del comercio (T-029)
export async function listarPedidosComercio(comercioId: string): Promise<Pedido[]> {
  await esperar();
  return pedidosMock
    .filter((p) => p.comercioId === comercioId)
    .map((p) => ({ ...p }))
    .sort((a, b) => b.creadoEn.localeCompare(a.creadoEn));
}

// Solo cambia el indicador; el comercio nunca modifica el estado de logística
export async function marcarListoParaRecoger(pedidoId: string): Promise<void> {
  await esperar();
  const pedido = pedidosMock.find((p) => p.id === pedidoId);
  if (pedido && (pedido.estado === 'Creado' || pedido.estado === 'Asignado')) {
    pedido.listoParaRecoger = true;
  }
}

export function puedeMarcarListo(pedido: Pedido): boolean {
  return !pedido.listoParaRecoger && (pedido.estado === 'Creado' || pedido.estado === 'Asignado');
}