# Contexto de ViveADN

Documento de referencia para quien se incorpora al proyecto. No contiene datos de infraestructura (identificadores de proyectos, claves, dominios internos ni datos de personas), porque el repositorio es público.

Cada afirmación lleva su etiqueta: **[V]** verificado leyendo el código o ejecutando algo en esta sesión, **[H]** deducido de lo que se ve, **[NV]** no verificable desde el repositorio. Estado a 11 de noviembre de 2026, sobre la rama `main`.

## 1. Qué es

ViveADN es una aplicación web para gestionar iglesias: miembros, casas de oración (células), consolidación de nuevos creyentes, eventos y asistencia, formación con certificados, dar (enlaces de ofrenda) y comunicación. Cada iglesia es un inquilino aislado dentro de una sola base de datos compartida [V]. La web sirve en español, inglés, francés y portugués de Brasil [V, `src/i18n/locales`]. El producto lo construye Visualiza Studio.

## 2. Stack

| Capa | Tecnología | Estado |
| --- | --- | --- |
| Interfaz | Vue 3, Vite, Pinia, Vue Router, vue-i18n, Tailwind 3 | [V] `package.json` |
| Datos y acceso | Supabase: Postgres con seguridad por filas, Auth, Storage | [V] |
| Lógica de borde | Funciones Deno de Supabase en `supabase/functions` (seis) | [V] |
| Despliegue de la web | Vercel (`vercel.json`) | [V] existe la configuración; [NV] el estado del despliegue |
| Pruebas | SQL sobre un Postgres local (`supabase/tests`) y scripts de Node (`scripts/probar-*.mts`) | [V] |
| Integración continua | GitHub Actions, un flujo con dos trabajos (base de datos y web) | [V] |

No hay servidor propio ni pasarela de cobro, de correo, de SMS ni de WhatsApp [V].

## 3. Estado real por área

La escala es completo, parcial o inexistente.

| Área | Estado | Qué hay y qué falta |
| --- | --- | --- |
| Inicio de sesión, registro, invitaciones, recuperar contraseña | Completo | Alta de iglesia por registro con código de beta y alta de personas por invitación [V] |
| Aislamiento entre iglesias | Completo en base de datos | Seguridad por filas en todas las tablas, claves foráneas compuestas, pruebas en cada solicitud de unión [V]. Hay pruebas SQL; falta una prueba de extremo a extremo con dos usuarios reales a través de la API (trabajo 6) |
| Roles y permisos | Completo | Roles por iglesia con permisos y módulos activables por plan [V] |
| Miembros | Completo | Listado, ficha, alta, edición, importación desde CSV [V] |
| Importador de miembros | Parcial | Lee CSV con columnas en español o inglés, máximo 2.000 filas, valida y detecta duplicados [V]. No mapea el formato de Google Contacts: no admite segundo correo, tres teléfonos, direcciones ni etiquetas, y exige apellido a cada fila [V, `src/lib/importarMiembros.ts`] |
| Casas de oración y zonas | Completo | Listado, edición, líderes [V] |
| Consolidación (OP72) | Completo | Seguimiento de las 72 horas con color de alerta, métricas avanzadas de pago [V]. Faltan las alertas automáticas, porque no existe canal de envío |
| Eventos y asistencia | Completo | Eventos, asistencia manual y registro por QR con enlace secreto, cartel imprimible [V] |
| Formación | Completo | Seguimiento por niveles, programas con lecciones, avance, certificados con QR y verificación pública [V]. Faltan la credencial personal con escáner y los reportes |
| Dar | Parcial | Página pública `/dar/:slug` con enlaces de recaudo de la iglesia [V]. No cobra: solo enlaza a pasarelas externas |
| Comunicación | Parcial, solo maqueta | Redactor, plantillas, segmentos y vista previa [V]. No guarda mensajes, no tiene historial real y no envía nada [V, `ComunicacionView.vue`] |
| Reportes | Parcial | Cifras en pantalla (miembros, consolidación, formación, zonas) [V]. No exporta a PDF ni a Excel, y no hay informe de asistencia ni de crecimiento por periodo |
| Panel de inicio | Parcial | Cuatro cifras, consolidaciones críticas y miembros recientes con datos reales [V]. No muestra asistencia, crecimiento ni eventos próximos |
| Red de iglesias | Completo | Iglesia madre con sedes y cifras agregadas [V] |
| Panel de plataforma | Completo | Altas, planes, módulos, etapas, exportación, borrado programado, red, códigos de registro, auditoría [V] |
| Ciclo de vida de la iglesia | Completo en base de datos y función de borde; falta programar la purga | Etapas, receso, suspensión, borrado programado, borrado suave con plazo fijo de 30 días, recuperación dentro del plazo, purga completa y auditoría que sobrevive a la purga [V, 46 comprobaciones en `adn_ciclo_vida.sql` y reversión probada]. La purga automática necesita una tarea programada y el secreto `ADN_CRON_SECRET`: sin ellos la purga la lanza un administrador desde el panel [NV: la función de borde no se ejecutó de extremo a extremo, solo se comprobaron sus tipos y sus piezas puras] |
| Exportación de una iglesia | Parcial | `exportar_iglesia` entrega un JSON con todas las tablas con `iglesia_id` y el listado de archivos, sin tokens ni huellas [V]. No hay CSV ni prueba de carga en una base vacía (trabajo 2) |
| Cobro del plan | Inexistente | Solo hay diseño en `docs/COBRO.md`; no hay tablas ni código [V] |
| Subdominio por iglesia, historial de cambios por iglesia, segundo factor obligatorio | Inexistente | Listados como brechas en `docs/MULTITENANT.md` [V] |

## 4. Tablas

Tablas de la base pública, agrupadas. Todas llevan seguridad por filas [V, `docs/MULTITENANT.md` y las pruebas de permisos].

- **Inquilino y acceso:** `iglesias`, `perfiles`, `roles`, `rol_permisos`, `permisos`, `invitaciones`.
- **Planes:** `planes`, `modulos`, `plan_modulos`, `iglesia_modulos`.
- **Personas y comunidad:** `miembros`, `zonas`, `casas_oracion`, `consolidaciones`, `logros`.
- **Eventos:** `eventos`, `asistencias`, `asistencia_evento`, `evento_checkin`, `checkin_registros`.
- **Formación:** `progreso_formacion`, `programas_formacion`, `programa_lecciones`, `inscripciones_formacion`, `avance_formacion`, `certificados`.
- **Dar:** `dar_config`, `enlaces_dar`.
- **Plataforma, solo servidor:** `plataforma_admins`, `plataforma_auditoria`, `plataforma_ajustes`, `registro_codigos`, `registro_intentos`.

Las tablas nuevas de esta línea de trabajo llevan el prefijo `adn_` [regla de Gerencia]. Las existentes no se renombran hasta que Gerencia lo ordene.

Reglas para toda tabla nueva: `docs/MULTITENANT.md`, sección 5.

## 5. Rutas de la web

Públicas: `/bienvenida`, `/presentacion`, `/login`, `/registro`, `/reset-password`, `/aceptar` (invitación), `/dar/:slug`, `/checkin/:token` y `/verificar/:codigo` [V, `src/router/index.ts`].

Con sesión: `/` (panel), `/miembros`, `/miembros/:id`, `/eventos`, `/eventos/:id`, `/casas`, `/consolidacion`, `/formacion`, `/formacion/programas`, `/comunicacion`, `/reportes`, `/configuracion`, `/red` y `/plataforma` (solo administradores de plataforma) [V]. Cada entrada del menú aparece según los permisos del rol y los módulos de la iglesia [V, `AppLayout.vue`].

## 6. Funciones de borde

`plataforma` (gestión), `red-resumen`, `dar-publico`, `checkin-evento`, `registro-iglesia`, `invitaciones` y `verificar-certificado` [V]. Son la única vía que cruza iglesias y la única que usa la clave de servicio, que vive en los secretos de la función y no en el repositorio.

## 7. Pendientes

Los seis trabajos en curso, en orden:

1. Ciclo de vida de la iglesia: hecho salvo programar la purga automática (pendiente de aprobación del dueño).
2. Exportación completa en CSV y JSON, con prueba de carga en una base vacía y comparación de cifras.
3. Importador de miembros con formato Google Contacts.
4. Informes en PDF y Excel (miembros, asistencia, crecimiento).
5. Panel de inicio completo y envío real en Comunicación, en pruebas solo hacia un sumidero.
6. Pruebas de aislamiento con dos usuarios de prueba a través de la API.

Del producto, sin fecha: cobro del plan, canal de envío de alertas, credencial con escáner, subdominio por iglesia, historial de cambios por iglesia y segundo factor obligatorio [V, `docs/MULTITENANT.md` y `docs/COBRO.md`].

## 8. Hallazgos de higiene del repositorio

- **[V] El repositorio es público y ya contiene identificadores de infraestructura** en `supabase/README.md` (nombre y referencia del proyecto de base de datos, región) y en `docs/MULTITENANT.md` (nombre del proyecto y región). Quitarlos del último commit no los borra del historial. Gerencia debe decidir si se reescribe el historial o si se acepta la exposición, y rotar lo que corresponda.
- **[V] `docs/COBRO.md` y `docs/MULTITENANT.md` describen datos de producción** (conteos de tablas, estado de despliegues). Es información operativa, no secretos, pero conviene moverla a un documento privado.
- **[V] Secretos en el historial:** se buscaron, en los 79 commits de todas las ramas, claves JWT, claves de Supabase y de Stripe, claves privadas, tokens de GitHub y de Slack, y archivos `.env`. No hay ninguna clave real: la única coincidencia es un marcador truncado en `.env.example`, y `.env` nunca se subió. Las direcciones de correo del repositorio son de prueba, salvo un contacto público de la empresa.
- [NV] La búsqueda cubre el historial local. No cubre las solicitudes de unión cerradas ni los comentarios de GitHub.
