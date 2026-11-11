// Edge Function `retener-pago` (tarea 2): aprueba un pago digital y retiene los fondos
// (estado `en_custodia`) llamando a public.retener_pago(), que solo ejecuta service_role.
//
// Quién la puede llamar (se valida aquí, por eso verify_jwt = false en config.toml):
//   1. El webhook de la pasarela, con el header  x-webhook-secret: <PAGOS_WEBHOOK_SECRET>
//   2. Un administrador, con su sesión:          Authorization: Bearer <access_token>
//
// POST { "pedido_id": "<uuid>", "referencia": "<id de la transacción, opcional>" }
//   200 { ok: true, ya_procesado: false, ...resultado }   pago retenido
//   200 { ok: true, ya_procesado: true }                  reintento del webhook (idempotente)
//   400 JSON o pedido_id inválido · 401 sin credenciales · 403 no es admin
//   404 pedido sin pago · 409 el pago no se puede retener · 500 error interno

import { createClient } from 'npm:@supabase/supabase-js@2';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Código con el que empieza el mensaje de la base -> estado HTTP
const ESTADOS: Record<string, number> = {
  PEDIDO_NO_ENCONTRADO: 404,
  PAGO_NO_ENCONTRADO: 404,
  PAGO_NO_ES_DIGITAL: 409,
  PAGO_YA_COBRADO: 409,
  PAGO_NO_COBRABLE: 409,
  ESTADO_NO_PERMITIDO: 409,
};

function responder(cuerpo: Record<string, unknown>, estado = 200) {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { 'Content-Type': 'application/json' },
  });
}

// Comparación en tiempo constante para no filtrar el secreto por tiempos de respuesta
function iguales(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  for (let i = 0; i < Math.max(ea.length, eb.length); i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return responder({ ok: false, error: 'METODO_NO_PERMITIDO' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const claveServicio = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const secretoWebhook = Deno.env.get('PAGOS_WEBHOOK_SECRET') ?? '';
  if (!url || !claveServicio) return responder({ ok: false, error: 'CONFIGURACION_INCOMPLETA' }, 500);

  // El cliente con service_role se queda aquí: nunca se devuelve ni se registra.
  const admin = createClient(url, claveServicio, { auth: { persistSession: false } });

  // ---- Quién llama ------------------------------------------------------------------
  let actor: string | null = null;
  const secretoRecibido = req.headers.get('x-webhook-secret');
  const autorizacion = req.headers.get('Authorization') ?? '';

  if (secretoRecibido !== null) {
    // Sin secreto configurado el camino del webhook queda cerrado (falla cerrado).
    if (secretoWebhook === '' || !iguales(secretoRecibido, secretoWebhook)) {
      return responder({ ok: false, error: 'NO_AUTORIZADO' }, 401);
    }
  } else if (autorizacion.startsWith('Bearer ')) {
    const token = autorizacion.slice('Bearer '.length);
    const { data: usuario, error: errorUsuario } = await admin.auth.getUser(token);
    if (errorUsuario || !usuario.user) return responder({ ok: false, error: 'NO_AUTORIZADO' }, 401);

    const { data: perfil } = await admin
      .from('perfiles')
      .select('rol')
      .eq('id', usuario.user.id)
      .maybeSingle();
    if (perfil?.rol !== 'admin') return responder({ ok: false, error: 'ROL_NO_PERMITIDO' }, 403);
    actor = usuario.user.id;
  } else {
    return responder({ ok: false, error: 'NO_AUTORIZADO' }, 401);
  }

  // ---- Entrada ------------------------------------------------------------------------
  let cuerpo: { pedido_id?: unknown; referencia?: unknown };
  try {
    cuerpo = await req.json();
  } catch {
    return responder({ ok: false, error: 'JSON_INVALIDO' }, 400);
  }

  if (typeof cuerpo.pedido_id !== 'string' || !UUID.test(cuerpo.pedido_id)) {
    return responder({ ok: false, error: 'PEDIDO_ID_INVALIDO' }, 400);
  }
  const referencia =
    typeof cuerpo.referencia === 'string' ? cuerpo.referencia.trim().slice(0, 120) : null;

  // ---- Retener los fondos -----------------------------------------------------------
  const { data, error } = await admin.rpc('retener_pago', {
    p_pedido_id: cuerpo.pedido_id,
    p_referencia: referencia || null,
    p_actor: actor,
  });

  if (error) {
    const codigo = error.message.split(':')[0].trim();
    // La pasarela reintenta los webhooks: un pago ya retenido no es un error.
    if (codigo === 'PAGO_YA_RETENIDO') return responder({ ok: true, ya_procesado: true });
    const estado = ESTADOS[codigo];
    if (estado) return responder({ ok: false, error: codigo }, estado);
    console.error('[retener-pago]', error.code, error.message);
    return responder({ ok: false, error: 'ERROR_INTERNO' }, 500);
  }

  return responder({ ok: true, ya_procesado: false, ...data });
});
