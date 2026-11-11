// T-107. Crea (o actualiza) las cuentas de prueba del piloto en un proyecto de Supabase:
//   demo.solicitante / demo.domiciliario (con la declaración +18 ya aceptada) / demo.comercio / demo.admin
// Es idempotente: si la cuenta ya existe, solo le restablece la contraseña y los datos.
//
// Uso (PowerShell, desde la raíz del repositorio):
//   $env:SUPABASE_URL="https://<ref>.supabase.co"
//   $env:SUPABASE_SERVICE_ROLE_KEY="<clave service_role de STAGING>"
//   $env:PASSWORD_PRUEBA="<contraseña temporal>"      # opcional; si falta se genera una y se imprime
//   node supabase/crear_usuarios_prueba.mjs
//
// La clave service_role da acceso total: úsala solo contra staging y nunca la guardes en el repositorio.
import { randomBytes } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const clave = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !clave) {
  console.error('Faltan SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}
const dominio = process.env.DOMINIO_PRUEBA ?? 'eia.edu.co'; // debe estar en dominios_permitidos
const password = process.env.PASSWORD_PRUEBA ?? `Demo-${randomBytes(6).toString('hex')}9aA`;
const VERSION_CONDICIONES = '0.1-borrador'; // igual a VERSION_CONDICIONES_REPARTIDOR en app/src/utils/legal.ts
const COMERCIO = process.env.COMERCIO_PRUEBA ?? 'Cafetería Central Bloque 1';

const admin = createClient(url, clave, { auth: { persistSession: false, autoRefreshToken: false } });

const cuentas = [
  { alias: 'solicitante', nombre: 'Demo Solicitante', rol: 'solicitante' },
  { alias: 'domiciliario', nombre: 'Demo Domiciliario', rol: 'solicitante', repartidor: true },
  { alias: 'comercio', nombre: 'Demo Comercio', rol: 'comercio', comercio: COMERCIO },
  { alias: 'admin', nombre: 'Demo Admin', rol: 'admin' },
];

async function buscarUsuario(email) {
  for (let pagina = 1; pagina <= 20; pagina++) {
    const { data, error } = await admin.auth.admin.listUsers({ page: pagina, perPage: 200 });
    if (error) throw error;
    const hallado = data.users.find((u) => u.email?.toLowerCase() === email);
    if (hallado) return hallado;
    if (data.users.length < 200) return null;
  }
  return null;
}

async function asegurarUsuario(email, nombre) {
  const existente = await buscarUsuario(email);
  if (existente) {
    const { error } = await admin.auth.admin.updateUserById(existente.id, { password, email_confirm: true });
    if (error) throw error;
    return existente.id;
  }
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { nombre_completo: nombre },
  });
  if (error) throw error;
  return data.user.id;
}

const filas = [];
for (const c of cuentas) {
  const email = `demo.${c.alias}@${dominio}`;
  const id = await asegurarUsuario(email, c.nombre);

  const { error: ePerfil } = await admin
    .from('perfiles')
    .upsert({ id, email, nombre_completo: c.nombre, rol: c.rol }, { onConflict: 'id' });
  if (ePerfil) throw new Error(`perfil ${email}: ${ePerfil.message}`);

  if (c.repartidor) {
    const { error } = await admin
      .from('aceptaciones_repartidor')
      .upsert({ usuario_id: id, version: VERSION_CONDICIONES }, { onConflict: 'usuario_id,version', ignoreDuplicates: true });
    if (error) throw new Error(`aceptación ${email}: ${error.message}`);
  }

  if (c.comercio) {
    const { data: previo, error: eBusca } = await admin.from('comercios').select('id').eq('nombre', c.comercio).limit(1);
    if (eBusca) throw new Error(`comercio: ${eBusca.message}`);
    if (previo?.length) {
      const { error } = await admin.from('comercios').update({ administrador_id: id, activo: true }).eq('id', previo[0].id);
      if (error) throw new Error(`comercio: ${error.message}`);
    } else {
      const { error } = await admin.from('comercios').insert({ nombre: c.comercio, administrador_id: id, activo: true });
      if (error) throw new Error(`comercio: ${error.message}`);
    }
  }
  filas.push({ correo: email, rol: c.repartidor ? 'solicitante + repartidor habilitado' : c.rol });
}

console.table(filas);
console.log(`Contraseña de las cuentas: ${password}`);
console.log('Verifica: comercio con "Recibiendo pedidos" activo y productos con inventario (supabase/seed_catalogo.sql).');
