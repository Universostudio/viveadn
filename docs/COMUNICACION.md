# Comunicación y panel de inicio

Estado a 11 de noviembre de 2026. Etiquetas: **[V]** verificado en esta sesión, **[H]** deducido, **[NV]** no verificable desde el repositorio.

## 1. Qué hace y qué no hace

La pantalla de Comunicación redacta un mensaje, calcula con la base de datos quiénes lo recibirían, lo registra y deja el resultado en un historial. **No envía nada a nadie** [V]: cada mensaje se guarda en un buzón de pruebas, que son las tablas `adn_mensajes` y `adn_mensaje_destinatarios`. El destinatario de cada fila es la dirección o el teléfono al que habría ido, y `texto_final` es el texto ya personalizado con su nombre.

La garantía de que no sale nada no depende del código de la web: la columna `proveedor` de `adn_mensajes` solo admite el valor `sumidero` por una restricción de la tabla, y ninguna función llama a un servicio externo [V, `supabase/tests/adn_comunicacion.sql`]. Activar un proveedor real exige una migración nueva, y esa migración necesita la aprobación expresa del titular de la plataforma.

## 2. Reglas del envío

| Regla | Detalle |
| --- | --- |
| Canales | Correo y WhatsApp. La notificación dentro de la app no existe y no se ofrece [V] |
| Grupos | Todos, nuevos (creados en los últimos 30 días), líderes y en consolidación |
| Permisos | Ver el historial pide `comunicacion.ver`. Enviar pide `comunicacion.enviar` y `miembros.ver`. Ambos permisos se siembran en administrador y coadministrador, también en las iglesias que ya existen [V] |
| Personalización | `{{nombre}}`, `{{iglesia}}` y `{{dia}}` |
| Bajas | Una baja por canal aplica a la persona y también a la dirección compartida con otra persona de la misma iglesia (por ejemplo, un correo familiar) [V] |
| Repetidos | Si varias personas comparten una dirección, el mensaje se registra una sola vez para esa dirección |
| Sin destino | Quien no tiene correo, o teléfono para WhatsApp, queda registrado como omitido con ese motivo |
| Idempotencia | Cada envío lleva una clave. Repetir la misma petición devuelve el resultado anterior y no duplica nada [V] |
| Topes | 20 mensajes al día por iglesia y 2.000 destinatarios por mensaje [V] |
| Aislamiento | Cada iglesia solo ve su historial. Las personas autenticadas no pueden escribir en las tablas de mensajes: solo la función de envío las llena [V] |

La función de envío vive en el esquema `private` y la web llama a un envoltorio público sin privilegios propios, porque las pruebas prohíben `SECURITY DEFINER` en `public`.

## 3. Panel de inicio

La función `adn_panel_inicio` devuelve en una sola llamada: miembros activos, nuevos en 30 días frente a los 30 anteriores, sin casa de oración y bautizados; asistencia de la semana actual y de la anterior con la serie de ocho semanas; los cinco próximos eventos; los cumpleaños de los próximos 14 días; formación en curso, completada y certificados del mes; mensajes del buzón de pruebas y crecimiento de seis meses [V, 24 comprobaciones en `supabase/tests/adn_panel_inicio.sql`].

Corre con los permisos de quien la llama, de modo que las políticas de seguridad por filas recortan las cifras según su rol. Un líder sin personas asignadas ve ceros, y un visitante recibe un rechazo [V]. La web además oculta cada bloque cuando el rol no tiene el permiso del módulo correspondiente.

Los casos de calendario están probados: el 29 de febrero se celebra el último día de febrero en los años no bisiestos, y los cumpleaños de finales de diciembre aparecen a principios de enero [V].

## 4. Límites

- **[NV]** Las pantallas nuevas se compilaron y pasaron la comprobación de tipos, pero no se abrieron en un navegador contra una base real.
- **[NV]** No hay forma en la pantalla de dar de baja a un miembro: la tabla de bajas y sus permisos existen y están probados, pero falta el interruptor en la ficha del miembro.
- El buzón no registra aperturas, rebotes ni respuestas, porque no hay envío real.
- El tope de 20 mensajes al día y el de 2.000 destinatarios son decisiones de seguridad mientras no haya proveedor. Un proveedor real puede exigir otros.

## 5. Antes de enviar de verdad

Estas son deducciones, no asesoría jurídica. Un abogado debe confirmarlas [H].

1. **Consentimiento y base legal.** En la Unión Europea, el Reglamento General de Protección de Datos trata los datos de pertenencia religiosa como categoría especial. Mensajes a miembros necesitan una base legal documentada, normalmente el consentimiento o el interés legítimo de una entidad religiosa respecto a sus propios miembros. En España, la Ley de Servicios de la Sociedad de la Información exige además consentimiento previo para comunicaciones comerciales por correo.
2. **Baja visible.** Todo correo debe llevar un enlace de baja que funcione sin iniciar sesión. Hoy existe la tabla de bajas, pero no el enlace público: hay que construirlo antes de activar un proveedor.
3. **WhatsApp.** La API oficial exige un número verificado y plantillas aprobadas por Meta para los mensajes que se inician fuera de una conversación abierta. El texto libre del redactor no sirve tal cual.
4. **Proveedor y remitente.** Hay que elegir proveedor, verificar el dominio de envío con sus registros de autenticación y definir quién responde a los mensajes.
5. **Aprobación.** La migración que habilite un proveedor distinto de `sumidero` necesita la aprobación del titular de la plataforma, y el primer envío real debería hacerse a una lista de pocas personas conocidas.
