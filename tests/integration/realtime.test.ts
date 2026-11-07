// Pruebas de punta a punta del seguimiento en vivo (T-046) contra la base LOCAL de Supabase.
// Requiere: npx supabase start y npx supabase db reset (para tener la migración realtime_pedidos).
//
// Cada usuario abre su propio cliente con su sesión y se suscribe a los cambios de `pedidos`.
// Se comprueba que Realtime entrega a cada uno SOLO los eventos que su RLS le deja ver
// y que el cambio de estado llega en menos de 2 s.
//
// Ojo: Realtime pierde los cambios que ocurren antes de que su conexión de replicación con
// Postgres esté lista. Por eso cada suscripción espera el aviso `replication_ready` y, antes de
// las pruebas, se "calienta" Realtime hasta que entregue un evento.
import { execSync } from 'node:child_process';
import { createClient, type RealtimeChannel, type SupabaseClient } from '@supabase/supabase-js';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

// ---------------------------------------------------------------------------
// Configuración local (variables de entorno o, si no están, la CLI de Supabase)
// ---------------------------------------------------------------------------
function configLocal(): { url: string; anonKey: string; serviceKey: string } {
  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (url && anonKey && serviceKey) return { url, anonKey, serviceKey };

  const salida = execSync('npx supabase status -o json', {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
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
// Cliente con service_role: solo para preparar datos y simular los cambios de estado
// que harán aceptar_pedido / confirmar_recogida (T-036). Nunca se usa en la app.
const admin = createClient(url, serviceKey, opcionesAuth);

const LATENCIA_MAXIMA_MS = 2000;

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------
type Rol = 'solicitante' | 'repartidor' | 'comercio';
type Usuario = { id: string; cliente: SupabaseClient };
type Evento = { tipo: string; id: string; estado: string; errores: string[]; en: number };

const usuariosCreados: string[] = [];
const clientes: SupabaseClient[] = [];
const comerciosCreados: string[] = [];
const zonasCreadas: string[] = [];

async function ok<T>(promesa: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await promesa;
  if (error) throw new Error(error.message);
  return data;
}

const esperar = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/** Crea un usuario con perfil y devuelve un cliente con su sesión iniciada (también en Realtime). */
async function crearUsuario(etiqueta: string, rol: Rol = 'solicitante'): Promise<Usuario> {
  const email = `rt-${corrida}-${etiqueta}@${dominio}`;
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (error || !data.user) throw new Error(`createUser ${etiqueta}: ${error?.message}`);
  const id = data.user.id;
  usuariosCreados.push(id);

  await ok(
    admin
      .from('perfiles')
      .upsert({ id, email, nombre_completo: `Prueba ${etiqueta}`, rol }, { onConflict: 'id' })
      .select(),
  );

  const cliente = createClient(url, anonKey, opcionesAuth);
  clientes.push(cliente);
  const { data: sesion, error: errLogin } = await cliente.auth.signInWithPassword({ email, password });
  if (errLogin || !sesion.session) throw new Error(`login ${etiqueta}: ${errLogin?.message}`);
  await cliente.realtime.setAuth(sesion.session.access_token);
  return { id, cliente };
}

function aEvento(cambio: { eventType: string; new: unknown; errors?: unknown }): Evento {
  const fila = (cambio.new ?? {}) as { id?: string; estado?: string };
  const errores = Array.isArray(cambio.errors) ? cambio.errors.map(String) : [];
  return { tipo: cambio.eventType, id: fila.id ?? '', estado: fila.estado ?? '', errores, en: Date.now() };
}

/**
 * Se suscribe a todos los cambios de `pedidos` y guarda los eventos que le llegan.
 * Resuelve cuando el canal está suscrito y la replicación de Postgres está lista
 * (si el servidor no manda ese aviso en 8 s, sigue de todas formas).
 * Con `permitirRechazo`, un CHANNEL_ERROR también resuelve (para el cliente anon).
 */
async function escuchar(
  cliente: SupabaseClient,
  nombre: string,
  permitirRechazo = false,
): Promise<{ eventos: Evento[]; canal: RealtimeChannel }> {
  const eventos: Evento[] = [];
  let suscrito = false;
  let replicacionLista = false;

  const canal = cliente.channel(`rt-${corrida}-${nombre}`, {
    config: { broadcast: { replication_ready: true } },
  });

  await new Promise<void>((resolve, reject) => {
    const intentarResolver = () => {
      if (suscrito && replicacionLista) {
        clearTimeout(limite);
        clearTimeout(sinAviso);
        resolve();
      }
    };
    const limite = setTimeout(() => reject(new Error(`no se pudo suscribir ${nombre}`)), 15000);
    let sinAviso: ReturnType<typeof setTimeout>;

    canal
      .on('postgres_changes', { event: '*', schema: 'public', table: 'pedidos' }, (cambio) => {
        eventos.push(aEvento(cambio));
      })
      .on('system', {}, (aviso: { extension?: string; status?: string }) => {
        if (aviso.status === 'ok') {
          replicacionLista = true;
          intentarResolver();
        }
      })
      .subscribe((estado, err) => {
        if (estado === 'SUBSCRIBED') {
          suscrito = true;
          sinAviso = setTimeout(() => {
            replicacionLista = true;
            intentarResolver();
          }, 8000);
          intentarResolver();
        } else if (estado === 'CHANNEL_ERROR' || estado === 'TIMED_OUT') {
          clearTimeout(limite);
          clearTimeout(sinAviso);
          if (permitirRechazo) resolve();
          else reject(err ?? new Error(`${nombre}: ${estado}`));
        }
      });
  });
  return { eventos, canal };
}

/**
 * Realtime arranca su lectura de cambios con la primera suscripción y puede perder los
 * primeros eventos. Se cambia un pedido de prueba hasta que llegue un evento (máx. 30 s).
 */
async function calentarRealtime(): Promise<void> {
  const usuario = await crearUsuario('calentamiento');
  const { eventos, canal } = await escuchar(usuario.cliente, 'calentamiento');
  const creado = await ok(
    usuario.cliente.rpc('crear_pedido', {
      p_punto_entrega_id: puntoDentro,
      p_items: [{ producto_id: productoId, cantidad: 1 }],
    }),
  );
  const fin = Date.now() + 30000;
  for (let i = 0; Date.now() < fin; i++) {
    if (eventos.some((e) => e.id === creado.pedido_id)) {
      await usuario.cliente.removeChannel(canal);
      return;
    }
    await ok(admin.from('pedidos').update({ notas_entrega: `calentamiento ${i}` }).eq('id', creado.pedido_id).select('id'));
    await esperar(500);
  }
  throw new Error('Realtime no entregó ningún evento en 30 s: revisa que esté corriendo (npx supabase status)');
}

/** Espera hasta `ms` a que llegue un evento que cumpla la condición. */
async function esperarEvento(
  eventos: Evento[],
  condicion: (e: Evento) => boolean,
  ms = LATENCIA_MAXIMA_MS + 3000,
): Promise<Evento | undefined> {
  const fin = Date.now() + ms;
  while (Date.now() < fin) {
    const encontrado = eventos.find(condicion);
    if (encontrado) return encontrado;
    await esperar(50);
  }
  return eventos.find(condicion);
}

async function cambiarEstado(pedidoId: string, cambios: Record<string, unknown>): Promise<number> {
  const antes = Date.now();
  await ok(admin.from('pedidos').update(cambios).eq('id', pedidoId).select('id'));
  return antes;
}

// ---------------------------------------------------------------------------
// Escenario: un comercio, un punto dentro del campus y un producto
// ---------------------------------------------------------------------------
let dueno: Usuario;
let puntoDentro: string;
let productoId: string;

beforeAll(async () => {
  dueno = await crearUsuario('comercio', 'comercio');
  const comercio = await ok(
    admin
      .from('comercios')
      .insert({ administrador_id: dueno.id, nombre: `Comercio rt ${corrida}`, activo: true })
      .select('id')
      .single(),
  );
  comerciosCreados.push(comercio.id);

  const zona = await ok(
    admin.from('zonas_campus').insert({ nombre: `Zona rt ${corrida}`, activo: true }).select('id').single(),
  );
  zonasCreadas.push(zona.id);

  const punto = await ok(
    admin
      .from('puntos_entrega')
      .insert({ zona_id: zona.id, nombre: 'Dentro', latitud: 6.1667, longitud: -75.5667, activo: true })
      .select('id')
      .single(),
  );
  puntoDentro = punto.id;

  const producto = await ok(
    admin
      .from('productos')
      .insert({ comercio_id: comercio.id, nombre: 'Producto rt', precio: 5000, inventario_disponible: 10 })
      .select('id')
      .single(),
  );
  productoId = producto.id;

  await calentarRealtime();
}, 60000);

afterAll(async () => {
  await Promise.all(clientes.map((c) => c.removeAllChannels()));
  if (usuariosCreados.length > 0) {
    await admin.from('pedidos').delete().in('solicitante_id', usuariosCreados);
  }
  if (comerciosCreados.length > 0) {
    await admin.from('productos').delete().in('comercio_id', comerciosCreados);
    await admin.from('comercios').delete().in('id', comerciosCreados);
  }
  if (zonasCreadas.length > 0) {
    await admin.from('puntos_entrega').delete().in('zona_id', zonasCreadas);
    await admin.from('zonas_campus').delete().in('id', zonasCreadas);
  }
  for (const id of usuariosCreados) await admin.auth.admin.deleteUser(id);
});

// ---------------------------------------------------------------------------
// Seguimiento en vivo con RLS
// ---------------------------------------------------------------------------
describe('Realtime: cada usuario recibe solo los cambios de sus pedidos', () => {
  it('el pedido nuevo y sus cambios de estado llegan solo a quien puede verlos, en menos de 2 s', async () => {
    const [solA, solB, rep1, rep2] = await Promise.all([
      crearUsuario('sol-a'),
      crearUsuario('sol-b'),
      crearUsuario('rep-1', 'repartidor'),
      crearUsuario('rep-2', 'repartidor'),
    ]);

    const [enA, enB, enRep1, enRep2, enDueno] = await Promise.all([
      escuchar(solA.cliente, 'sol-a'),
      escuchar(solB.cliente, 'sol-b'),
      escuchar(rep1.cliente, 'rep-1'),
      escuchar(rep2.cliente, 'rep-2'),
      escuchar(dueno.cliente, 'comercio'),
    ]);

    // 1. El solicitante A crea su pedido
    const creado = await ok(
      solA.cliente.rpc('crear_pedido', {
        p_punto_entrega_id: puntoDentro,
        p_items: [{ producto_id: productoId, cantidad: 1 }],
      }),
    );
    const pedidoId: string = creado.pedido_id;
    const esInsert = (e: Evento) => e.tipo === 'INSERT' && e.id === pedidoId;

    expect(await esperarEvento(enA.eventos, esInsert), 'A recibe su pedido nuevo').toBeDefined();
    expect(await esperarEvento(enRep1.eventos, esInsert), 'rep1 ve el pedido disponible').toBeDefined();
    expect(await esperarEvento(enRep2.eventos, esInsert), 'rep2 ve el pedido disponible').toBeDefined();
    expect(await esperarEvento(enDueno.eventos, esInsert), 'el comercio recibe el pedido').toBeDefined();

    // 2. rep1 toma el pedido (Creado -> Asignado)
    const antesAsignar = await cambiarEstado(pedidoId, { estado: 'Asignado', repartidor_id: rep1.id });
    const esAsignado = (e: Evento) => e.tipo === 'UPDATE' && e.id === pedidoId && e.estado === 'Asignado';

    const asignadoEnA = await esperarEvento(enA.eventos, esAsignado);
    expect(asignadoEnA, 'A recibe el cambio a Asignado').toBeDefined();
    expect(asignadoEnA!.en - antesAsignar, 'latencia del cambio a Asignado').toBeLessThan(LATENCIA_MAXIMA_MS);
    expect(await esperarEvento(enRep1.eventos, esAsignado), 'rep1 recibe su asignación').toBeDefined();
    expect(await esperarEvento(enDueno.eventos, esAsignado), 'el comercio recibe el cambio').toBeDefined();

    // 3. rep1 recoge el pedido (Asignado -> En Camino)
    const antesSalir = await cambiarEstado(pedidoId, { estado: 'En Camino' });
    const esEnCamino = (e: Evento) => e.tipo === 'UPDATE' && e.id === pedidoId && e.estado === 'En Camino';

    const enCaminoEnA = await esperarEvento(enA.eventos, esEnCamino);
    expect(enCaminoEnA, 'A recibe el cambio a En Camino').toBeDefined();
    expect(enCaminoEnA!.en - antesSalir, 'latencia del cambio a En Camino').toBeLessThan(LATENCIA_MAXIMA_MS);

    // 4. Quien no puede ver el pedido no recibe nada de él
    await esperar(1500);
    expect(enB.eventos.filter((e) => e.id === pedidoId), 'otro solicitante no recibe nada').toHaveLength(0);
    // rep2 lo vio mientras estaba disponible, pero al asignarse a rep1 deja de verlo
    expect(
      enRep2.eventos.filter((e) => e.id === pedidoId && e.tipo === 'UPDATE'),
      'otro repartidor no recibe los cambios de un pedido ajeno',
    ).toHaveLength(0);
  });

  it('un cliente sin sesión (anon) no recibe ningún pedido', async () => {
    const anonimo = createClient(url, anonKey, opcionesAuth);
    clientes.push(anonimo);
    // anon no tiene SELECT sobre pedidos. Realtime puede rechazar la suscripción o avisarle
    // que hubo un cambio pero SIN datos (error 401). Lo que no puede pasar es que reciba datos.
    const { eventos: eventosAnon } = await escuchar(anonimo, 'anon', true);

    const sol = await crearUsuario('sol-c');
    const enSol = await escuchar(sol.cliente, 'sol-c');

    const creado = await ok(
      sol.cliente.rpc('crear_pedido', {
        p_punto_entrega_id: puntoDentro,
        p_items: [{ producto_id: productoId, cantidad: 1 }],
      }),
    );
    const pedidoId: string = creado.pedido_id;

    expect(
      await esperarEvento(enSol.eventos, (e) => e.tipo === 'INSERT' && e.id === pedidoId),
      'el solicitante sí recibe su pedido (la suscripción funciona)',
    ).toBeDefined();
    await esperar(1500);
    const conDatos = eventosAnon.filter((e) => e.id !== '' || e.estado !== '');
    expect(conDatos, 'anon no recibe datos de ningún pedido').toHaveLength(0);
    for (const e of eventosAnon) {
      expect(e.errores.join(' '), 'si a anon le llega un aviso, viene marcado como no autorizado').toMatch(/401|Unauthorized/i);
    }
  });
});