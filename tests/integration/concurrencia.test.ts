// Pruebas de concurrencia y reglas RN-001 / RN-002 de crear_pedido contra la base LOCAL de Supabase.
// Requiere: npx supabase start (y `npx supabase db reset` para tener la migración de cobertura).
//
// pgTAP corre en una sola transacción, así que no puede simular dos sesiones a la vez.
// Aquí cada solicitante usa su propio cliente (su propia conexión HTTP -> su propia
// transacción en Postgres) y las llamadas se lanzan con Promise.all.
import { execSync } from 'node:child_process';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
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
// Cliente con service_role: solo para preparar y limpiar datos (nunca en la app).
const admin = createClient(url, serviceKey, opcionesAuth);

// ---------------------------------------------------------------------------
// Utilidades de preparación
// ---------------------------------------------------------------------------
const usuariosCreados: string[] = [];
const comerciosCreados: string[] = [];
const zonasCreadas: string[] = [];

async function ok<T>(promesa: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await promesa;
  if (error) throw new Error(error.message);
  return data;
}

/** Crea un usuario con perfil y devuelve un cliente con su sesión iniciada. */
async function crearUsuario(
  etiqueta: string,
  rol: 'solicitante' | 'comercio' = 'solicitante',
): Promise<{ id: string; cliente: SupabaseClient }> {
  const email = `conc-${corrida}-${etiqueta}@${dominio}`;
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
  const { error: errLogin } = await cliente.auth.signInWithPassword({ email, password });
  if (errLogin) throw new Error(`login ${etiqueta}: ${errLogin.message}`);
  return { id, cliente };
}

async function crearProducto(comercioId: string, nombre: string, inventario: number): Promise<string> {
  const fila = await ok(
    admin
      .from('productos')
      .insert({ comercio_id: comercioId, nombre, precio: 5000, inventario_disponible: inventario })
      .select('id')
      .single(),
  );
  return fila.id;
}

async function inventarioDe(productoId: string): Promise<number> {
  const fila = await ok(
    admin.from('productos').select('inventario_disponible').eq('id', productoId).single(),
  );
  return fila.inventario_disponible;
}

async function pedidosDeProducto(productoId: string): Promise<number> {
  const { count, error } = await admin
    .from('items_pedido')
    .select('id', { count: 'exact', head: true })
    .eq('producto_id', productoId);
  if (error) throw new Error(error.message);
  return count ?? 0;
}

const linea = (productoId: string, cantidad = 1) => [{ producto_id: productoId, cantidad }];

// ---------------------------------------------------------------------------
// Escenario común: un comercio y dos puntos de entrega (uno dentro y otro fuera del campus)
// ---------------------------------------------------------------------------
let comercioId: string;
let puntoDentro: string;
let puntoFuera: string;

beforeAll(async () => {
  const dueno = await crearUsuario('comercio', 'comercio');
  const comercio = await ok(
    admin
      .from('comercios')
      .insert({ administrador_id: dueno.id, nombre: `Comercio conc ${corrida}`, activo: true })
      .select('id')
      .single(),
  );
  comercioId = comercio.id;
  comerciosCreados.push(comercioId);

  const zona = await ok(
    admin.from('zonas_campus').insert({ nombre: `Zona conc ${corrida}`, activo: true }).select('id').single(),
  );
  zonasCreadas.push(zona.id);

  // Dentro del polígono oficial (docs/zonas_campus_piloto.md) y lejos de él.
  const dentro = await ok(
    admin
      .from('puntos_entrega')
      .insert({ zona_id: zona.id, nombre: 'Dentro', latitud: 6.1667, longitud: -75.5667, activo: true })
      .select('id')
      .single(),
  );
  const fuera = await ok(
    admin
      .from('puntos_entrega')
      .insert({ zona_id: zona.id, nombre: 'Fuera', latitud: 6.2001, longitud: -75.5781, activo: true })
      .select('id')
      .single(),
  );
  puntoDentro = dentro.id;
  puntoFuera = fuera.id;
});

afterAll(async () => {
  // Orden por llaves foráneas: pedidos (e ítems por cascada) -> productos -> comercios -> puntos/zonas -> usuarios.
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
// Concurrencia sobre el inventario
// ---------------------------------------------------------------------------
describe('Concurrencia: pedidos simultáneos por el mismo inventario', () => {
  it('dos pedidos simultáneos por la última unidad: uno gana y el otro recibe CARRITO_INVALIDO', async () => {
    const producto = await crearProducto(comercioId, 'Última unidad', 1);
    const [a, b] = await Promise.all([crearUsuario('ultima-a'), crearUsuario('ultima-b')]);

    const [ra, rb] = await Promise.all([
      a.cliente.rpc('crear_pedido', { p_punto_entrega_id: puntoDentro, p_items: linea(producto) }),
      b.cliente.rpc('crear_pedido', { p_punto_entrega_id: puntoDentro, p_items: linea(producto) }),
    ]);

    const resultados = [ra, rb];
    const exitosos = resultados.filter((r) => r.error === null);
    const fallidos = resultados.filter((r) => r.error !== null);

    expect(exitosos).toHaveLength(1);
    expect(fallidos).toHaveLength(1);
    expect(fallidos[0].error?.message).toMatch(/^CARRITO_INVALIDO/);
    expect(fallidos[0].error?.details).toContain('INVENTARIO_INSUFICIENTE');

    expect(await inventarioDe(producto)).toBe(0); // nunca negativo
    expect(await pedidosDeProducto(producto)).toBe(1); // un solo pedido con esa unidad
  });

  it('seis pedidos simultáneos por 2 unidades: exactamente 2 ganan', async () => {
    const producto = await crearProducto(comercioId, 'Dos unidades', 2);
    const usuarios = await Promise.all(
      Array.from({ length: 6 }, (_, i) => crearUsuario(`carrera-${i}`)),
    );

    const resultados = await Promise.all(
      usuarios.map((u) =>
        u.cliente.rpc('crear_pedido', { p_punto_entrega_id: puntoDentro, p_items: linea(producto) }),
      ),
    );

    const exitosos = resultados.filter((r) => r.error === null);
    const fallidos = resultados.filter((r) => r.error !== null);

    expect(exitosos).toHaveLength(2);
    expect(fallidos).toHaveLength(4);
    for (const f of fallidos) expect(f.error?.message).toMatch(/^CARRITO_INVALIDO/);

    expect(await inventarioDe(producto)).toBe(0);
    expect(await pedidosDeProducto(producto)).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// RN-001: un solo pedido activo por usuario, también con solicitudes simultáneas
// ---------------------------------------------------------------------------
describe('RN-001: un pedido activo por usuario', () => {
  it('dos solicitudes simultáneas del mismo usuario: una crea el pedido y la otra recibe PEDIDO_ACTIVO_EXISTENTE', async () => {
    const producto = await crearProducto(comercioId, 'Stock amplio', 10);
    const usuario = await crearUsuario('mismo-usuario');

    const [r1, r2] = await Promise.all([
      usuario.cliente.rpc('crear_pedido', { p_punto_entrega_id: puntoDentro, p_items: linea(producto) }),
      usuario.cliente.rpc('crear_pedido', { p_punto_entrega_id: puntoDentro, p_items: linea(producto) }),
    ]);

    const exitosos = [r1, r2].filter((r) => r.error === null);
    const fallidos = [r1, r2].filter((r) => r.error !== null);

    expect(exitosos).toHaveLength(1);
    expect(fallidos).toHaveLength(1);
    expect(fallidos[0].error?.message).toMatch(/^PEDIDO_ACTIVO_EXISTENTE/);
    expect(fallidos[0].error?.code).toBe('23505');

    const { count } = await admin
      .from('pedidos')
      .select('id', { count: 'exact', head: true })
      .eq('solicitante_id', usuario.id)
      .in('estado', ['Creado', 'Asignado', 'En Camino']);
    expect(count).toBe(1);

    // El intento perdedor se revirtió completo: solo se descontó la unidad del ganador.
    expect(await inventarioDe(producto)).toBe(9);
    expect(await pedidosDeProducto(producto)).toBe(1);
  });

  it('con un pedido activo, un nuevo intento secuencial también se rechaza', async () => {
    const producto = await crearProducto(comercioId, 'Secuencial', 10);
    const usuario = await crearUsuario('secuencial');

    const primero = await usuario.cliente.rpc('crear_pedido', {
      p_punto_entrega_id: puntoDentro,
      p_items: linea(producto),
    });
    expect(primero.error).toBeNull();

    const segundo = await usuario.cliente.rpc('crear_pedido', {
      p_punto_entrega_id: puntoDentro,
      p_items: linea(producto),
    });
    expect(segundo.error?.message).toMatch(/^PEDIDO_ACTIVO_EXISTENTE/);
    expect(await inventarioDe(producto)).toBe(9);
  });

  it('al cancelar el pedido activo, el usuario puede crear otro', async () => {
    const producto = await crearProducto(comercioId, 'Tras cancelar', 10);
    const usuario = await crearUsuario('cancela');

    const primero = await usuario.cliente.rpc('crear_pedido', {
      p_punto_entrega_id: puntoDentro,
      p_items: linea(producto),
    });
    expect(primero.error).toBeNull();

    await ok(
      admin
        .from('pedidos')
        .update({ estado: 'Cancelado' })
        .eq('id', (primero.data as { pedido_id: string }).pedido_id)
        .select(),
    );

    const segundo = await usuario.cliente.rpc('crear_pedido', {
      p_punto_entrega_id: puntoDentro,
      p_items: linea(producto),
    });
    expect(segundo.error).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// RN-002: cobertura del campus
// ---------------------------------------------------------------------------
describe('RN-002: cobertura del campus', () => {
  it('un punto fuera del polígono se rechaza con FUERA_DE_COBERTURA y no toca el inventario', async () => {
    const producto = await crearProducto(comercioId, 'Cobertura', 5);
    const usuario = await crearUsuario('fuera');

    const { data, error } = await usuario.cliente.rpc('crear_pedido', {
      p_punto_entrega_id: puntoFuera,
      p_items: linea(producto),
    });

    expect(data).toBeNull();
    expect(error?.message).toMatch(/^FUERA_DE_COBERTURA/);
    expect(await inventarioDe(producto)).toBe(5);
    expect(await pedidosDeProducto(producto)).toBe(0);
  });

  it('un punto dentro del polígono crea el pedido', async () => {
    const producto = await crearProducto(comercioId, 'Cobertura ok', 5);
    const usuario = await crearUsuario('dentro');

    const { data, error } = await usuario.cliente.rpc('crear_pedido', {
      p_punto_entrega_id: puntoDentro,
      p_items: linea(producto),
    });

    expect(error).toBeNull();
    expect((data as { estado: string }).estado).toBe('Creado');
    expect(await inventarioDe(producto)).toBe(4);
  });
});
