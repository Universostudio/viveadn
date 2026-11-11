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
| Lógica de borde | Funciones Deno de Supabase en `supabase/functions` (ocho) | [V] |
| Despliegue de la web | Vercel (`vercel.json`) | [V] existe la configuración; [NV] el estado del despliegue |
| Pruebas | SQL sobre un Postgres local (`supabase/tests`) y scripts de Node (`scripts/probar-*.mts`) | [V] |
| Integración continua | GitHub Actions, un flujo con dos trabajos (base de datos y web) | [V] |

No hay servidor propio ni pasarela de cobro, de correo, de SMS ni de WhatsApp [V].

## 3. Estado real por área

La escala es completo, parcial o inexistente.

| Área | Estado | Qué hay y qué falta |
| --- | --- | --- |
| Inicio de sesión, registro, invitaciones, recuperar contraseña | Completo | Alta de iglesia por registro con código de beta y alta de personas por invitación [V] |
| Aislamiento entre iglesias | Completo en base de datos | Seguridad por filas en todas las tablas, claves foráneas compuestas, pruebas en cada solicitud de unión [V]. Prueba SQL exhaustiva con dos usuarios sobre todas las tablas, que detecta fugas inyectadas a propósito [V, `adn_aislamiento_total.sql`]. El mismo ataque a través de la API (PostgREST) está escrito y su plomería probada con un servidor simulado, pero no se ha ejecutado contra PostgREST real [NV, `docs/AISLAMIENTO.md`] |
| Roles y permisos | Completo | Roles por iglesia con permisos y módulos activables por plan [V] |
| Miembros | Completo | Listado, ficha, alta, edición, importación desde CSV [V] |
| Importador de miembros | Completo salvo validar con los archivos reales | Plantilla CSV propia y, desde el 11-11, contactos de Google, Outlook y Wix (el archivo real de Gerencia resultó ser de Wix; su estado de suscripción se guarda como consentimiento por canal y Comunicación solo envía a quien consta como suscrito): segundo correo, tres teléfonos, cumpleaños, direcciones y etiquetas, con deduplicación por correo, descarte de filas vacías y sin importar nunca contraseñas (`docs/IMPORTACION.md`). Probado a la escala de Gerencia (6.100 filas) con datos sintéticos [V]; el archivo real no se ha importado, solo se ha resumido desde el entorno de Gerencia [NV]. Falta decidir qué hacer con los contactos sin nombre (por defecto no se importan) |
| Casas de oración y zonas | Completo | Listado, edición, líderes [V] |
| Consolidación (OP72) | Completo | Seguimiento de las 72 horas con color de alerta, métricas avanzadas de pago [V]. Faltan las alertas automáticas, porque no existe canal de envío |
| Eventos y asistencia | Completo | Eventos, asistencia manual y registro por QR con enlace secreto, cartel imprimible [V] |
| Formación | Completo | Seguimiento por niveles, programas con lecciones, avance, certificados con QR y verificación pública [V]. Faltan la credencial personal con escáner y los reportes |
| Dar | Parcial | Página pública `/dar/:slug` con enlaces de recaudo de la iglesia [V]. No cobra: solo enlaza a pasarelas externas |
| Comunicación | Completo hacia un buzón de pruebas; sin envío real | Redactor, plantillas, grupos, vista previa de destinatarios con las reglas de la base de datos (bajas, repetidos, sin destino), envío idempotente con topes diarios e historial. El mensaje se guarda en un buzón de pruebas y no sale de la plataforma: el proveedor solo admite `sumidero` por una restricción de la tabla [V, `adn_comunicacion.sql`, `docs/COMUNICACION.md`]. Activar un proveedor real exige una migración nueva con aprobación del dueño, un enlace público de baja y revisión jurídica [H]. La pantalla no se abrió en un navegador real [NV] |
| Reportes | Completo | Cifras en pantalla (miembros, consolidación, formación, zonas) y, desde el 11-11, descarga de informes de miembros, asistencia y crecimiento en PDF y Excel, en los cuatro idiomas (`docs/INFORMES.md`). Probado con lectores independientes y datos sintéticos [V]; la pantalla no se ejecutó en un navegador real [NV]. Límite: el PDF no muestra alfabetos no latinos |
| Panel de inicio | Completo | Cifras de miembros, asistencia de ocho semanas, crecimiento de seis meses, próximos eventos, cumpleaños, formación y comunicación, desde una sola función que respeta los permisos del rol, además de consolidaciones críticas y miembros recientes [V, 24 comprobaciones en `adn_panel_inicio.sql`]. La pantalla no se abrió en un navegador real [NV] |
| Red de iglesias | Completo | Iglesia madre con sedes y cifras agregadas [V] |
| Panel de plataforma | Completo | Altas, planes, módulos, etapas, exportación, borrado programado, red, códigos de registro, auditoría [V] |
| Ciclo de vida de la iglesia | Completo en base de datos y función de borde; falta programar la purga | Etapas, receso, suspensión, borrado programado, borrado suave con plazo fijo de 30 días, recuperación dentro del plazo, purga completa y auditoría que sobrevive a la purga [V, 46 comprobaciones en `adn_ciclo_vida.sql` y reversión probada]. La purga automática necesita una tarea programada y el secreto `ADN_CRON_SECRET`: sin ellos la purga la lanza un administrador desde el panel [NV: la función de borde no se ejecutó de extremo a extremo, solo se comprobaron sus tipos y sus piezas puras] |
| Exportación de una iglesia | Completo, verificado en base de datos | JSON y un CSV por tabla con manifiesto de cifras y huellas (`docs/EXPORTACION.md`). Recargado en dos bases vacías (desde JSON y desde CSV) con las 25 tablas coincidiendo en filas y contenido [V]. La función de borde y el ZIP del panel no se ejecutaron de extremo a extremo [NV] |
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
- **Plataforma, solo servidor:** `plataforma_admins`, `plataforma_auditoria` (no sale en la exportación de la iglesia), `plataforma_ajustes`, `registro_codigos`, `registro_intentos`, `adn_ciclo_auditoria` (borrado suave, recuperación y purga; sobrevive a la purga).
- **Informes:** leen de las tablas anteriores con las funciones `adn_informe_*`. Solo tienen `adn_informe_descargas`, el registro de solo altas de quién descargó el informe de miembros, cuándo y cuántas filas.
- **Comunicación:** `adn_mensajes`, `adn_mensaje_destinatarios` (el buzón de pruebas), `adn_comunicacion_bajas` y `adn_consentimientos` (estado de suscripción por persona y canal), `adn_consentimiento_auditoria` (solo altas) y `adn_bajas_enlaces` (solo servidor, secretos de un solo uso que no salen en la exportación). El panel de inicio lee de las tablas anteriores con `adn_panel_inicio`.
- **Datos de contacto adicionales:** `adn_miembro_contactos` (segundos correos, teléfonos extra, direcciones y etiquetas de un miembro, por ejemplo de una importación).

Las tablas nuevas de esta línea de trabajo llevan el prefijo `adn_` [regla de Gerencia]. Las existentes no se renombran hasta que Gerencia lo ordene.

Reglas para toda tabla nueva: `docs/MULTITENANT.md`, sección 5.

## 5. Rutas de la web

Públicas: `/bienvenida`, `/presentacion`, `/login`, `/registro`, `/reset-password`, `/aceptar` (invitación), `/dar/:slug`, `/checkin/:token` y `/verificar/:codigo` y `/baja/:token` [V, `src/router/index.ts`].

Con sesión: `/` (panel), `/miembros`, `/miembros/:id`, `/eventos`, `/eventos/:id`, `/casas`, `/consolidacion`, `/formacion`, `/formacion/programas`, `/comunicacion`, `/comunicacion/consentimientos`, `/reportes`, `/configuracion`, `/red` y `/plataforma` (solo administradores de plataforma) [V]. Cada entrada del menú aparece según los permisos del rol y los módulos de la iglesia [V, `AppLayout.vue`].

## 6. Funciones de borde

`plataforma` (gestión), `red-resumen`, `dar-publico`, `checkin-evento`, `registro-iglesia`, `invitaciones`, `verificar-certificado` y `baja` [V]. Son la única vía que cruza iglesias y la única que usa la clave de servicio, que vive en los secretos de la función y no en el repositorio.

## 7. Pendientes

Los seis trabajos en curso, en orden:

1. Ciclo de vida de la iglesia: hecho salvo programar la purga automática (pendiente de aprobación del dueño).
2. Exportación completa en CSV y JSON: hecho y verificado en base de datos (ver `docs/EXPORTACION.md`).
3. Importador de miembros con formato Google Contacts: hecho con datos sintéticos; falta probarlo con los archivos reales que entregue Gerencia.
4. Informes en PDF y Excel (miembros, asistencia, crecimiento): hecho y verificado (ver `docs/INFORMES.md`).
5. Panel de inicio completo y Comunicación con envío al buzón de pruebas y consentimiento por canal: hecho y verificado en base de datos (ver `docs/COMUNICACION.md`). Hechos el 11-11: pantalla de consentimientos con auditoría de solo altas, interruptor de baja por canal en la ficha y enlace público de baja de un solo uso, sin envío real (`docs/COMUNICACION.md`). El envío real sigue pendiente de proveedor, enlace de baja y aprobación del dueño.
6. Pruebas de aislamiento con dos usuarios de prueba: hecha y verificada a nivel SQL con los roles reales; la versión a través de la API está escrita y pendiente de ejecutarse contra PostgREST (ver `docs/AISLAMIENTO.md`).

**Requisitos previos al envío real de mensajes (Gerencia, 11-11):**

1. Crear un enlace de baja por destinatario y canal al enviar, con `adn_baja_crear_enlace`, y poner `https://<web>/baja/<secreto>` en el mensaje.
2. Desplegar la función de borde `baja` sin verificar el JWT, como `dar-publico`, y probarla de extremo a extremo.
3. Límite de frecuencia en `baja` (opcional: no hace falta contra la fuerza bruta, pero frena el ruido).
4. Un proveedor aprobado por el dueño, base legal revisada por un abogado (`docs/COMUNICACION.md`, apartado 5) y consentimientos registrados. Re-suscribir a alguien exige un registro explícito con origen: quitar una baja lo deja en «sin dato».

**Prioritaria antes de producción:** paginar la exportación o generar el ZIP en el servidor, porque hoy todo el paquete viaja en una sola respuesta y no se ha medido con iglesias de decenas de miles de filas (`docs/EXPORTACION.md`).

Del producto, sin fecha: cobro del plan, canal de envío real de mensajes y alertas, credencial con escáner, subdominio por iglesia, historial de cambios por iglesia y segundo factor obligatorio [V, `docs/MULTITENANT.md` y `docs/COBRO.md`].

## 8. Hallazgos de higiene del repositorio

- **[V] El repositorio es público y ya contiene identificadores de infraestructura** en `supabase/README.md` (nombre y referencia del proyecto de base de datos, región) y en `docs/MULTITENANT.md` (nombre del proyecto y región). Quitarlos del último commit no los borra del historial. Gerencia debe decidir si se reescribe el historial o si se acepta la exposición, y rotar lo que corresponda.
- **[V] `docs/COBRO.md` y `docs/MULTITENANT.md` describen datos de producción** (conteos de tablas, estado de despliegues). Es información operativa, no secretos, pero conviene moverla a un documento privado.
- **[V] Secretos en el historial:** se buscaron, en los 79 commits de todas las ramas, claves JWT, claves de Supabase y de Stripe, claves privadas, tokens de GitHub y de Slack, y archivos `.env`. No hay ninguna clave real: la única coincidencia es un marcador truncado en `.env.example`, y `.env` nunca se subió. Las direcciones de correo del repositorio son de prueba, salvo un contacto público de la empresa.
- **[V, hallazgo de otro producto, 11-11] Cuentas creadas por SQL:** un NULL en columnas de texto de `auth.users` (`email_change`, etc.) rompe el inicio de sesión del servicio de Supabase. Hay una comprobación en `supabase/tests` para la rama de pruebas (`supabase/README.md`).
- [NV] La búsqueda cubre el historial local. No cubre las solicitudes de unión cerradas ni los comentarios de GitHub.
