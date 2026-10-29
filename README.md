# DeskDrop

App móvil de domicilios dentro de un campus universitario: un solicitante pide productos de un comercio y un domiciliario se los lleva. Solo pueden usarla personas con correo institucional.

Proyecto de clase (requisitos y modelos), construido como un producto real y con presupuesto $0.

## Stack

| Parte | Tecnología |
|---|---|
| App móvil | Expo (React Native + TypeScript), probada con Expo Go |
| Backend | Supabase: Postgres, Auth, Realtime, funciones SQL y `pg_cron` |
| Gestión y diseño | Jira, GitHub y Figma |

Decisiones de arquitectura:
- [ADR 001: stack Expo + Supabase](docs/adr/001-stack-expo-supabase.md)
- [ADR 002: captura de la ubicación en el campus](docs/adr/002-captura-ubicacion-campus.md)
- [ADR 003: autenticación, datos personales y cuentas](docs/adr/003-autenticacion-datos-personales.md)

## Estructura del repositorio

```
app/          App Expo: todo el código de la app vive aquí (src/app, src/components, ...)
supabase/     config.toml, migraciones (esquema), seeds y pruebas pgTAP (supabase/tests)
docs/         ADR y documentación del producto
tests/        Pruebas de integración con supabase-js (vitest)
package.json  En la raíz: solo la CLI de Supabase y las herramientas de pruebas
```

> **La app va solo en `app/`.** No subas `src/`, `assets/`, `app.json` ni `tsconfig.json` a la raíz: crean una segunda copia de la app y sobrescriben el `package.json` de la raíz (se pierden los scripts de pruebas y el CI falla).

## Requisitos

- [Node.js](https://nodejs.org) (versión LTS)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/), abierto antes de iniciar Supabase (en Windows necesita WSL2)
- [Expo Go](https://expo.dev/go) en el celular, con la misma cuenta de Expo que uses en la terminal
- Git

## Primer arranque

Todos los comandos son en PowerShell o terminal. La base local es de cada persona y se reconstruye desde las migraciones.

**1. Clonar e instalar las herramientas de la raíz:**

```bash
git clone <URL-DEL-REPOSITORIO>
cd DeskDrop
npm install
```

**2. Levantar Supabase en local** (la primera vez descarga imágenes y puede tardar varios minutos):

```bash
npx supabase start
npx supabase db reset
```

`db reset` aplica todas las migraciones de `supabase/migrations` y los seeds (`seed.sql` y `seed_catalogo.sql`). Para ver de nuevo las URLs, las claves locales y el buzón local donde llegan los correos de prueba (Mailpit):

```bash
npx supabase status
```

**3. Configurar la app.** En `app/`, copia `.env.example` a `.env` y completa los valores con los que muestra `status`. Los nombres deben coincidir con los que lee `app/src/lib/supabase.ts`:

```bash
EXPO_PUBLIC_SUPABASE_URL=
EXPO_PUBLIC_SUPABASE_KEY=
```

- Usa solo la clave pública (publishable o anon). **Nunca** pongas la clave secreta (service role) en la app ni en el repositorio.
- Desde un celular, `127.0.0.1` apunta al propio celular. Usa la IP de tu computador en la red local, por ejemplo `http://192.168.1.10:54321`. En un emulador de Android es `http://10.0.2.2:54321`.
- El celular y el computador deben estar en la misma red. Si el wifi de la universidad lo bloquea, usa un hotspot.

**4. Correr la app:**

```bash
cd app
npm install
npx expo start
```

Escanea el QR con Expo Go. Si la red no deja conectar, usa `npx expo start --tunnel` (más lento, pero funciona entre redes distintas). Si un cambio no aparece en el celular, limpia la caché con `npx expo start -c`.

**5. Entrar a la app.** En local la verificación por correo está desactivada (`enable_confirmations = false`): al registrarte con un correo `@eia.edu.co` entras directo. También puedes crear usuarios en Studio (`http://127.0.0.1:54323`) → Authentication → Add user.

## Comandos útiles

| Comando | Para qué |
|---|---|
| `npx supabase start` / `npx supabase stop` | Encender y apagar la base local |
| `npx supabase db reset` | Borrar la base local y reconstruirla desde las migraciones y seeds |
| `npx supabase migration new <nombre>` | Crear una migración nueva |
| `npx supabase migration list` | Ver qué migraciones están aplicadas en local y en staging |
| `npx supabase test db` | Correr las pruebas pgTAP de la base |
| `npx supabase status` | Ver URLs y claves locales |
| `npm test` | Correr todas las pruebas (pgTAP + integración) |
| `npm run test:integration` | Prueba de integración con supabase-js |

Desde `app/`:

| Comando | Para qué |
|---|---|
| `npx expo install <paquete>` | Instalar dependencias compatibles con el SDK (en vez de `npm install <paquete>`) |
| `npx tsc --noEmit` | Revisar los tipos de TypeScript |
| `npx expo start -c` | Arrancar limpiando la caché |

## Cómo trabajamos

- **Todo cambio del esquema va como migración** en `supabase/migrations`, nunca solo desde el panel web. Si una migración ya se integró o se aplicó en staging, no se edita: se crea otra.
- **Toda tabla nueva empieza con `revoke all`.** Supabase da por defecto todos los permisos (`ALL`) a `anon` y `authenticated` sobre cada tabla nueva de `public`, y un `grant` **suma** permisos, no los quita. El patrón es:

  ```sql
  alter table public.mi_tabla enable row level security;
  revoke all on public.mi_tabla from anon, authenticated;
  grant select on public.mi_tabla to authenticated;     -- solo lo necesario
  create policy ... on public.mi_tabla for select to authenticated using (...);
  ```

  La prueba `supabase/tests/05 permisos.test.sql` falla si alguna tabla queda con permisos de más.
- **Las funciones que cambian datos sensibles son `security definer`** con `set search_path = ''`, validan quién llama (`auth.uid()`, `mi_rol()`, `es_admin()`, `es_dueno_comercio()`) y hacen `revoke execute ... from public, anon`.
- **Errores propios con código.** Las funciones lanzan códigos de 5 caracteres que la app traduce a mensajes (ver la tabla de códigos más abajo). No se compara el texto del error.
- **Cada migración trae sus pruebas** en `supabase/tests`, con un caso permitido y uno denegado por rol.
- **Lo que todavía es simulado se marca** con un comentario `SIMULADO:` que dice qué lo reemplaza y en qué tarea.
- **Ramas y Pull Requests:** una rama por tarea, nombrada con la clave del issue de Jira (por ejemplo `CLAVE-12-login`). Se integra a `main` solo por Pull Request aprobado.
- **Secretos:** `.env` está en `.gitignore`. Claves y contraseñas se comparten por un canal privado, nunca por el repositorio.

## Autenticación

| Flujo | Cómo funciona |
|---|---|
| Registro | Nombre, correo institucional y contraseña, más la casilla de términos. La base rechaza otros dominios (trigger `validar_dominio_correo`, tabla `dominios_permitidos`) |
| Verificación | Código numérico por correo (no enlace: el enlace no abre Expo Go). Pantalla `verificar.tsx` con `verifyOtp({ type: 'email' })` |
| Login | Correo y contraseña. La sesión se guarda en el celular (AsyncStorage) y se renueva sola |
| Recuperar contraseña | Código por correo + contraseña nueva en la misma pantalla (`verifyOtp({ type: 'recovery' })` y `updateUser`). Si la contraseña falla, se reintenta sin pedir otro código |
| Contraseña | Mínimo 8 caracteres con mayúscula, minúscula y número (igual en `config.toml`, en el panel de staging y en `utils/validaciones.ts`) |

**Configuración de staging** (panel de Supabase → Authentication):
- *Confirm email* activado y *Email OTP Length* en 6 (la app acepta de 6 a 10 dígitos).
- Plantillas *Confirm signup* y *Reset Password* con `{{ .Token }}` (el código) en vez de `{{ .ConfirmationURL }}`.
- Sin SMTP propio, Supabase envía **2 correos por hora** para todo el proyecto. Para probar sin gastar correos, crea usuarios en *Add user* con *Auto Confirm User*.

## Roles y permisos

Cada perfil tiene un rol (`perfiles.rol`, enum `rol_usuario`). Todas las tablas tienen RLS.

| Rol | Puede |
|---|---|
| `solicitante` | Ver el catálogo activo, sus pedidos y su perfil; editar su nombre y teléfono |
| `repartidor` | Lo anterior, más ver los pedidos disponibles (`Creado`, sin repartidor) y los asignados a él |
| `comercio` | Administrar su comercio y sus productos (también los inactivos) y ver los pedidos de su comercio. No puede cambiar el dueño ni mover productos a otro comercio |
| `admin` | Todo lo anterior sobre todos los datos; crear comercios, zonas y puntos; asignar roles |

- El rol **solo se cambia** con `select public.asignar_rol('<id-usuario>', '<rol>')`, siendo admin. Nadie puede cambiarse su propio rol.
- **Pedidos, ítems, pagos y calificaciones son de solo lectura para la app**: se escriben con funciones `security definer` (por ejemplo `crear_pedido`).
- **El primer admin** y el dueño de un comercio se asignan desde el SQL Editor:

  ```sql
  update public.perfiles set rol = 'admin' where email = 'correo@eia.edu.co';
  update public.comercios
  set administrador_id = (select id from public.perfiles where email = 'cafeteria@eia.edu.co')
  where nombre = 'Cafetería Central Bloque 1';
  ```

**Roles en la app.** La base guarda un rol por perfil; la app lo traduce a los *modos* que puede usar (`rolesDesdeBase` en `app/src/utils/roles.ts`). El modo activo (`rolActivo` en `useAuth()`) decide qué pestañas se ven, y el repartidor puede cambiar de modo en Perfil:

| Rol en la base | Modos en la app |
|---|---|
| `solicitante` | solicitante |
| `repartidor` | solicitante y domiciliario |
| `comercio` | comercio |
| `admin` | solicitante (aún no hay pantallas de admin) |

> **Provisional:** si el equipo decide que un usuario tenga varios roles en la base (por ejemplo una tabla `perfil_roles`), solo cambian `rolesDesdeBase` y una migración nueva.

## Datos personales y cuentas

- **Términos y privacidad:** al registrarse, la versión aceptada (`VERSION_LEGAL` en `app/src/utils/legal.ts`) viaja en el `signUp` y la base la guarda en `consentimientos` con la hora del servidor. Si los textos cambian, se sube la versión y se pide aceptar la nueva (`consentimientoService.ts`).
- **No se piden** fecha de nacimiento ni documento (minimización de datos, Ley 1581).
- **Eliminar cuenta** (Perfil → *Eliminar mi cuenta*): llama a `eliminar_mi_cuenta()`. El usuario se borra de Auth y su perfil queda anonimizado ("Usuario eliminado"); los pedidos y la aceptación de términos se conservan. No se permite con un pedido en curso ni si es el único admin.
- **Limpieza automática:** `pg_cron` corre `limpiar_cuentas_sin_verificar()` todos los días a las 3:00 a. m. (hora de Colombia) y borra las cuentas sin verificar de más de 7 días que no tengan pedidos.

Detalles y razones en el [ADR 003](docs/adr/003-autenticacion-datos-personales.md).

## Estado de la conexión con Supabase

| Parte de la app | Estado |
|---|---|
| Login, registro, verificación, recuperación, eliminar cuenta | Real |
| Catálogo (comercios y productos) | Real (`catalogService.ts`) |
| Lugares de entrega | Real (`listarPuntosEntrega` en `checkoutService.ts`) |
| Crear pedido | Simulado hasta `crear_pedido` (T-023) |
| Bandeja del comercio y entregas | Simulado (`pedidosService.ts`, `mocks/pedidos.ts`) |

## Códigos de error propios

| Código | Significa | Lo lanza |
|---|---|---|
| `42501` | Sin permiso (estándar de Postgres) | RLS, `grant` faltante, `asignar_rol`, `proteger_dueno_comercio` |
| `DD001` | Tiene un pedido en curso | `eliminar_mi_cuenta()` |
| `DD002` | Es el único administrador | `eliminar_mi_cuenta()` |

## Pruebas

```bash
npx supabase db reset
npx supabase test db
```

| Archivo | Qué prueba |
|---|---|
| `00 health` | La función `health()` |
| `01 rls activo` | Todas las tablas de `public` tienen RLS |
| `02 registro` | Dominio institucional y perfil automático |
| `03 roles` | Qué puede ver y hacer cada rol (24 casos) |
| `04 consentimiento` | Aceptación de términos |
| `05 permisos` | Ninguna tabla queda con permisos de más |
| `06 eliminar cuenta` | Anonimización y limpieza de cuentas |

El CI (`.github/workflows/db-tests.yml`) corre las mismas pruebas en cada Pull Request.

## Staging (proyecto en la nube)

Lo despliega solo quien tenga acceso y, más adelante, el CI. Los demás desarrollan en local.

```bash
npx supabase login
npx supabase link --project-ref <PROJECT-REF>
npx supabase migration list
npx supabase db push
```

El `project ref` es la parte inicial de la URL del proyecto (`https://<PROJECT-REF>.supabase.co`). `link` pide la contraseña de la base de datos. Los seeds **no** se aplican con `db push`: el catálogo de staging se carga una vez pegando `supabase/seed_catalogo.sql` en el SQL Editor.

## Límites del plan gratuito

- Solo **2 proyectos activos** en Supabase.
- El proyecto se **pausa tras una semana sin uso**: revisa que esté activo antes de cada demo.
- Correos de Auth: **2 por hora** con el correo de Supabase; con SMTP propio se puede subir (30 por hora por defecto).
- Un mismo usuario debe esperar **60 segundos** entre envíos de códigos (la app muestra la cuenta regresiva).
- Más detalles en el [ADR 001](docs/adr/001-stack-expo-supabase.md).

## Problemas frecuentes

| Síntoma | Qué revisar |
|---|---|
| `supabase start` falla | Docker Desktop abierto y WSL2 activo |
| La app no conecta a la base | Que la URL use la IP del computador y no `127.0.0.1`, y que ambos estén en la misma red |
| `permission denied` (`42501`) al llamar una función o tabla | Falta el `grant` o la política en la migración, o el usuario no tiene el rol |
| Un cambio del código no se ve en el celular | `npx expo start -c` para limpiar la caché |
| `Unable to resolve module` al abrir la app | Un archivo importa otro que no se subió o tiene el nombre mal escrito |
| El código de verificación no se puede escribir completo | *Email OTP Length* del panel distinto al esperado; la app acepta de 6 a 10 dígitos |
| No llegan los correos | Límite de 2 por hora sin SMTP propio; revisar spam y Authentication → Logs |
| Registrar un correo externo da un error genérico | Es lo esperado: el trigger de dominio lo rechaza |
| `git pull` abre un editor raro (Vim) | `Esc`, escribir `:wq` y `Enter`. Para cambiarlo: `git config --global core.editor "notepad"` |
| Una ruta nueva sale en rojo en VS Code | `npx expo start` regenera los tipos de rutas; luego *TypeScript: Restart TS Server* |
| Expo Go no abre el proyecto | La misma cuenta de Expo en la terminal y en la app, y la versión del SDK compatible con Expo Go |