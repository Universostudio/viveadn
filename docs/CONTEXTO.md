# Contexto de Vive ADN

Documento de referencia para quien se incorpora al proyecto. No contiene datos de infraestructura (identificadores de proyectos, claves, dominios internos ni datos de personas), porque el repositorio es público.

Cada afirmación lleva su etiqueta de evidencia: **[V]** comprobado por Gerencia, **[E]** informado por Desarrollo con una prueba repetible (ver «Cómo repetir las pruebas»), **[H]** deducido de lo que se ve, **[NV]** no verificable desde el repositorio. Desarrollo no usa **[V]**: solo Gerencia puede comprobar algo. Estado a 11 de noviembre de 2026, sobre la rama `gerencia/contexto-2026-11-11`.

## 1. Qué es

Vive ADN es una aplicación web para gestionar iglesias: miembros, casas de oración (células), consolidación de nuevos creyentes, eventos y asistencia, formación con certificados, dar (enlaces de ofrenda) y comunicación. Cada iglesia es un inquilino aislado dentro de una sola base de datos compartida [E]. La web sirve en español, inglés, francés y portugués de Brasil [E, `src/i18n/locales`]. El producto lo construye Visualiza Studio.

## 2. Stack

| Capa | Tecnología | Estado |
| --- | --- | --- |
| Interfaz | Vue 3, Vite, Pinia, Vue Router, vue-i18n, Tailwind 3 | [E] `package.json` |
| Datos y acceso | Supabase: Postgres con seguridad por filas, Auth, Storage | [E] |
| Lógica de borde | Funciones Deno de Supabase en `supabase/functions` (ocho) | [E] |
| Despliegue de la web | Vercel (`vercel.json`) | [E] existe la configuración; [NV] el estado del despliegue |
| Pruebas | SQL sobre un Postgres local (`supabase/tests`) y scripts de Node (`scripts/probar-*.mts`) | [E] |
| Integración continua | GitHub Actions, un flujo con dos trabajos (base de datos y web) | [E] |

No hay servidor propio ni pasarela de cobro, de correo, de SMS ni de WhatsApp [E].

## 3. Estado real por área

La escala es completo, parcial o inexistente.

| Área | Estado | Qué hay y qué falta |
| --- | --- | --- |
| Inicio de sesión, registro, invitaciones, recuperar contraseña | Completo | Alta de iglesia por registro con código de beta y alta de personas por invitación [E] |
| Aislamiento entre iglesias | Completo en base de datos | Seguridad por filas en todas las tablas, claves foráneas compuestas, pruebas en cada solicitud de unión [E]. Prueba SQL exhaustiva con dos usuarios sobre todas las tablas, que detecta fugas inyectadas a propósito [E, `adn_aislamiento_total.sql`]. El mismo ataque a través de la API (PostgREST) está escrito y su plomería probada con un servidor simulado, pero no se ha ejecutado contra PostgREST real [NV, `docs/AISLAMIENTO.md`] |
| Roles y permisos | Completo | Roles por iglesia con permisos y módulos activables por plan [E] |
| Miembros | Completo | Listado, ficha, alta, edición, importación desde CSV [E] |
| Importador de miembros | Completo salvo validar con los archivos reales | Plantilla CSV propia y, desde el 11-11, contactos de Google, Outlook y Wix (el archivo real de Gerencia resultó ser de Wix; su estado de suscripción se guarda como consentimiento por canal y Comunicación solo envía a quien consta como suscrito): segundo correo, tres teléfonos, cumpleaños, direcciones y etiquetas, con deduplicación por correo, descarte de filas vacías y sin importar nunca contraseñas (`docs/IMPORTACION.md`). Probado a la escala de Gerencia (6.100 filas) con datos sintéticos [E]; el archivo real no se ha importado, solo se ha resumido desde el entorno de Gerencia [NV]. Falta decidir qué hacer con los contactos sin nombre (por defecto no se importan) |
| Casas de oración y zonas | Completo | Listado, edición, líderes [E] |
| Consolidación (OP72) | Completo | Seguimiento de las 72 horas con color de alerta, métricas avanzadas de pago [E]. Faltan las alertas automáticas, porque no existe canal de envío |
| Eventos y asistencia | Completo | Eventos, asistencia manual y registro por QR con enlace secreto, cartel imprimible [E] |
| Formación | Completo | Seguimiento por niveles, programas con lecciones, avance, certificados con QR y verificación pública [E]. Faltan la credencial personal con escáner y los reportes |
| Dar | Parcial | Página pública `/dar/:slug` con enlaces de recaudo de la iglesia [E]. No cobra: solo enlaza a pasarelas externas |
| Comunicación | Completo hacia un buzón de pruebas; sin envío real | Redactor, plantillas, grupos, vista previa de destinatarios con las reglas de la base de datos (bajas, repetidos, sin destino), envío idempotente con topes diarios e historial. El mensaje se guarda en un buzón de pruebas y no sale de la plataforma: el proveedor solo admite `sumidero` por una restricción de la tabla [E, `adn_comunicacion.sql`, `docs/COMUNICACION.md`]. Activar un proveedor real exige una migración nueva con aprobación del dueño, un enlace público de baja y revisión jurídica [H]. La pantalla no se abrió en un navegador real [NV] |
| Reportes | Completo | Cifras en pantalla (miembros, consolidación, formación, zonas) y, desde el 11-11, descarga de informes de miembros, asistencia y crecimiento en PDF y Excel, en los cuatro idiomas (`docs/INFORMES.md`). Probado con lectores independientes y datos sintéticos [E]; la pantalla no se ejecutó en un navegador real [NV]. Límite: el PDF no muestra alfabetos no latinos |
| Panel de inicio | Completo | Cifras de miembros, asistencia de ocho semanas, crecimiento de seis meses, próximos eventos, cumpleaños, formación y comunicación, desde una sola función que respeta los permisos del rol, además de consolidaciones críticas y miembros recientes [E, 24 comprobaciones en `adn_panel_inicio.sql`]. La pantalla no se abrió en un navegador real [NV] |
| Red de iglesias | Completo | Iglesia madre con sedes y cifras agregadas [E] |
| Panel de plataforma | Completo | Altas, planes, módulos, etapas, exportación, borrado programado, red, códigos de registro, auditoría [E] |
| Ciclo de vida de la iglesia | Completo en base de datos y función de borde; la purga programada está diseñada y aprobada, falta activarla | Etapas, receso, suspensión, borrado programado, borrado suave con plazo fijo de 30 días, recuperación dentro del plazo, purga completa y auditoría que sobrevive a la purga [E, 46 comprobaciones en `adn_ciclo_vida.sql` y reversión probada]. La purga automática (opción A, `pg_cron` y `pg_net`, aprobada) necesita que Gerencia genere el secreto `ADN_CRON_SECRET` y verifique las extensiones en la rama de pruebas: sin ello la purga la lanza un administrador desde el panel, que ahora muestra su estado (tarjeta «Purga programada»). El libro externo de purgadas, que se exige para aceptar una restauración, está hecho en local (`adn_libro_purgas.sql`) [NV: la función de borde no se ejecutó de extremo a extremo, solo se comprobaron sus tipos y sus piezas puras] |
| Exportación de una iglesia | Completo, verificado en base de datos | JSON y un CSV por tabla con manifiesto de cifras y huellas (`docs/EXPORTACION.md`). Recargado en dos bases vacías (desde JSON y desde CSV) con las 32 tablas coincidiendo en filas y contenido [E]. La función de borde y el ZIP del panel no se ejecutaron de extremo a extremo [NV] |
| Cobro del plan | Inexistente | Solo hay diseño en `docs/COBRO.md`; no hay tablas ni código [E] |
| Subdominio por iglesia, historial de cambios por iglesia, segundo factor obligatorio | Inexistente | Listados como brechas en `docs/MULTITENANT.md` [E] |

## 4. Tablas

Tablas de la base pública, agrupadas. Todas llevan seguridad por filas [E, `docs/MULTITENANT.md` y las pruebas de permisos].

- **Inquilino y acceso:** `iglesias`, `perfiles`, `roles`, `rol_permisos`, `permisos`, `invitaciones`.
- **Planes:** `planes`, `modulos`, `plan_modulos`, `iglesia_modulos`.
- **Personas y comunidad:** `miembros`, `zonas`, `casas_oracion`, `consolidaciones`, `logros`.
- **Eventos:** `eventos`, `asistencias`, `asistencia_evento`, `evento_checkin`, `checkin_registros`.
- **Formación:** `progreso_formacion`, `programas_formacion`, `programa_lecciones`, `inscripciones_formacion`, `avance_formacion`, `certificados`.
- **Dar:** `dar_config`, `enlaces_dar`.
- **Plataforma, solo servidor:** `plataforma_admins`, `plataforma_auditoria` (no sale en la exportación de la iglesia), `plataforma_ajustes`, `registro_codigos`, `registro_intentos`, `adn_ciclo_auditoria` (borrado suave, recuperación y purga; sobrevive a la purga).
- **Informes:** leen de las tablas anteriores con las funciones `adn_informe_*`. Solo tienen `adn_informe_descargas`, el registro de solo altas de quién descargó el informe de miembros, cuándo y cuántas filas.
- **Comunicación:** `adn_mensajes`, `adn_mensaje_destinatarios` (el buzón de pruebas), `adn_comunicacion_bajas` y `adn_consentimientos` (estado de suscripción por persona y canal), `adn_consentimiento_auditoria` (solo altas), `adn_consentimiento_textos` (textos versionados e inmutables, sin datos de nadie) y `adn_consentimiento_evidencias` (solo altas: qué texto aceptó cada registro por QR y qué valor traía el archivo importado) y `adn_bajas_enlaces` (solo servidor, secretos de un solo uso que no salen en la exportación). El panel de inicio lee de las tablas anteriores con `adn_panel_inicio`.
- **Datos de contacto adicionales:** `adn_miembro_contactos` (segundos correos, teléfonos extra, direcciones y etiquetas de un miembro, por ejemplo de una importación).

Las tablas nuevas de esta línea de trabajo llevan el prefijo `adn_` [regla de Gerencia]. Las existentes no se renombran hasta que Gerencia lo ordene.

Reglas para toda tabla nueva: `docs/MULTITENANT.md`, sección 5.

## 5. Rutas de la web

Públicas: `/bienvenida`, `/presentacion`, `/login`, `/registro`, `/reset-password`, `/aceptar` (invitación), `/dar/:slug`, `/checkin/:token` y `/verificar/:codigo`, `/baja/:token`, `/confirmar/:token` y los textos legales `/privacidad`, `/terminos`, `/aviso-legal` y `/cookies` [E, `src/router/index.ts`].

Con sesión: `/` (panel), `/miembros`, `/miembros/:id`, `/eventos`, `/eventos/:id`, `/casas`, `/consolidacion`, `/formacion`, `/formacion/programas`, `/comunicacion`, `/comunicacion/consentimientos`, `/reportes`, `/configuracion`, `/red` y `/plataforma` (solo administradores de plataforma) [E]. Cada entrada del menú aparece según los permisos del rol y los módulos de la iglesia [E, `AppLayout.vue`].

## 6. Funciones de borde

`plataforma` (gestión), `red-resumen`, `dar-publico`, `checkin-evento`, `registro-iglesia`, `invitaciones`, `verificar-certificado` y `baja` [E]. Son la única vía que cruza iglesias y la única que usa la clave de servicio, que vive en los secretos de la función y no en el repositorio.

## 7. Pendientes

Los seis trabajos en curso, en orden:

1. Ciclo de vida de la iglesia: hecho salvo activar la purga automática (diseñada y aprobada por Gerencia el 11 de noviembre; falta el secreto y la prueba en la rama de pruebas).
2. Exportación completa en CSV y JSON: hecho y verificado en base de datos (ver `docs/EXPORTACION.md`).
3. Importador de miembros con formato Google Contacts: hecho con datos sintéticos; falta probarlo con los archivos reales que entregue Gerencia.
4. Informes en PDF y Excel (miembros, asistencia, crecimiento): hecho y verificado (ver `docs/INFORMES.md`).
5. Panel de inicio completo y Comunicación con envío al buzón de pruebas y consentimiento por canal: hecho y verificado en base de datos (ver `docs/COMUNICACION.md`). Hechos el 11-11: pantalla de consentimientos con auditoría de solo altas, interruptor de baja por canal en la ficha y enlace público de baja de un solo uso, sin envío real (`docs/COMUNICACION.md`). El envío real sigue pendiente de proveedor, enlace de baja y aprobación del dueño.
6. Pruebas de aislamiento con dos usuarios de prueba: hecha y verificada a nivel SQL con los roles reales; la versión a través de la API está escrita y pendiente de ejecutarse contra PostgREST (ver `docs/AISLAMIENTO.md`).

**Requisitos previos al envío real de mensajes (Gerencia, 11-11):**

1. Crear un enlace de baja por destinatario y canal al enviar, con `adn_baja_crear_enlace`, y poner `https://<web>/baja/<secreto>` en el mensaje.
2. Desplegar la función de borde `baja` sin verificar el JWT, como `dar-publico`, y probarla de extremo a extremo.
2b. Encender la doble confirmación por correo (`docs/COMUNICACION.md`, apartado «Doble confirmación»): hoy está construida y apagada, y sin ella una persona nueva queda suscrita con la dirección que alguien escribió.
3. Límite de frecuencia en `baja` (opcional: no hace falta contra la fuerza bruta, pero frena el ruido).
4. Un proveedor aprobado por el dueño, base legal revisada por un abogado (`docs/COMUNICACION.md`, apartado 5) y consentimientos registrados. Re-suscribir a alguien exige un registro explícito con origen: quitar una baja lo deja en «sin dato».

**Textos legales:** versión 1 publicable en la rama, en cuatro idiomas (`docs/LEGAL.md`). Faltan los datos del titular (NIF, domicilio, correos), la revisión del abogado y la aprobación de Harold para desplegar. El registro por QR es la versión v2, con una casilla por canal (`docs/COMUNICACION.md`).

**Monitorización:** ruta de salud y pantalla de error propia, escritas y probadas pero sin desplegar; falta elegir el vigilante y a quién se avisa (`docs/MONITORIZACION.md`).

**Purga programada y plazo de copias:** diseño aprobado en `docs/PURGA.md` (opción A, copias a 14 días, libro externo; texto legal en privacidad 1.2 y términos 1.1). Falta que Gerencia cree el secreto y verifique `pg_cron` y `pg_net` en la rama de pruebas, y configurar la rotación de copias. Sin eso, la purga de los 30 días sigue siendo manual.

**Copias y restauración:** hay un procedimiento para ensayar en la rama de pruebas y un ensayo local repetible de la base completa (`docs/RESTAURACION.md`). Falta ejecutarlo contra Supabase real y decidir la política de copias, la custodia de la clave y la copia de los archivos de Storage, que hoy no existe.

**Prioritaria antes de producción:** paginar la exportación o generar el ZIP en el servidor, porque hoy todo el paquete viaja en una sola respuesta y no se ha medido con iglesias de decenas de miles de filas (`docs/EXPORTACION.md`).

Del producto, sin fecha: cobro del plan, canal de envío real de mensajes y alertas, credencial con escáner, subdominio por iglesia, historial de cambios por iglesia y segundo factor obligatorio [E, `docs/MULTITENANT.md` y `docs/COBRO.md`].

## 8. Hallazgos de higiene del repositorio

- **[E] El repositorio es público y ya contiene identificadores de infraestructura** en `supabase/README.md` (nombre y referencia del proyecto de base de datos, región) y en `docs/MULTITENANT.md` (nombre del proyecto y región). Quitarlos del último commit no los borra del historial. Gerencia debe decidir si se reescribe el historial o si se acepta la exposición, y rotar lo que corresponda.
- **[E] `docs/COBRO.md` y `docs/MULTITENANT.md` describen datos de producción** (conteos de tablas, estado de despliegues). Es información operativa, no secretos, pero conviene moverla a un documento privado.
- **[E] Secretos en el historial:** se buscaron, en los 79 commits de todas las ramas, claves JWT, claves de Supabase y de Stripe, claves privadas, tokens de GitHub y de Slack, y archivos `.env`. No hay ninguna clave real: la única coincidencia es un marcador truncado en `.env.example`, y `.env` nunca se subió. Las direcciones de correo del repositorio son de prueba, salvo un contacto público de la empresa.
- **[E, hallazgo de otro producto, 11-11] Cuentas creadas por SQL:** un NULL en columnas de texto de `auth.users` (`email_change`, etc.) rompe el inicio de sesión del servicio de Supabase. Hay una comprobación en `supabase/tests` para la rama de pruebas (`supabase/README.md`).
- [NV] La búsqueda cubre el historial local. No cubre las solicitudes de unión cerradas ni los comentarios de GitHub.

## 9. Cómo repetir las pruebas

Todo lo marcado **[E]** se repite con estos comandos, desde la raíz del repositorio. Los de base de datos necesitan un Postgres local y recrean la base `viveadn_pruebas`; nunca apuntarlos a una base real.

| Qué | Comando |
| --- | --- |
| Batería SQL completa: permisos, aislamiento total, ciclo de vida, exportación, importación, informes, comunicación, consentimiento, evidencia, doble confirmación, purga programada, descargas, panel, reversión de las catorce migraciones `adn_*` y comprobación de NULL en `auth.users` | `PGUSER=postgres supabase/tests/ejecutar.sh` |
| Exportación recargada en dos bases vacías (JSON y CSV) | `PGUSER=postgres supabase/tests/exportacion_carga.sh viveadn_pruebas` |
| Reversión de las migraciones `adn_*` | `PGUSER=postgres supabase/tests/adn_reversion.sh` |
| Restauración de la base completa en una base vacía, con comparación fila a fila | `PGUSER=postgres supabase/tests/restauracion_base_completa.sh` |
| Ciclo de vida, exportación, contactos de Google y Wix, informes (archivos con lectores independientes) | `npm run test:ciclo`, `test:exportacion`, `test:google`, `test:informes` |
| Secretos en todo el historial y en los archivos actuales (solo imprime recuentos) | `scripts/buscar-secretos.sh` |
| Tipos, compilación y los cuatro idiomas | `npm run type-check`, `npm run build-only`, `npm run check:idiomas` |
| El texto de consentimiento de la web es el que consta en la base (versión v1, cuatro idiomas) | `npm run check:textos` |
| Textos legales: mismos cuatro idiomas, estructura y huella de versión | `npm run check:legal` |
| Datos del titular completos antes de publicar (no imprime valores) | `npm run check:config-legal` |
| Doble confirmación: correo, baja de un clic y lectura de la petición (no envía) | `npm run test:confirmacion` |
| Ruta de salud y estado de error de la aplicación | `npm run test:salud`, `npm run test:error` |
| Ensayo de un archivo de contactos real, solo cifras | `node scripts/resumen-contactos-google.mts <archivo fuera del repositorio>` |
| Aislamiento por API (necesita PostgREST real y una base de pruebas) | `supabase/tests/aislamiento_api.sh <base>` (**[NV]**: no se ha ejecutado) |

Sin prueba repetible no hay **[E]**: lo que no la tiene está marcado **[NV]** o **[H]**.
