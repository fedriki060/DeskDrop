# DeskDrop

App móvil de domicilios dentro de un campus universitario: un solicitante pide productos de un comercio y un domiciliario se los lleva. Solo pueden usarla personas con correo institucional.

Proyecto de clase (requisitos y modelos), construido como un producto real y con presupuesto $0.

## Stack

| Parte | Tecnología |
|---|---|
| App móvil | Expo (React Native + TypeScript), probada con Expo Go |
| Backend | Supabase: Postgres, Auth, Realtime, funciones SQL, `pg_cron` y Edge Functions |
| Gestión y diseño | Jira, GitHub y Figma |

La decisión y sus alternativas están en [docs/adr/0001-stack-expo-supabase.md](docs/adr/0001-stack-expo-supabase.md).

## Estructura del repositorio

```
app/        App Expo (pantallas, navegación, cliente supabase-js)
supabase/   Configuración local, migraciones (esquema) y seed
docs/       ADR y documentación
package.json  Solo fija la versión de la CLI de Supabase
```

## Requisitos

- [Node.js](https://nodejs.org) (versión LTS)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/), abierto antes de iniciar Supabase (en Windows necesita WSL2)
- [Expo Go](https://expo.dev/go) en el celular, con la misma cuenta de Expo que uses en la terminal
- Git

## Primer arranque

Todos los comandos son en PowerShell o terminal. La base local es de cada persona y se reconstruye desde las migraciones.

**1. Clonar e instalar la CLI de Supabase** (desde la raíz del repositorio):

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

`db reset` aplica todas las migraciones de `supabase/migrations` y el seed. Para ver de nuevo las URLs y claves locales, y la dirección del buzón local donde llegan los correos de prueba:

```bash
npx supabase status
```

**3. Configurar la app.** En `app/`, copia `.env.example` a `.env` y completa los valores con los que muestra `status`:

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

Escanea el QR con Expo Go. Si la red no deja conectar, usa `npx expo start --tunnel` (más lento, pero funciona entre redes distintas).

**5. Comprobar que todo conecta.** La app llama a la función `health()` de la base y muestra `ok`.

## Comandos útiles

| Comando | Para qué |
|---|---|
| `npx supabase start` / `npx supabase stop` | Encender y apagar la base local |
| `npx supabase db reset` | Borrar la base local y reconstruirla desde las migraciones |
| `npx supabase migration new <nombre>` | Crear una migración nueva |
| `npx supabase test db` | Correr las pruebas pgTAP de la base |
| `npx supabase status` | Ver URLs y claves locales |
| `npm test` | Correr todas las pruebas
| `npm run test:integration` | Prueba integracion con Supabase

## Cómo trabajamos

- **Todo cambio del esquema va como migración** en `supabase/migrations`, nunca solo desde el panel web. Si una migración ya se integró, no se edita: se crea otra.
- **Toda tabla y función nueva declara sus permisos.** En el proyecto en la nube la exposición automática de tablas está desactivada, así que cada migración debe incluir su RLS y sus `grant` o `revoke` explícitos.
- **Ramas y Pull Requests:** una rama por tarea, nombrada con la clave del issue de Jira (por ejemplo `CLAVE-12-login`). Se integra a `main` solo por Pull Request aprobado.
- **Secretos:** `.env` está en `.gitignore`. Claves y contraseñas se comparten por un canal privado, nunca por el repositorio.

## Staging (proyecto en la nube)

Lo despliega solo quien tenga acceso y, más adelante, el CI. Los demás desarrollan en local.

```bash
npx supabase login
npx supabase link --project-ref <PROJECT-REF>
npx supabase db push
```

El `project ref` es la parte inicial de la URL del proyecto (`https://<PROJECT-REF>.supabase.co`). `link` pide la contraseña de la base de datos.

## Límites del plan gratuito

- Solo **2 proyectos activos** en Supabase.
- El proyecto se **pausa tras una semana sin uso**: revisa que esté activo antes de cada demo.
- Con SMTP propio, el límite de correos de verificación es de **30 por hora**.
- Más detalles en el [ADR 0001](docs/adr/0001-stack-expo-supabase.md).

## Problemas frecuentes

| Síntoma | Qué revisar |
|---|---|
| `supabase start` falla | Docker Desktop abierto y WSL2 activo |
| La app no conecta a la base | Que la URL use la IP del computador y no `127.0.0.1`, y que ambos estén en la misma red |
| `permission denied` al llamar una función o tabla | Falta el `grant` en la migración |
| Registrar un correo externo da un error genérico de base de datos | Es lo esperado: el trigger de dominio lo rechaza |
| Expo Go no abre el proyecto | La misma cuenta de Expo en la terminal y en la app, y la versión del SDK compatible con Expo Go |