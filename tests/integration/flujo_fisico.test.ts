// Flujo completo del piloto con pago físico (HU-27), de punta a punta contra la base LOCAL de Supabase:
// solicitante crea el pedido -> comercio lo marca listo -> domiciliario lo acepta y lo recoge ->
// el solicitante recibe el código de 4 dígitos -> el domiciliario lo digita (primero mal, luego bien) ->
// cobro en efectivo. Mientras tanto el solicitante recibe cada cambio de estado por Realtime.
// También cubre el rechazo del comercio (se repone el inventario).
//
// Requiere: npx supabase start y npx supabase db reset (con todas las migraciones aplicadas).
import { execSync } from 'node:child_process';
import { createClient, type RealtimeChannel, type SupabaseClient } from '@supabase/supabase-js';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

function configLocal(): { url: string; anonKey: string; serviceKey: string } {
  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (url && anonKey && serviceKey) return { url, anonKey, serviceKey };
  const salida = execSync('npx supabase status -o json', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  const estado = JSON.parse(salida.slice(salida.indexOf('{')));
  return {
    url: url ?? estado.API_URL,
    anonKey: anonKey ?? estado.PUBLISHABLE_KEY ?? estado.ANON_KEY,
    serviceKey: serviceKey ?? estado.SECRET_KEY ?? estado.SERVICE_ROLE_KEY,
  };
}

const { url, anonKey, serviceKey } = configLocal();
const dominio = process.env.TEST_EMAIL_DOMAIN ?? 'example.com';
const password = 'Prueba-12345!';
const corrida = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
const opcionesAuth = { auth: { persistSession: false, autoRefreshToken: false } };
const admin = createClient(url, serviceKey, opcionesAuth);

type Usuario = { id: string; cliente: SupabaseClient };
type Evento = { id: string; estado: string };

const usuariosCreados: string[] = [];
const clientes: SupabaseClient[] = [];
let comercioId = '';
let zonaId = '';
let productoId = '';
let puntoId = '';

async function ok<T>(promesa: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await promesa;
  if (error) throw new Error(error.message);
  return data;
}
const esperar = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

async function crearUsuario(etiqueta: string, rol: 'solicitante' | 'comercio'): Promise<Usuario> {
  const email = `ff-${corrida}-${etiqueta}@${dominio}`;
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (error || !data.user) throw new Error(`createUser ${etiqueta}: ${error?.message}`);
  const id = data.user.id;
  usuariosCreados.push(id);
  await ok(admin.from('perfiles').upsert({ id, email, nombre_completo: `Prueba ${etiqueta}`, rol }, { onConflict: 'id' }).select());
  const cliente = createClient(url, anonKey, opcionesAuth);
  clientes.push(cliente);
  const { data: sesion, error: errLogin } = await cliente.auth.signInWithPassword({ email, password });
  if (errLogin || !sesion.session) throw new Error(`login ${etiqueta}: ${errLogin?.message}`);
  await cliente.realtime.setAuth(sesion.session.access_token);
  return { id, cliente };
}

/** Se suscribe a los cambios de `pedidos` y espera a que la replicación esté lista. */
async function escuchar(cliente: SupabaseClient, nombre: string): Promise<{ eventos: Evento[]; canal: RealtimeChannel }> {
  const eventos: Evento[] = [];
  const canal: RealtimeChannel = cliente.channel(`ff-${corrida}-${nombre}`, { config: { broadcast: { replication_ready: true } } });
  await new Promise<void>((resolve, reject) => {
    let suscrito = false;
    let lista = false;
    const revisar = () => suscrito && lista && resolve();
    const limite = setTimeout(() => reject(new Error(`no se pudo suscribir ${nombre}`)), 15000);
    canal
      .on('postgres_changes', { event: '*', schema: 'public', table: 'pedidos' }, (c) => {
        const fila = (c.new ?? {}) as { id?: string; estado?: string };
        eventos.push({ id: fila.id ?? '', estado: fila.estado ?? '' });
      })
      .on('system', {}, (aviso: { status?: string }) => {
        if (aviso.status === 'ok') { lista = true; revisar(); }
      })
      .subscribe((estado, err) => {
        if (estado === 'SUBSCRIBED') {
          suscrito = true;
          setTimeout(() => { lista = true; revisar(); clearTimeout(limite); }, 8000);
          revisar();
        } else if (estado === 'CHANNEL_ERROR' || estado === 'TIMED_OUT') {
          clearTimeout(limite);
          reject(err ?? new Error(`${nombre}: ${estado}`));
        }
      });
  });
  return { eventos, canal };
}

async function esperarEstado(eventos: Evento[], pedidoId: string, estado: string, ms = 5000): Promise<boolean> {
  const fin = Date.now() + ms;
  while (Date.now() < fin) {
    if (eventos.some((e) => e.id === pedidoId && e.estado === estado)) return true;
    await esperar(50);
  }
  return false;
}

let solicitante: Usuario;
let domiciliario: Usuario;
let dueno: Usuario;

async function inventario(): Promise<number> {
  const p = await ok(admin.from('productos').select('inventario_disponible').eq('id', productoId).single());
  return p.inventario_disponible;
}

beforeAll(async () => {
  dueno = await crearUsuario('comercio', 'comercio');
  solicitante = await crearUsuario('solicitante', 'solicitante');
  domiciliario = await crearUsuario('domiciliario', 'solicitante'); // se vuelve domiciliario con el modo repartidor

  comercioId = (await ok(admin.from('comercios').insert({ administrador_id: dueno.id, nombre: `Comercio ff ${corrida}`, activo: true }).select('id').single())).id;
  zonaId = (await ok(admin.from('zonas_campus').insert({ nombre: `Zona ff ${corrida}`, activo: true }).select('id').single())).id;
  puntoId = (await ok(admin.from('puntos_entrega').insert({ zona_id: zonaId, nombre: 'Dentro', latitud: 6.1667, longitud: -75.5667, activo: true }).select('id').single())).id;
  productoId = (await ok(admin.from('productos').insert({ comercio_id: comercioId, nombre: 'Producto ff', precio: 5000, inventario_disponible: 10 }).select('id').single())).id;

  // Declaración de mayoría de edad: habilita al usuario para tomar entregas (HU-19)
  await ok(domiciliario.cliente.rpc('activar_modo_repartidor', { p_acepta_mayor_edad: true, p_version: 'v1' }));
}, 60000);

afterAll(async () => {
  await Promise.all(clientes.map((c) => c.removeAllChannels()));
  await admin.from('pedidos').delete().in('solicitante_id', usuariosCreados);
  await admin.from('productos').delete().eq('comercio_id', comercioId);
  await admin.from('comercios').delete().eq('id', comercioId);
  await admin.from('puntos_entrega').delete().eq('zona_id', zonaId);
  await admin.from('zonas_campus').delete().eq('id', zonaId);
  for (const id of usuariosCreados) await admin.auth.admin.deleteUser(id);
});

describe('Flujo físico completo: código de entrega y pago en efectivo', () => {
  it('lleva el pedido de Creado a Entregado y registra el cobro, con seguimiento en vivo', async () => {
    const { eventos, canal } = await escuchar(solicitante.cliente, 'flujo');
    const antes = await inventario();

    const creado = await ok(
      solicitante.cliente.rpc('crear_pedido', { p_punto_entrega_id: puntoId, p_items: [{ producto_id: productoId, cantidad: 2 }] }),
    );
    const pedidoId: string = creado.pedido_id;
    expect(await inventario()).toBe(antes - 2);

    // El domiciliario acepta, pero no puede recoger hasta que el comercio marque el pedido listo
    await ok(domiciliario.cliente.rpc('aceptar_pedido', { p_pedido_id: pedidoId }));
    const recogidaTemprana = await domiciliario.cliente.rpc('confirmar_recogida', { p_pedido_id: pedidoId });
    expect(recogidaTemprana.error?.message).toMatch(/PEDIDO_NO_LISTO/);

    // El comercio marca listo; el domiciliario recoge
    await ok(dueno.cliente.rpc('marcar_listo_para_recoger', { p_pedido_id: pedidoId }));
    await ok(domiciliario.cliente.rpc('confirmar_recogida', { p_pedido_id: pedidoId }));
    expect(await esperarEstado(eventos, pedidoId, 'Asignado')).toBe(true);
    expect(await esperarEstado(eventos, pedidoId, 'En Camino')).toBe(true);

    // Solo el solicitante dueño puede leer el código; el domiciliario no
    const codigo = (await ok(solicitante.cliente.from('codigos_entrega').select('codigo').eq('pedido_id', pedidoId).single())).codigo;
    expect(codigo).toMatch(/^\d{4}$/);
    const lecturaDomiciliario = await domiciliario.cliente.from('codigos_entrega').select('codigo').eq('pedido_id', pedidoId);
    expect(lecturaDomiciliario.data ?? []).toHaveLength(0);

    // Código incorrecto: no confirma y descuenta un intento
    const incorrecto = codigo === '0000' ? '1111' : '0000';
    const mal = await ok(domiciliario.cliente.rpc('confirmar_entrega', { p_pedido_id: pedidoId, p_codigo: incorrecto }));
    expect(mal.ok).toBe(false);
    expect(mal.intentos_restantes).toBe(4);

    // Código correcto: Entregado
    const bien = await ok(domiciliario.cliente.rpc('confirmar_entrega', { p_pedido_id: pedidoId, p_codigo: codigo }));
    expect(bien.ok).toBe(true);
    expect(await esperarEstado(eventos, pedidoId, 'Entregado')).toBe(true);

    // Cobro en efectivo
    await ok(domiciliario.cliente.rpc('registrar_cobro_efectivo', { p_pedido_id: pedidoId }));
    const pago = await ok(admin.from('pagos').select('estado, monto').eq('pedido_id', pedidoId).single());
    expect(pago.estado).toBe('cobrado');
    expect(Number(pago.monto)).toBe(Number(creado.total));

    await solicitante.cliente.removeChannel(canal);
  }, 60000);

  it('rechazo del comercio: el pedido se cancela y el inventario vuelve', async () => {
    const antes = await inventario();
    const creado = await ok(
      solicitante.cliente.rpc('crear_pedido', { p_punto_entrega_id: puntoId, p_items: [{ producto_id: productoId, cantidad: 3 }] }),
    );
    expect(await inventario()).toBe(antes - 3);

    await ok(dueno.cliente.rpc('cancelar_pedido', { p_pedido_id: creado.pedido_id, p_motivo: 'Sin inventario' }));
    const pedido = await ok(admin.from('pedidos').select('estado, cancelado_por').eq('id', creado.pedido_id).single());
    expect(pedido.estado).toBe('Cancelado');
    expect(pedido.cancelado_por).toBe('comercio');
    expect(await inventario()).toBe(antes);
  }, 30000);
});
