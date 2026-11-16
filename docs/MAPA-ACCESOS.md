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

La regla es la de `AppLayout.vue`: una sección aparece si el rol tiene alguno de sus permisos y la iglesia tiene el módulo en su plan. Esta tabla sale de aplicar esa regla a los permisos sembrados, suponiendo todos los módulos activos [E]. Eventos y Comunicación dependen además del plan; Red solo la ve el propietario de una iglesia con sedes.

| Rol | Panel de inicio | Miembros | Eventos | Casas | Consolidación | Formación | Comunicación | Reportes | Configuración |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Propietario | sí | sí | sí | sí | sí | sí | sí | sí | sí |
| Administrador | sí | sí | sí | sí | sí | sí | sí | sí | sí |
| Co-administrador | sí | sí | sí | sí | sí | sí | sí | sí | no |
| Líder de Zona | sí | **no** | sí | **no** | **no** | no | no | sí | no |
| Líder de Casa | sí | sí | sí | sí | sí | no | no | no | no |
| Líder de Escuela | sí | sí | sí | no | no | sí | no | no | no |
| Consolidador | sí | sí | sí | no | sí | no | no | no | no |
| Colaborador | sí | **no** | sí | sí | **no** | no | no | no | no |
| Miembro | sí | no | sí | no | no | no | no | no | no |

Además de esta tabla, `/datos-iglesia` (descarga y baja) solo la completa el propietario, y `/comunicacion/consentimientos` y `/formacion/programas` se abren desde sus secciones. La base de datos aplica por su cuenta el aislamiento por iglesia y los permisos con políticas de nivel de fila, de modo que el menú es comodidad y la base es la barrera [E, `docs/AISLAMIENTO.md`].

### Tarjetas del panel de inicio por rol

El panel de inicio muestra una tarjeta por permiso: asistencia (`asistencia.ver`), dos de miembros (`miembros.ver`), eventos (`eventos.ver`), formación (`formacion.ver`) y comunicación (`comunicacion.ver`). Aplicado a los permisos sembrados [E]: propietario, administrador y co-administrador ven las cinco; el líder de escuela ve miembros, eventos y formación; el resto (líder de zona, líder de casa, consolidador, colaborador y miembro) ve solo la tarjeta de eventos.

## 4. Qué ruta lleva a cada sitio tras iniciar sesión

| Quién | Aterriza en | Cómo sigue |
| --- | --- | --- |
| Administrador de plataforma sin iglesia | `/plataforma` | Las rutas de iglesia le redirigen al panel |
| Administrador de plataforma con iglesia | `/plataforma` | «Entrar a mi iglesia» lleva a `/`; «Volver al Panel Maestro» regresa; la elección dura la pestaña |
| Cualquier rol de iglesia | `/` | Elige en el menú lo que su rol permite |
| Propietario con la iglesia suspendida (baja pedida) | `/` con aviso rojo | El aviso lleva a `/datos-iglesia` para descargar o cancelar la baja |
| Persona invitada | `/aceptar` desde el enlace del correo | Crea su contraseña y entra a `/` con el rol de la invitación |
| Sin sesión | `/bienvenida` (raíz) o `/login` | Las páginas públicas (`/dar/:slug`, `/checkin/:token`, `/baja/:token`...) no piden sesión |

No hay aterrizaje por rol: un líder de casa y un administrador llegan al mismo `/` [E].

## 5. Qué falta

Ordenado por lo que más se nota en pantalla.

1. **Permisos acotados sin pantalla [E].** Tres roles tienen permisos restringidos (`ver_zona`, `ver_propios`) que el menú no reconoce: el líder de zona no tiene entrada de Miembros, Casas ni Consolidación aunque su permiso es verlas de su zona, y el colaborador no tiene Miembros ni Consolidación aunque puede ver lo que registra. El resultado es que el líder de zona solo ve Panel de inicio, Eventos y Reportes. Es el hueco más claro entre lo que promete la descripción del rol y lo que muestra la aplicación. La base ya filtra por zona y por autor; falta la entrada de menú y la pantalla que enseñe solo ese subconjunto.
2. **No hay «Mi panel» por rol (nivel 3) [E].** Todos ven el mismo panel de inicio filtrado por permisos. No hay una portada propia para el líder de casa (su casa, su asistencia de la semana, sus nuevos convertidos), ni para el líder de zona (sus casas con semáforo), ni para el consolidador (sus contactos pendientes), ni para el miembro (su perfil, sus eventos, su progreso).
3. **El rol `miembro` solo ve Eventos [E].** No existe un portal del miembro: ver y corregir sus datos, sus consentimientos, su historial de asistencia o su formación.
4. **No hay rol «pastor» ni un nombre «supervisor de zona» [E].** Ver apartado 2.
5. **No hay pantalla para crear roles nuevos [E].** Configuración permite cambiar el rol de un usuario entre los existentes y ver sus permisos, pero no crear ni editar roles. El permiso `roles.gestionar` existe y solo lo tiene el propietario.
6. **El router no comprueba permisos [E].** Una dirección escrita a mano abre la vista aunque el menú no la ofrezca; los datos siguen protegidos por la base y varias vistas comprueban `can()` por dentro, pero una persona sin permiso vería una pantalla vacía en lugar de una redirección clara.
7. **Permisos sin pantalla [E].** `gamificacion.*` y `zonas.*` existen y se asignan a roles, pero no tienen entrada de menú.
8. **«Ver como» solo para el propietario [E].** Permite al superadministrador previsualizar la interfaz con los permisos de otro rol; no cambia lo que permite la base. No se ha pensado una versión para el administrador de plataforma, que por principio no ve a las personas de una iglesia.

## 6. Decisiones de producto (Gerencia, 16 de noviembre de 2026) y lo que queda para Harold

Decididas por Gerencia:
1. **Rol «Pastor».** No se crea todavía. Se cubre con propietario o administrador. **PENDIENTE: le diré** (Harold decide si existe y qué ve).
2. **Líder de zona.** No se renombra la clave en la base. El nombre que se muestra pasa a ser configurable por iglesia (una etiqueta), sin cambiar la clave del rol.
3. **Crear y editar roles por iglesia.** Fase posterior, no ahora.
4. **Orden de «Mi panel».** Líder de casa, líder de zona y consolidador, y al final el miembro.

Orden de construcción acordado: A seguimiento de nuevos creyentes, B líderes (zonas, líder de casa y de zona, casa de cada persona), C menú y router por permisos con «Mi panel» del líder de casa, D registro por QR con la pregunta «¿Es nuevo creyente?», E ficha del miembro editable y panel de inicio honesto, F diseño del método de seguimiento configurable (solo documento) y G siembra de cuatro iglesias de prueba.

Estado: A hecho (ver `docs/MANUAL-IGLESIAS.md`, apartado 7). El resto, pendiente.
