// Prueba de integración de ejemplo (T-010) contra la base LOCAL de Supabase.
// Requiere: npx supabase start
import { execSync } from 'node:child_process';
import { createClient } from '@supabase/supabase-js';
import { describe, expect, it } from 'vitest';

// Toma URL y clave pública de las variables de entorno o, si no están, de la CLI.
function configLocal(): { url: string; key: string } {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_KEY;
  if (url && key) return { url, key };

  const salida = execSync('npx supabase status -o json', {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const estado = JSON.parse(salida.slice(salida.indexOf('{')));
  return {
    url: estado.API_URL,
    key: estado.PUBLISHABLE_KEY ?? estado.ANON_KEY,
  };
}

const { url, key } = configLocal();

// Cuando exista el trigger de dominio (T-068), usar TEST_EMAIL_DOMAIN con el dominio institucional.
const dominio = process.env.TEST_EMAIL_DOMAIN ?? 'example.com';
const correo = `test-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@${dominio}`;
const password = 'Prueba-12345!';

describe('Integración con Supabase local', () => {
  const supabase = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  it('registra un usuario de prueba y obtiene una sesión', async () => {
    const { data, error } = await supabase.auth.signUp({ email: correo, password });
    expect(error).toBeNull();
    expect(data.session).not.toBeNull();
    expect(data.user?.email).toBe(correo);
  });

  it('consulta con la sesión del usuario', async () => {
    const { data: usuario } = await supabase.auth.getUser();
    expect(usuario.user?.email).toBe(correo);

    const { data, error } = await supabase.rpc('health');
    expect(error).toBeNull();
    expect(data).toBe('ok');
  });

  it('cierra la sesión', async () => {
    const { error } = await supabase.auth.signOut();
    expect(error).toBeNull();
    const { data } = await supabase.auth.getSession();
    expect(data.session).toBeNull();
  });

  it('rechaza un correo de otro dominio', async () => {
  const otro = createClient(url, key, { auth: { persistSession: false } });
  const { error } = await otro.auth.signUp({ email: `ext-${Date.now()}@gmail.com`, password });
  expect(error).not.toBeNull();
});
});