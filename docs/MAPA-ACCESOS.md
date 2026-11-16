# Mapa de paneles y accesos por rol

Estado a 16 de noviembre de 2026. Responde a tres preguntas: qué paneles hay, qué ve cada rol y qué le falta a cada nivel. Etiquetas: [E] comprobado en el código o con prueba repetible, [H] deducido, [NV] no verificable desde el repositorio. Complementa a `docs/PANEL-MAESTRO.md` (el nivel 1) y a `docs/MULTITENANT.md`.

## 1. Los tres niveles

| Nivel | Quién | Dónde entra | Estado |
| --- | --- | --- | --- |
| 1. Panel Maestro | Administradores de plataforma (`plataforma_admins`) | `/plataforma` con layout y menú propios | Hecho [E, `scripts/probar-panel-maestro-ui.mjs`] |
| 2. Panel de la iglesia | Cada iglesia, con todas las secciones de su plan | `/` con `AppLayout` | Hecho; las secciones salen según el plan y el rol [E, `AppLayout.vue`] |
| 3. Acceso propio de cada usuario | Cada persona con cuenta, según su rol | También `/`: un solo panel de inicio filtrado por permisos | Parcial: no existe un «Mi panel» por rol (apartado 5) |

Tras iniciar sesión, todos los roles de iglesia llegan a `/`. La excepción es el administrador de plataforma, que llega a `/plataforma`; si además tiene iglesia, cambia de contexto con «Entrar a mi iglesia» y «Volver al Panel Maestro» [E].

## 2. Los roles que existen

Cada iglesia nace con nueve roles de sistema, que son filas de la tabla `roles` de esa iglesia (esquema base y migración `20261030000000`). El propietario tiene todos los permisos sin lista; el resto tiene los permisos que se muestran [E: lectura de `rol_permisos` en una base local recién sembrada].

| Clave | Nombre en pantalla | Para qué existe | Permisos de más peso |
| --- | --- | --- | --- |
| `propietario` | Propietario (superadministrador) | Acceso total; único que cambia al propietario; el que descarga los datos y pide la baja de la iglesia | Todos, incluida la configuración de la iglesia y la gestión de roles |
| `administrador` | Administrador | Gestión operativa completa | Todo lo operativo, gestión de usuarios y de zonas; no la configuración crítica |
| `coadministrador` | Co-administrador | Opera miembros, casas, consolidación, formación y reportes | Sin gestión de usuarios, roles ni configuración; sin lectura de asistencia por zona |
| `lider_zona` | Líder de Zona | Supervisa las casas de su zona | Ver casas, miembros, consolidación y asistencia de su zona; reportes; eventos |
| `lider_casa` | Líder de Casa de Oración | Gestiona su casa | Casa propia, miembros asignados, consolidación de su casa, registrar asistencia propia; eventos |
| `lider_escuela` | Líder de Escuela de Formación | Lleva la formación | Programas, progreso y certificados; ver miembros; eventos |
| `consolidador` | Consolidador | Da seguimiento a nuevos convertidos asignados | Procesos asignados, registrar contactos; miembros asignados; eventos |
| `colaborador` | Colaborador | Registra asistencia y nuevos convertidos | Solo lo que registra él mismo; casas; eventos |
| `miembro` | Miembro | Acceso básico | Solo eventos |

**Nombres que pidió Harold y no existen tal cual.** No hay un rol «pastor». El «supervisor de zona» es el `lider_zona`. El perfil pastoral de una iglesia pequeña se cubre hoy con `propietario` o `administrador` [E]. Si Harold quiere un rol «Pastor» con un panel propio, hay que decidir qué permisos tiene (apartado 6).

## 3. Qué secciones del menú ve cada rol

La regla vive en un solo sitio, `src/lib/acceso.ts`: el menú de `AppLayout.vue` y la comprobación de cada ruta del router leen la misma tabla, de modo que lo que se ofrece y lo que se abre no se separan. Una sección aparece si el rol tiene alguno de sus permisos (incluidos los acotados `ver_zona`, `ver_propios`, `ver_asignados`) y la iglesia tiene el módulo en su plan. `scripts/probar-acceso.mts` aplica esa regla a los permisos reales de cada rol y falla si cambian en la base sin actualizar la prueba [E]. Eventos y Comunicación dependen además del plan; Red solo la ve el propietario de una iglesia con sedes; «Mi panel» solo el líder de casa.

| Rol | Mi panel | Inicio | Miembros | Eventos | Casas | Zonas | Consolidación | Formación | Logros | Comunicación | Reportes | Configuración |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Propietario | no | sí | sí | sí | sí | sí | sí | sí | sí | sí | sí | sí |
| Administrador | no | sí | sí | sí | sí | sí | sí | sí | sí | sí | sí | sí |
| Co-administrador | no | sí | sí | sí | sí | sí | sí | sí | sí | sí | sí | no |
| Líder de Zona | no | sí | sí (su zona) | sí | sí (su zona) | sí (solo mira) | sí (su zona) | no | sí | no | sí | no |
| Líder de Casa | **sí** | sí | sí (su gente) | sí | sí (la suya) | no | sí (su casa) | no | no | no | no | no |
| Líder de Escuela | no | sí | sí | sí | no | no | no | sí | sí | no | no | no |
| Consolidador | no | sí | sí (sus asignados) | sí | no | no | sí | no | no | no | no | no |
| Colaborador | no | sí | sí (lo que registra) | sí | sí | no | sí | no | no | no | no | no |
| Miembro | no | sí | no | sí | no | no | no | no | no | no | no | no |

Además de esta tabla, `/datos-iglesia` (descarga y baja) solo la completa el propietario, y `/comunicacion/consentimientos` y `/formacion/programas` se abren desde sus secciones. La base de datos aplica por su cuenta el aislamiento por iglesia y los permisos con políticas de nivel de fila, de modo que el menú y el router evitan una pantalla vacía y la base es la barrera [E, `docs/AISLAMIENTO.md`].

**Escribir la dirección a mano.** Una ruta cuyos requisitos no cumple el rol lleva a `/sin-acceso`, una pantalla que nombra el rol, dice qué dirección se intentó y ofrece volver a la portada del rol. Es lo que hace el guard del router con la misma tabla del menú [E, `scripts/probar-acceso-ui.mjs`].

### Tarjetas del panel de inicio por rol

Las cuatro cifras de arriba (personas, casas, personas en seguimiento y alertas críticas) salen de `tarjetasDeInicio` (`src/lib/panelInicio.ts`) con los permisos del rol: con el permiso amplio (`miembros.ver`, `casas.ver`, `consolidacion.ver`) cuentan toda la iglesia; con uno acotado (`ver_asignados`, `ver_zona`, `ver_propios`, `ver_propia`, `ver_casa`) cuentan lo que el rol tiene a su cargo y el rótulo lo dice; sin permiso, no hay tarjeta. El panel de inicio muestra además un bloque por permiso: asistencia (`asistencia.ver`), crecimiento y cumpleaños (`miembros.ver`), eventos (`eventos.ver`), formación (`formacion.ver`) y comunicación (`comunicacion.ver`). Aplicado a los permisos sembrados [E]: propietario, administrador y co-administrador ven todo; el líder de zona, el líder de casa, el consolidador y el colaborador ven las cifras acotadas de lo suyo; el líder de escuela, miembros, eventos y formación; el miembro, solo eventos. Un dato que no carga se muestra como «—» con aviso y botón de reintentar, nunca como cero.

## 4. Qué ruta lleva a cada sitio tras iniciar sesión

| Quién | Aterriza en | Cómo sigue |
| --- | --- | --- |
| Administrador de plataforma sin iglesia | `/plataforma` | Las rutas de iglesia le redirigen al panel |
| Administrador de plataforma con iglesia | `/plataforma` | «Entrar a mi iglesia» lleva a `/`; «Volver al Panel Maestro» regresa; la elección dura la pestaña |
| Líder de casa | `/mi-panel` | Su casa, sus personas con llamar y WhatsApp, pasar lista y sus nuevos creyentes |
| Cualquier otro rol de iglesia | `/` | Elige en el menú lo que su rol permite |
| Propietario con la iglesia suspendida (baja pedida) | `/` con aviso rojo | El aviso lleva a `/datos-iglesia` para descargar o cancelar la baja |
| Persona invitada | `/aceptar` desde el enlace del correo | Crea su contraseña y entra a la portada de su rol |
| Sin sesión | `/bienvenida` (raíz) o `/login` | Las páginas públicas (`/dar/:slug`, `/checkin/:token`, `/baja/:token`...) no piden sesión |

El aterrizaje sale de `aterrizajeDe` (`src/lib/acceso.ts`): quien ve solo su casa y no todas llega a «Mi panel». Iniciar sesión y abrir `/login` con una sesión ya abierta llevan al mismo sitio [E].

### «Mi panel» del líder de casa

Muestra su casa (o varias, con selector), las personas asignadas con enlaces para llamar y escribir por WhatsApp, **pasar lista** de una fecha (crea las filas de asistencia que faltan y actualiza las existentes, sin duplicar), el resumen de las últimas cuatro semanas y, si el rol puede ver la consolidación de su casa, sus nuevos creyentes en seguimiento en solo lectura. Sin casa asignada lo dice y explica a quién pedirla. El orden acordado para el resto de portadas es líder de zona y consolidador, y por último el miembro: aún sin hacer.

## 5. Qué falta

Ordenado por lo que más se nota en pantalla.

1. **No hay «Mi panel» para el líder de zona, el consolidador ni el miembro (nivel 3) [E].** Hecho para el líder de casa. El líder de zona (sus casas con semáforo), el consolidador (sus contactos pendientes) y el miembro (su perfil, sus eventos, su progreso) siguen con el panel de inicio general.
2. **El rol `miembro` solo ve Eventos [E].** No existe un portal del miembro: ver y corregir sus datos, sus consentimientos, su historial de asistencia o su formación.
3. **No hay rol «pastor» ni un nombre «supervisor de zona» [E].** Ver apartado 2. **PENDIENTE: le diré.**
4. **No hay pantalla para crear roles nuevos [E].** Configuración permite cambiar el rol de un usuario entre los existentes y ver sus permisos, pero no crear ni editar roles. El permiso `roles.gestionar` existe y solo lo tiene el propietario. Fase posterior acordada por Gerencia.
5. **«Ver como» solo para el propietario [E].** Permite al superadministrador previsualizar la interfaz con los permisos de otro rol, y el menú y el guard de rutas respetan esa vista; no cambia lo que permite la base. No se ha pensado una versión para el administrador de plataforma, que por principio no ve a las personas de una iglesia.
6. **Logros es una pantalla mínima [E].** Otorgar un logro a una persona, ranking y logros recientes; no hay catálogo de logros ni reglas automáticas de puntos.

Resuelto en el paso C: permisos acotados sin entrada de menú (líder de zona y colaborador), router sin comprobación de permisos, y `zonas.*` y `gamificacion.*` sin entrada de menú.

## 6. Decisiones de producto (Gerencia, 16 de noviembre de 2026) y lo que queda para Harold

Decididas por Gerencia:
1. **Rol «Pastor».** No se crea todavía. Se cubre con propietario o administrador. **PENDIENTE: le diré** (Harold decide si existe y qué ve).
2. **Líder de zona.** No se renombra la clave en la base. El nombre que se muestra pasa a ser configurable por iglesia (una etiqueta), sin cambiar la clave del rol.
3. **Crear y editar roles por iglesia.** Fase posterior, no ahora.
4. **Orden de «Mi panel».** Líder de casa, líder de zona y consolidador, y al final el miembro.

Orden de construcción acordado: A seguimiento de nuevos creyentes, B líderes (zonas, líder de casa y de zona, casa de cada persona), C menú y router por permisos con «Mi panel» del líder de casa, D registro por QR con la pregunta «¿Es nuevo creyente?», E ficha del miembro editable y panel de inicio honesto, F diseño del método de seguimiento configurable (solo documento) y G siembra de cuatro iglesias de prueba.

Estado: A hecho (`docs/MANUAL-IGLESIAS.md`, apartado 7), B hecho (apartado 5: zonas, líderes y asignación de casa a cada persona) y C hecho (menú y router por permisos, pantalla de sin acceso, aterrizaje por rol, «Mi panel» del líder de casa, entradas de Zonas y Logros). El resto, pendiente.
