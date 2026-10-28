# ADR 0001: Stack tecnológico (Expo + Supabase)

- **Estado:** Aceptada. Las pruebas de la app del spike siguen pendientes (ver Verificación).
- **Fecha:** 2026-10-27
- **Responsable:** Muñoz
- **Tareas relacionadas:** T-001 (spike), T-008

## Contexto

DeskDrop es una app móvil de domicilios dentro de un campus: un solicitante pide productos de un comercio y un domiciliario se los lleva. Todos los usuarios (solicitante, domiciliario, comercio, administrador) deben ser personas confirmadas de la institución.

Es un proyecto de clase con presupuesto $0, pero debe construirse y demostrarse como un producto real. Los requisitos que más condicionan la tecnología son:

- Registro solo con correo institucional (HU-16) y permisos por rol (HU-17).
- Un solo pedido activo por usuario (RN-001), también con solicitudes simultáneas.
- Estado del pedido en vivo, en menos de 2 s (RNF-005).
- Cancelación automática de pedidos sin domiciliario (RN-003).
- Modelo de datos relacional (T-006).
- Equipo de 4 personas con experiencia mixta.

## Decisión

- **App móvil:** Expo (React Native + TypeScript). La demo se hace con Expo Go.
- **Backend:** Supabase, que aporta Postgres, Auth, Realtime, Data API, funciones SQL (RPC), `pg_cron` y Edge Functions cuando haga falta código de servidor.
- **Herramientas de apoyo:** GitHub (repositorio y CI), Jira (gestión) y Figma (wireframes).
- **Esquema como código:** toda tabla, función y política vive en `supabase/migrations`, gestionada con la CLI de Supabase. No se cambia el esquema solo desde el panel web.
- **Reglas críticas dentro de la base:** funciones SQL transaccionales, índices únicos parciales y RLS, para que se cumplan aunque alguien manipule la app.

## Alternativas consideradas

| Opción | Por qué no se eligió |
|---|---|
| **B. Expo + API propia (Node/TypeScript) + Postgres en Supabase** | Obliga a programar autenticación, roles y tiempo real. El hosting gratuito de la API se duerme tras 15 minutos sin tráfico y tarda cerca de un minuto en despertar. Es el plan B si fallan las pruebas críticas. |
| **C. Expo + Firebase** | Las Cloud Functions exigen el plan Blaze (tarjeta), así que a $0 no hay lógica de servidor ni jobs programados. Además, su modelo NoSQL encaja mal con el ER relacional. |
| PWA / web | Se pidió una aplicación móvil. |
| Flutter | Obliga a aprender Dart, con poco tiempo. |
| Nativo (Kotlin y Swift) | Dos bases de código para un equipo de 4. |

## Consecuencias

**Positivas**
- Autenticación, tiempo real, base relacional y tareas programadas quedan cubiertos a $0.
- Una sola base de código móvil para los cuatro roles y para Android e iOS.
- La seguridad se aplica en la base y no depende de la app.
- Menos código que mantener: casi todo T-068 a T-070 lo cubre Supabase Auth.

**Negativas y cómo se mitigan**

| Riesgo | Mitigación |
|---|---|
| El proyecto se pausa tras una semana sin uso | Usarlo cada semana o programar un ping; comprobar que esté activo antes de cada demo. |
| Solo 2 proyectos activos | Uno para staging/demo; el desarrollo se hace en local con la CLI. |
| RLS y `grant` son difíciles y un error deja datos abiertos | Plantilla de migración con `revoke` y `grant` explícitos, pruebas pgTAP de acceso denegado (T-074) y revisión en cada Pull Request. |
| La lógica crítica está en SQL, no en TypeScript | Pruebas pgTAP de cada función y revisión cruzada de migraciones. |
| Con SMTP propio el límite es de 30 correos por hora | Suficiente para el piloto; es ajustable en el panel. |
| Expo Go solo soporta las librerías que incluye | Si hace falta código nativo propio, pasar a una development build con EAS. |
| La demo depende de la red y del portátil | Usar `expo start --tunnel` y generar un APK de Android como respaldo. |
| Los planes gratuitos pueden cambiar | Revisarlos antes de la entrega final. |

## Límites del plan gratuito (octubre 2026)

Cifras tomadas de las páginas de precios en esa fecha; verificarlas antes de depender de ellas.

- **Supabase:** 500 MB de base de datos, 50.000 usuarios activos al mes, 2 proyectos activos y pausa por inactividad de una semana. Realtime incluye 2 millones de mensajes al mes.
- **Correo:** con SMTP propio activado, Supabase sube el límite a 30 correos por hora.
- **Expo:** el plan gratuito incluye 15 builds de Android y 15 de iOS al mes. Para instalar en un iPhone fuera de Expo Go se necesita una cuenta de Apple Developer de pago, por eso la demo usa Expo Go.

## Verificación

Hecho:
- El trigger de dominio rechaza correos externos y acepta los institucionales, creando el perfil con rol solicitante.
- `pg_cron` está disponible en el plan gratuito.
- El SMTP propio eleva el límite a 30 correos por hora.

Pendiente (pruebas 3 a 9 del spike):
- Sesión persistente, un pedido activo por usuario, RLS entre usuarios, estado en vivo en menos de 2 s, cancelación automática con `pg_cron` y funcionamiento en Expo Go sobre Android e iPhone.

**Criterio de reversión:** si falla el estado en vivo o la cancelación automática, se reevalúa la opción B.

## Impacto en el backlog

- T-004 pasa a inicializar el proyecto Supabase y las migraciones.
- T-068 a T-072 y T-076 se reducen, porque Supabase Auth ya cubre buena parte.
- T-010 pasa a pruebas de la base con pgTAP y de integración con supabase-js.
- Los puntos de esas tareas deben reestimarse al cerrar el spike.