# Comunicación y panel de inicio

Estado a 11 de noviembre de 2026. Etiquetas de evidencia (carta de gerencia, 11-11): **[V]** comprobado por Gerencia, **[E]** informado por Desarrollo con una prueba repetible (el comando está en «Cómo repetir las pruebas», `docs/CONTEXTO.md`), **[H]** deducido, **[NV]** no verificable.

## 1. Qué hace y qué no hace

La pantalla de Comunicación redacta un mensaje, calcula con la base de datos quiénes lo recibirían, lo registra y deja el resultado en un historial. **No envía nada a nadie** [E]: cada mensaje se guarda en un buzón de pruebas, que son las tablas `adn_mensajes` y `adn_mensaje_destinatarios`. El destinatario de cada fila es la dirección o el teléfono al que habría ido, y `texto_final` es el texto ya personalizado con su nombre.

La garantía de que no sale nada no depende del código de la web: la columna `proveedor` de `adn_mensajes` solo admite el valor `sumidero` por una restricción de la tabla, y ninguna función llama a un servicio externo [E, `supabase/tests/adn_comunicacion.sql`]. Activar un proveedor real exige una migración nueva, y esa migración necesita la aprobación expresa del titular de la plataforma.

## 2. Reglas del envío

| Regla | Detalle |
| --- | --- |
| Canales | Correo y WhatsApp. La notificación dentro de la app no existe y no se ofrece [E] |
| Grupos | Todos, nuevos (creados en los últimos 30 días), líderes y en consolidación |
| Permisos | Ver el historial pide `comunicacion.ver`. Enviar pide `comunicacion.enviar` y `miembros.ver`. Ambos permisos se siembran en administrador y coadministrador, también en las iglesias que ya existen [E] |
| Personalización | `{{nombre}}`, `{{iglesia}}` y `{{dia}}` |
| Bajas | Una baja por canal aplica a la persona y también a la dirección compartida con otra persona de la misma iglesia (por ejemplo, un correo familiar) [E] |
| Repetidos | Si varias personas comparten una dirección, el mensaje se registra una sola vez para esa dirección |
| Consentimiento | **Solo recibe quien consta como `suscrito` en ese canal** (tabla `adn_consentimientos`, por persona y canal). Quien no tiene registro, o consta como `nunca`, `cancelado` o `sin_dato`, se omite con el motivo `sin_consentimiento`. WhatsApp tiene su propio consentimiento: el de correo y el de SMS no lo habilitan, y ningún archivo importado trae el de WhatsApp [E, `adn_consentimiento.sql`] |
| Suscripción cancelada | Como una baja, protege también a otra persona que comparta la dirección [E] |
| Sin destino | Quien no tiene correo, o teléfono para WhatsApp, queda registrado como omitido con ese motivo |
| Idempotencia | Cada envío lleva una clave. Repetir la misma petición devuelve el resultado anterior y no duplica nada [E] |
| Topes | 20 mensajes al día por iglesia y 2.000 destinatarios por mensaje [E] |
| Aislamiento | Cada iglesia solo ve su historial. Las personas autenticadas no pueden escribir en las tablas de mensajes: solo la función de envío las llena [E] |

La función de envío vive en el esquema `private` y la web llama a un envoltorio público sin privilegios propios, porque las pruebas prohíben `SECURITY DEFINER` en `public`.

## 3. Panel de inicio

La función `adn_panel_inicio` devuelve en una sola llamada: miembros activos, nuevos en 30 días frente a los 30 anteriores, sin casa de oración y bautizados; asistencia de la semana actual y de la anterior con la serie de ocho semanas; los cinco próximos eventos; los cumpleaños de los próximos 14 días; formación en curso, completada y certificados del mes; mensajes del buzón de pruebas y crecimiento de seis meses [E, 24 comprobaciones en `supabase/tests/adn_panel_inicio.sql`].

Corre con los permisos de quien la llama, de modo que las políticas de seguridad por filas recortan las cifras según su rol. Un líder sin personas asignadas ve ceros, y un visitante recibe un rechazo [E]. La web además oculta cada bloque cuando el rol no tiene el permiso del módulo correspondiente.

Los casos de calendario están probados: el 29 de febrero se celebra el último día de febrero en los años no bisiestos, y los cumpleaños de finales de diciembre aparecen a principios de enero [E].

### Pantalla de consentimientos, baja por canal y enlace de baja

- **Pantalla de consentimientos** (`/comunicacion/consentimientos`): busca miembros, muestra su estado por canal (correo, SMS, WhatsApp) con origen y fecha, y permite registrar un consentimiento eligiendo canal, estado y origen (formulario, papel firmado, de palabra, manual). Solo la ve quien tiene `comunicacion.ver` o `comunicacion.enviar`, y solo edita quien tiene `comunicacion.enviar`. Registrar exige ese mismo permiso en la base de datos, no solo en la pantalla [E, `adn_consentimiento.sql`].
- **Auditoría de solo altas** (`adn_consentimiento_auditoria`): cada cambio de consentimiento, venga de la pantalla, de una importación, de una baja o de un enlace, deja una fila con quién, cuándo, canal, estado anterior y nuevo, y origen. Repetir el mismo estado no deja fila. Nadie la inserta, modifica ni borra desde la web, y un disparador impide modificarla incluso al servicio; solo desaparece al borrar la iglesia [E]. Se muestran las últimas 30 entradas en la pantalla.
- **Interruptor de baja en la ficha del miembro**, por canal: deja el canal en `cancelado`. La importación no puede deshacerlo (solo endurece). Quitar una baja es una decisión de una persona con permiso, queda anotada y deja al miembro en «sin dato»: no recibe nada hasta que se registre un consentimiento nuevo [E].
- **Enlace público de baja de un solo uso** (`/baja/<secreto>`): el secreto tiene 244 bits aleatorios y la base guarda solo su huella SHA-256 [E]. Solo el servicio los crea (`adn_baja_crear_enlace`) y los consume (`adn_baja_consumir`, a través de la función de borde pública `baja`); ni una persona autenticada ni un visitante pueden llamar a esas funciones ni leer la tabla [E]. El segundo uso, un secreto inválido o uno caducado se rechazan sin dar pistas sobre la persona ni la iglesia, y no cambian nada [E]. Abrir el enlace no lo gasta: la página pide una confirmación y es ella quien da de baja, para que un analizador de correo que «visita» los enlaces no dé de baja a nadie. La baja del enlace deja a la persona en `cancelado` en ese canal, anotado como enlace y sin usuario.
- **Evidencia del consentimiento** (`adn_consentimiento_evidencias`, solo altas, la lee quien tiene permiso de comunicación) [E, `adn_consentimiento_evidencia.sql`, 40 comprobaciones]. Es prueba de lo que ocurrió; **no concede ni quita consentimiento** y no cambia a quién se envía. Hay dos tipos de fila:
  - *Registro por QR*: cada registro, también el de una persona que ya existía, deja una fila con la versión del texto aceptado, el idioma, la huella SHA-256 de ese texto, el evento y la fecha. Los textos viven en `adn_consentimiento_textos` (versión `v1` en los cuatro idiomas), que ni el servicio puede editar ni borrar: cambiar una palabra exige una versión nueva, y `npm run check:textos` falla si la web muestra un texto distinto del registrado. La versión y el idioma los afirma la página; si no constan en la tabla se anota `sin_version` y no se inventa una huella. Quien se registra por QR **sigue sin recibir mensajes** hasta que conste un consentimiento (comprobado).
  - *Importación*: junto al estado que se aplica se guarda el valor tal como venía en el archivo (por ejemplo, «Suscripción cancelada»), el estado que resultó de interpretarlo (vacío si no se entendió), si cambió el consentimiento y de qué importación viene. Un valor que no se entiende se conserva como texto y no crea consentimiento. El texto se limpia de saltos y espacios repetidos y se recorta a 60 caracteres. Reimportar un archivo que dice «suscrito» sobre una persona cancelada deja la evidencia como no aplicada y el consentimiento sigue cancelado.
  - Borrar a un miembro borra sus evidencias, como borra sus consentimientos. La evidencia sale en la exportación de la iglesia; los textos no, porque no llevan datos de nadie.
  - **Registro por QR v2 (decisión de Harold, 11-11)**: el texto base ya no habla de «contactarme»: dice «Acepto que {iglesia} guarde estos datos para registrar mi asistencia y acompañarme tras mi visita». El consentimiento de mensajes se pide aparte, con **una casilla por canal (correo, WhatsApp y SMS), sin marcar de antemano**, cada una con su texto versionado en cuatro idiomas (`adn_consentimiento_textos`, finalidades `checkin`, `checkin_email`, `checkin_whatsapp` y `checkin_sms`, versión v2). Registrarse sin marcar ninguna es válido. La v1 se conserva: es lo que aceptó quien se registró antes y sigue sin concederse ningún canal por ella [E, `adn_checkin_canales.sql`, 25 comprobaciones].
  - Cada casilla marcada deja su evidencia (texto, versión, huella, idioma, evento y fecha). **Solo una persona nueva queda suscrita** al canal marcado (origen `qr`, con auditoría y sin usuario). A una persona que ya existía no se le cambia el consentimiento y la casilla queda anotada como no aplicada: un correo o un teléfono escritos en un formulario público no prueban quién es, y de otro modo cualquiera podría suscribir o reactivar a otra persona, o deshacer una baja. Una casilla sin una versión de texto verificable en la tabla queda anotada como `sin_version` y no concede nada. El correo exige haber escrito un correo. [E]
  - **Riesgo y su remedio**: sin más, una persona nueva queda suscrita con la dirección que alguien escribió. La **doble confirmación por correo** (siguiente apartado) lo resuelve, está construida y **apagada por defecto**; debe encenderse antes de cualquier envío real.

### Doble confirmación por correo (apagada por defecto)

Pedida por Gerencia con el modelo de Vivepase, que no está en este repositorio: lo que sigue implementa lo que Gerencia describió (solicitud pendiente, enlace de un solo uso con huella y caducidad, botón de confirmar para que una vista previa no lo gaste, baja de un clic con cabeceras List-Unsubscribe), no una copia de aquel proyecto [E, `adn_doble_confirmacion.sql`, 52 comprobaciones; `npm run test:confirmacion`].

- **Interruptor**: el ajuste `adn_doble_confirmacion` de la plataforma, en `false`. Apagado, el registro por QR se comporta como hasta ahora (la casilla de correo de una persona nueva la suscribe). Encendido, la casilla **no concede nada**: crea una solicitud (`adn_confirmaciones`, solo servidor) y el consentimiento llega solo cuando la persona confirma. WhatsApp y SMS no tienen mecanismo de confirmación: encendido, no se conceden.
- **Enlace de un solo uso**: `adn_confirmacion_preparar` genera el secreto (244 bits), guarda solo su huella SHA-256 y fija la caducidad (3 días por defecto, entre 1 y 14); con el ajuste apagado no devuelve nada. Cada solicitud preparada crea además un enlace de baja de un solo uso para la cabecera del correo. Si el envío falla, `adn_confirmacion_fallida` devuelve la solicitud a «por enviar» sin secreto.
- **Confirmar** (`adn_confirmacion_consumir`, solo servidor): el segundo uso, un secreto inválido o uno caducado se rechazan sin dar pistas. **Solo concede el consentimiento si el canal no tiene registro o consta «sin dato»**: nunca deshace una baja ni un «nunca» (comprobado: una baja entre la solicitud y la confirmación sigue siendo baja, y la respuesta es la misma). Queda en la auditoría (origen `qr_confirmado`, sin usuario) y como evidencia de tipo `confirmacion`.
- **Página `/confirmar/<secreto>`**: pide pulsar un botón y es el botón quien confirma, de modo que abrir el enlace o su vista previa no gasta nada. Comprobado en un Chromium real: 0 llamadas al abrir, 1 al pulsar, y los tres desenlaces (confirmado, ya usado, caducado). [E]
- **Correo** (`supabase/functions/enviar-confirmaciones`): cuatro idiomas, con la confirmación, la caducidad, la baja y las cabeceras `List-Unsubscribe` (una sola dirección https a la función `baja`) y `List-Unsubscribe-Post: List-Unsubscribe=One-Click`. La función `baja` acepta esa baja de un clic (POST con el cuerpo exacto de la RFC 8058) además del flujo de la página. Lo que viene de una persona (iglesia, nombre) se limpia contra la inyección de cabeceras y se escapa en el HTML. [E, `npm run test:confirmacion`, con cuatro fallos introducidos a propósito y detectados]
- **Tres cerrojos independientes** en el envío: la clave de la tarea programada (`ADN_CRON_SECRET`, sin ella responde 403), el interruptor `ADN_CONFIRMACION_ACTIVA=1` de la función (sin él no toca la base de datos) y el ajuste de la base. Además necesita `BIRD_API_KEY`. Nadie la llama hoy: no hay tarea programada y nada se ha desplegado.
- **No probado [NV]**: ningún envío real; que el proveedor acepte `headers` con `List-Unsubscribe` en el campo que usa la función (no se ha consultado su documentación); que la baja de un clic funcione desde Gmail u Outlook, que además exigen firmas de dominio (SPF, DKIM) y una cabecera firmada; las funciones de borde solo pasaron la comprobación de tipos.
- **Para activarla**: desplegar `confirmar-suscripcion` sin verificar el JWT, y `enviar-confirmaciones` con `ADN_CRON_SECRET` y `BIRD_API_KEY`; programar su llamada cada pocos minutos; definir `ADN_CONFIRMACION_ACTIVA=1` y `ADN_WEB_URL`; poner el ajuste en `true`; y probar de extremo a extremo en la rama de pruebas con un buzón controlado. Verificar los dominios de envío (`docs/COMUNICACION.md`, apartado 5).
  - Límite **[NV]**: la evidencia del QR depende de lo que envía la página; un cliente manipulado podría afirmar una versión que no mostró. La huella siempre es la de un texto registrado, nunca una inventada, pero la base no puede comprobar qué vio la persona.
- **No hay envío real**: nada crea ni envía todavía esos enlaces. Cuando exista un proveedor, el envío debe crear un enlace por destinatario y canal con `adn_baja_crear_enlace` y poner `https://<dirección de la web>/baja/<secreto>` en el mensaje. El secreto no se guarda, así que no se puede reconstruir después. El buzón de pruebas no incluye enlaces para no dejar secretos en un historial legible.
- **[NV]** La función de borde `baja` solo pasó la comprobación de tipos; no se ejecutó de extremo a extremo. Hay que desplegarla sin verificar el JWT, como `dar-publico`, y la página de baja no se abrió en un navegador real. Tampoco hay límite de frecuencia: no hace falta frente a la fuerza bruta (244 bits), pero sí conviene si se quiere frenar el ruido.

### Efecto del consentimiento estricto

Un miembro creado a mano no tiene registro de consentimiento, así que hoy **no recibiría nada** hasta que alguien lo registre. Es la opción prudente mientras se decide la base legal (apartado 5). El registro se hace desde la pantalla de consentimientos, con la función `adn_registrar_consentimiento`, que exige `comunicacion.enviar` y puede dejar cualquier estado. La vista previa avisa de cuántas personas se omiten por falta de consentimiento.

## 4. Límites

- **[NV]** Las pantallas nuevas se compilaron y pasaron la comprobación de tipos, pero no se abrieron en un navegador contra una base real.
- **[NV]** (resuelto el 11-11: hay pantalla de consentimientos e interruptor de baja en la ficha) Ya no falta la forma de dar de baja a un miembro: la tabla de bajas y sus permisos existen y están probados, pero falta el interruptor en la ficha del miembro.
- El buzón no registra aperturas, rebotes ni respuestas, porque no hay envío real.
- El tope de 20 mensajes al día y el de 2.000 destinatarios son decisiones de seguridad mientras no haya proveedor. Un proveedor real puede exigir otros.

## 5. Antes de enviar de verdad

Estas son deducciones, no asesoría jurídica. Un abogado debe confirmarlas [H].

1. **Consentimiento y base legal.** En la Unión Europea, el Reglamento General de Protección de Datos trata los datos de pertenencia religiosa como categoría especial. Mensajes a miembros necesitan una base legal documentada, normalmente el consentimiento o el interés legítimo de una entidad religiosa respecto a sus propios miembros. En España, la Ley de Servicios de la Sociedad de la Información exige además consentimiento previo para comunicaciones comerciales por correo.
2. **Baja visible.** Todo correo debe llevar un enlace de baja que funcione sin iniciar sesión. Hoy existe la tabla de bajas, pero no el enlace público: hay que construirlo antes de activar un proveedor.
3. **WhatsApp.** La API oficial exige un número verificado y plantillas aprobadas por Meta para los mensajes que se inician fuera de una conversación abierta. El texto libre del redactor no sirve tal cual.
4. **Proveedor y remitente.** Hay que elegir proveedor, verificar el dominio de envío con sus registros de autenticación y definir quién responde a los mensajes.
5. **Aprobación.** La migración que habilite un proveedor distinto de `sumidero` necesita la aprobación del titular de la plataforma, y el primer envío real debería hacerse a una lista de pocas personas conocidas.
