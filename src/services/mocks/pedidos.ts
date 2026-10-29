import { Pedido } from '../../types';

const haceMinutos = (min: number) => new Date(Date.now() - min * 60000).toISOString();

export const pedidosMock: Pedido[] = [
  {
    id: 'ped-1042',
    numero: 1042,
    comercioId: 'c1',
    solicitante: 'Carlos',
    estado: 'Creado',
    listoParaRecoger: false,
    items: [
      { nombre: 'Hamburguesa Corral', cantidad: 2 },
      { nombre: 'Papas medianas', cantidad: 1 },
    ],
    total: 52000,
    creadoEn: haceMinutos(3),
  },
  {
    id: 'ped-1041',
    numero: 1041,
    comercioId: 'c1',
    solicitante: 'Laura',
    estado: 'Asignado',
    listoParaRecoger: false,
    items: [{ nombre: 'Hamburguesa Corral', cantidad: 1 }],
    total: 22000,
    creadoEn: haceMinutos(12),
  },
  {
    id: 'ped-1040',
    numero: 1040,
    comercioId: 'c1',
    solicitante: 'Andrés',
    estado: 'En Camino',
    listoParaRecoger: true,
    items: [{ nombre: 'Papas medianas', cantidad: 2 }],
    total: 16000,
    creadoEn: haceMinutos(25),
  },
  {
    id: 'ped-1039',
    numero: 1039,
    comercioId: 'c1',
    solicitante: 'Marta',
    estado: 'Entregado',
    listoParaRecoger: true,
    items: [
      { nombre: 'Hamburguesa Corral', cantidad: 1 },
      { nombre: 'Gaseosa 400 ml', cantidad: 1 },
    ],
    total: 27000,
    creadoEn: haceMinutos(60),
  },
  {
    id: 'ped-1043',
    numero: 1043,
    comercioId: 'c2',
    solicitante: 'Julián',
    estado: 'Creado',
    listoParaRecoger: false,
    items: [{ nombre: 'Torta Casera', cantidad: 1 }],
    total: 42000,
    creadoEn: haceMinutos(5),
  },
];