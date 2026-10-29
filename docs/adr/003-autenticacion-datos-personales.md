# ADR 003: Autenticación, datos personales y ciclo de vida de las cuentas

- **Estado:** Aceptado
- **Fecha:** 2026-10-29
- **Responsable:** Muñoz
- **Tareas:** T-068, T-069, T-070, T-072, T-074, T-075, T-076

## Contexto

DeskDrop maneja cuentas de miembros de la comunidad universitaria y sus datos personales, así que le aplica la Ley 1581 de 2012 (protección de datos personales). Algunos estudiantes de primer semestre son menores de edad. La app se prueba con Expo Go y el presupuesto es $0.

## Decisiones

### 1. Verificación y recuperación con código, no con enlace

El enlace de los correos de Supabase apunta a la *Site URL* y no abre la app dentro de Expo Go. Se usa un código numérico (`{{ .Token }}` en las plantillas) que el usuario escribe en la app (`verifyOtp`).

- La app acepta de 6 a 10 dígitos para no depender de la configuración exacta del panel.
- En la recuperación, si la contraseña nueva es rechazada después de validar el código, se conserva la sesión temporal para reintentar, porque Supabase gasta el código al validarlo.

### 2. No se piden fecha de nacimiento ni documento

Ningún flujo los necesita (principio de finalidad y necesidad de la Ley 1581). Además, conocer la edad de un menor obligaría a aplicar el régimen especial de datos de niños, niñas y adolescentes (art. 7). El registro pide solo nombre, correo institucional y contraseña.

- Pendiente: si se exige mayoría de edad para ser domiciliario (la Ley 1098 de 2006 pide autorización del inspector de trabajo entre los 15 y 17 años), se hará con una declaración al activar ese rol, no guardando la fecha de nacimiento.

### 3. La aceptación de términos se guarda en la base, con historial

Tabla `consentimientos` con una fila por versión aceptada (`usuario_id`, `version`, `aceptado_en`).

- La versión viaja en el `signUp` y el trigger `crear_perfil` la guarda en la misma transacción que crea el perfil: no puede existir una cuenta sin su aceptación ni al revés.
- La fecha la pone el servidor (`default now()`) y la app solo puede escribir la columna `version`: no se puede falsificar la fecha ni aceptar a nombre de otro.
- No hay `update` ni `delete`: una prueba de consentimiento no se edita.

### 4. Un rol por perfil, controlado por la base

`perfiles.rol` (enum `rol_usuario`: solicitante, repartidor, comercio, admin) y políticas RLS en todas las tablas.

- Funciones `security definer` (`mi_rol`, `es_admin`, `es_dueno_comercio`) para que las políticas consulten el rol sin pasar por la RLS de `perfiles`.
- El rol solo se cambia con `asignar_rol`, siendo admin, y nunca el propio.
- Pedidos, ítems, pagos y calificaciones son de solo lectura para la app; se escriben con funciones `security definer` que validan quién llama.
- Toda tabla empieza con `revoke all` porque Supabase da `ALL` por defecto a `anon` y `authenticated`. Este hueco se encontró con las pruebas pgTAP (un usuario podía cambiarse el rol) y se corrigió en `perfiles_permisos`.
- La app usa *modos* (solicitante, domiciliario, comercio) con un modo activo. Se derivan del rol de la base con `rolesDesdeBase` (`app/src/utils/roles.ts`): un repartidor puede usar la app como solicitante o como domiciliario. Es provisional: si se decide guardar varios roles por usuario (tabla `perfil_roles`), cambian esa función y una migración, no las pantallas.

### 5. Eliminar la cuenta anonimiza el perfil en vez de borrarlo

Los pedidos y calificaciones apuntan al perfil, y el historial del comercio los necesita.

- Se borra el usuario de `auth.users` (ya no puede entrar) y un trigger deja el perfil como "Usuario eliminado", sin correo ni teléfono y con rol solicitante.
- El trigger actúa sin importar quién borre al usuario (la app, el panel o el job).
- La aceptación de términos se conserva como prueba.
- No se permite con un pedido en curso (`DD001`) ni si es el único admin (`DD002`).

### 6. Función SQL en vez de Edge Function para eliminar la cuenta

Una función `security definer` puede borrar el usuario de `auth.users` sin exponer la clave secreta (service role). Evita desplegar y mantener código en Deno y se prueba con pgTAP igual que el resto. Si se necesitara una Edge Function, sería una envoltura delgada de `eliminar_mi_cuenta()`.

### 7. Limpieza automática de cuentas abandonadas

`pg_cron` ejecuta `limpiar_cuentas_sin_verificar()` todos los días a las 08:00 UTC (3:00 a. m. en Colombia). Borra por completo las cuentas que nunca verificaron el correo, tienen más de 7 días y no tienen pedidos: nunca llegaron a usarse.

## Consecuencias

- Las reglas de seguridad viven en la base y están cubiertas por pruebas pgTAP (`supabase/tests` 02 a 06) que corren en el CI.
- Toda migración nueva debe seguir el patrón `revoke all` → `grant` mínimo → políticas, o la prueba `05 permisos` falla.
- Sin SMTP propio, Supabase envía solo 2 correos por hora: suficiente para el prototipo, no para un piloto real.
- `perfiles` ya no tiene llave foránea hacia `auth.users`: un perfil puede existir sin usuario (cuentas eliminadas, marcadas con `eliminado_en`).