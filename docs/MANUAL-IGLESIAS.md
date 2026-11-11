# Manual de operación para iglesias

Estado a 11 de noviembre de 2026. Es el manual de quien lleva una iglesia en Vive ADN: cómo entrar, qué hace cada pantalla y cómo resolver lo habitual. Incluye las guías de importación, de exportación y de informes. Describe lo que la aplicación hace hoy: donde algo aún no existe, se dice. Los datos de contacto del equipo de Vive ADN y las condiciones comerciales no están en este manual hasta que se confirmen: figuran como «le diré» en `docs/PENDIENTES-PRODUCCION.md`. La aplicación está en la etapa de pruebas.

## 1. Antes de empezar

**Quién puede hacer qué.** Cada persona entra con su correo y su contraseña (al menos 10 caracteres). Lo que ve y puede hacer depende de su rol. Los roles de partida son Superadministrador, Co-administrador, Líder de zona y Colaborador, y la iglesia puede crear otros con los permisos que quiera desde Configuración. El Colaborador registra asistencia y nuevos convertidos y ve solo lo que registra. El Líder de zona ve las casas de su zona, sus miembros, la consolidación y la asistencia. Una pantalla que no aparece en tu menú es una pantalla para la que tu rol no tiene permiso.

**Siempre dos superadministradores.** La plataforma exige que la iglesia tenga al menos dos, para que nunca pierda el acceso. Mientras falte el segundo, el panel de inicio te lo recuerda con el botón «Invitar ahora». No se puede bajar de dos ni dejar la iglesia sin ninguno.

**Idioma.** La aplicación está en español, inglés, francés y portugués de Brasil, y los informes salen en el idioma de quien los descarga.

## 2. Primer día

1. **Registrar la iglesia.** Entra en la dirección de registro (`/registro`). Durante la etapa de pruebas hace falta un código de acceso que te entrega el equipo de Vive ADN. Indica el nombre de la iglesia, su dirección corta (identifica a la iglesia, por ejemplo en la página de dar), país y ciudad, tu nombre y apellido, tu correo y el código. Tu cuenta nace como superadministrador.
2. **Crear tu contraseña.** Recibes un correo para crearla, de modo que tu dirección queda comprobada. Si no llega, mira la carpeta de spam. En la etapa de pruebas puede que el equipo te entregue el enlace directamente.
3. **Completa la identidad** en Configuración, pestaña Iglesia: nombre, país y ciudad sede y correo de contacto.
4. **Invita al segundo superadministrador** y al resto del equipo (apartado 13).
5. **Carga a tu gente**: con «Nuevo miembro» uno a uno o con «Importar» de golpe (apartado 4).

## 3. Panel de inicio

Muestra el total de miembros, las casas de oración, las personas en consolidación y las alertas críticas, la asistencia de las últimas semanas con su variación frente al periodo anterior, el crecimiento y los miembros nuevos. Cada cifra lleva a su pantalla. Si no se pueden cargar, lo dice en lugar de mostrar ceros.

## 4. Miembros

**Alta.** «Nuevo miembro» pide nombre y apellido; correo, teléfono (WhatsApp), casa de oración y nivel de compromiso son opcionales. La lista se filtra por nivel y por activos o inactivos, y se busca por nombre, correo o código. Abre una ficha con «Ver perfil».

**Límites del plan.** Cada plan tiene un tope de miembros y de usuarios. Al alcanzarlo, la aplicación rechaza el alta con el aviso `PLAN_LIMITE`: no hay excepciones silenciosas. Los planes son Semilla (50 miembros y 3 usuarios), Básico (300 y 10) y Premium (5.000 miembros y sin tope de usuarios); más de 5.000, plan a medida.

### Guía de importación

El botón «Importar» de Miembros acepta tres tipos de archivo CSV y reconoce el tipo solo:

- **La plantilla de Vive ADN.** Pulsa «Descargar plantilla». Cada fila necesita al menos nombre y apellido; admite correo, teléfono, fecha de nacimiento, género, nivel de compromiso y notas. Las fechas van como AAAA-MM-DD o DD/MM/AAAA.
- **Google Contactos y Outlook.** Súbelo tal como lo exporta el programa. Lee nombre, correos, teléfonos, cumpleaños con año, direcciones y etiquetas.
- **Wix.** Se reconoce por la columna «Estado de suscriptor por email». Además de los datos de contacto, lee el estado de suscripción por correo y por SMS como consentimiento (apartado 8).

**Antes de importar ves un resumen y no se guarda nada hasta que lo confirmes**: cuántas filas están listas, cuáles ya existen, cuáles tienen errores (con su línea) y qué columnas se ignoran.

**Reglas que debes conocer.**

1. **Nunca se importan contraseñas.** Una columna que parece una clave se ignora y se te avisa para que la borres del archivo. Una nota que parece guardar una clave se descarta.
2. **Se evitan los duplicados.** Dos filas con el mismo correo son la misma persona y se fusionan. Sin correo se usa el teléfono; sin teléfono, el nombre. Lo que ya existe en tu iglesia no se duplica.
3. **Un dato inválido no invalida a la persona.** Un teléfono o un correo mal formados se descartan y se cuentan; la persona se importa igual.
4. **Las filas sin nombre ni contacto se descartan.** Las que tienen contacto pero no nombre quedan aparte y solo entran si tú lo marcas.
5. **Cada persona importada lleva una etiqueta** con la fecha y el origen, para poder encontrar lo que entró de una vez.
6. **Máximo de filas por archivo:** si te pasas, divídelo. Si la importación se corta, lo ya importado se conserva: vuelve a subir el archivo y los repetidos se omiten.
7. Una iglesia en modo alias no puede importar, porque guardaría nombres y correos reales.

El consentimiento al reimportar **nunca se relaja**: una baja del archivo se aplica aunque la persona ya existiera, y un archivo que diga «suscrito» no deshace una baja ni concede un consentimiento a quien no lo tenía.

## 5. Casas de oración y zonas

«Casas de Oración» lista tus casas con su zona, su líder y sus miembros, y permite crear nuevas con nombre, zona, país, ciudad y dirección. El código de la casa se genera solo, con la forma `ZN-849402`. Se filtra por zona y se busca por nombre, zona o líder. Cada casa tiene su ficha con sus miembros.

## 6. Eventos, asistencia y registro por QR

**Crear un evento.** «Nuevo evento» pide título, tipo (culto, casa de oración, formación, especial u otro), inicio, fin opcional, lugar y descripción. Con «Repetir cada semana» creas una serie de entre 2 y el máximo de reuniones. Un evento cancelado se marca como tal.

**Registro por QR.** Cada evento tiene un enlace y un código QR (`/checkin/<enlace>`) para que las personas se registren desde su móvil, sin cuenta. El registro se abre poco antes del evento y se cierra poco después de terminar; fuera de esa ventana la persona ve que está cerrado. Hay un tope de registros por evento y un límite por dispositivo para frenar abusos.

**Lo que ve la persona que se registra.** Nombre, y de forma opcional correo y teléfono, una declaración de que tiene 14 años o más o de que un tutor lo autoriza, y una casilla **por canal** (correo, SMS, WhatsApp) **sin marcar** para aceptar mensajes de la iglesia. Se le explica que la iglesia es la responsable de sus datos, que indican la asistencia a una comunidad religiosa, un dato especialmente protegido, y cómo ejercer sus derechos.

**Qué guarda Vive ADN.** Solo una **persona nueva** que marca un canal queda suscrita en ese canal, con origen QR. A una persona que ya existía no se le cambia el consentimiento: solo se guarda la evidencia de lo que marcó. Cada marca guarda el texto exacto que se le mostró, con su versión. La doble confirmación por correo existe pero está apagada (`docs/COMUNICACION.md`).

## 7. Consolidación 72 horas

Para cada nuevo convertido se registra el miembro, la fecha de conversión y notas. La pantalla muestra el progreso de las 72 horas, el límite, las horas transcurridas y el estado, y se ordena por urgencia, fecha o nombre. «Completar» cierra el seguimiento. Las consolidaciones pendientes aparecen en el panel como alertas, con las horas transcurridas desde la conversión.

## 8. Comunicación y consentimiento

**Quién recibe mensajes.** Solo recibe mensajes quien consta como **suscrito en ese canal**. Un miembro creado a mano no tiene registro de consentimiento, así que no recibe nada hasta que alguien lo registre. Los estados son: suscrito, sin dato, nunca suscrito y suscripción cancelada.

**Pantalla de consentimientos** (Comunicación, «Gestionar consentimientos»). Lista a las personas con su estado por canal, el origen (registro manual, formulario, papel firmado, de palabra, importado de Wix, baja registrada, enlace de baja u otro) y la fecha. Se busca por nombre o correo. Dar de baja y quitar una baja piden confirmación; **quitar una baja deja a la persona «sin dato»**, no suscrita, porque volver a suscribir a alguien exige un registro explícito con su origen. En la ficha de cada miembro hay un interruptor de baja por canal.

**Baja por enlace.** Cada mensaje real debe llevar un enlace de baja de un solo uso (`/baja/<secreto>`). La página pide una confirmación explícita antes de darse de baja, de modo que un analizador de correo que «visita» el enlace no puede gastarlo. Los programas de correo también pueden usar la baja de un clic.

**Redactar un mensaje.** «Nuevo mensaje» permite elegir los destinatarios (todos los miembros, nuevos de los últimos 30 días, líderes o en consolidación), partir de una plantilla (bienvenida, recordatorio o evento) y escribir el texto con variables como el nombre. **En la etapa de pruebas el envío va a un buzón de pruebas y no sale ningún mensaje a personas reales.** El envío real se activará cuando haya un proveedor aprobado y la base legal revisada.

## 9. Formación

La pantalla Formación muestra el progreso por nivel (Fundamentos, Crecimiento, Servicio, Liderazgo y Multiplicación). «Actualizar progreso» fija el porcentaje de un miembro en un nivel o lo marca como completado. Además, «Programas de formación» permite crear programas propios de la iglesia, con sus lecciones y el avance de cada alumno. Los certificados de formación llevan un código y un QR que cualquiera puede comprobar en `/verificar/<código>`: la página muestra el estado, la iglesia, el programa, la fecha y el titular reducido a su nombre y la inicial del apellido, y un certificado revocado no muestra al titular.

## 10. Dar

En Configuración, pestaña Dar, escribes la dirección web donde tu iglesia recibe diezmos, ofrendas y donaciones. **Vive ADN no procesa ni guarda pagos**: solo muestra un botón que abre ese sitio. Un campo vacío oculta su botón. La página pública `/dar/<la dirección de tu iglesia>` muestra los botones activos a cualquiera.

## 11. Reportes e informes

La pantalla Reportes muestra, para el periodo que elijas (semana, mes, trimestre o año), los miembros activos y nuevos, las consolidaciones y su tasa de éxito, las casas activas, los alumnos por nivel y la distribución por zona.

### Guía de informes

Abajo, «Descargar informes» genera tres informes en PDF o en Excel con los datos de tu iglesia. Solo incluyen lo que tu rol puede ver.

| Informe | Qué necesitas | Qué contiene |
| --- | --- | --- |
| Miembros | El permiso de exportar miembros | Resumen (total, activos, inactivos, bautizados, con correo, con teléfono, sin casa), cifras por nivel de compromiso y la lista completa de miembros |
| Asistencia | El permiso de ver reportes | De 4 a 52 semanas: porcentaje de asistencia, presentes por semana, y tablas por semana, por casa y por evento |
| Crecimiento | El permiso de ver reportes | De 6 a 36 meses: miembros registrados, nuevos, conversiones, bautizos y consolidaciones, con el acumulado |

Elige el informe, el periodo y el formato y pulsa descargar. **El informe de miembros contiene datos personales:** guárdalo en un lugar seguro y no lo compartas. Cada descarga de ese informe queda registrada en la iglesia (quién, cuándo y con qué periodo). Dos límites: en el PDF, los caracteres que no son del alfabeto latino salen como `?` (el Excel los conserva), y un texto que empieza por `=`, `+`, `-` o `@` se guarda en el Excel como texto y no como fórmula.

## 12. Red de iglesias

Si tu iglesia es la madre de otras sedes, la pantalla Red muestra cifras agregadas de tus sedes: miembros activos, casas, personas en consolidación y alertas críticas. Cada sede aparece según el acceso que la plataforma le haya concedido; con acceso «ninguno» solo se ve el nombre y la ciudad. **Nunca salen datos personales.**

## 13. Configuración

**Iglesia.** Nombre, país y ciudad sede, correo de contacto. La paleta de colores se podrá personalizar en una versión futura. Con «Registrar a las personas con un alias», las personas nuevas se guardan con un identificador interno, sin apellido ni correo, y se conserva el teléfono; los miembros que ya existen no cambian.

**Usuarios.** Muestra al equipo con su rol y permite cambiarlo si tu rol tiene permiso. «Invitar usuario» pide correo, nombre, apellido y rol. La invitación es un enlace de **un solo uso que caduca a los 15 días** y se muestra una sola vez: si se pierde, se crea uno nuevo. Si el envío de correo está activo, la persona lo recibe; si no, copia el enlace y envíaselo tú. Las invitaciones pendientes se pueden renovar o revocar.

**Seguridad.** Muestra las opciones de sesión y de privacidad. La autenticación de dos factores y las sesiones máximas aparecen como próximas. Las copias de seguridad dependen del plan de la base de datos.

## 14. Exportar tus datos

**Cómo se pide.** Hoy la exportación la entrega el equipo de Vive ADN: se pide desde Configuración, pestaña Seguridad, apartado «Tus datos y la baja». No hay todavía un botón que la genere por tu cuenta.

**Qué recibes.** Un archivo ZIP con tres tipos de contenido:

- `datos.json`: todos los datos de tu iglesia.
- `csv/<tabla>.csv`: un CSV por tabla (UTF-8, separador coma), que se abre en una hoja de cálculo.
- `manifest.json`: para cada tabla, el número de filas, las columnas y una huella para comprobar que el contenido está completo.

Entran 32 tablas: tu iglesia y todo lo que le pertenece. **No salen** los enlaces secretos (QR de eventos e invitaciones), las huellas de dispositivo ni los datos de otras iglesias. Las cuentas de acceso no viajan: las personas deberán ser invitadas de nuevo si restauras los datos en otro sitio. Los archivos subidos (logos, documentos) no van en el ZIP: se entrega su listado para pedirlos aparte. **Aviso:** si abres un CSV en una hoja de cálculo, una celda que empiece por `=`, `+`, `-` o `@` puede interpretarse como una fórmula; el CSV conserva el texto tal cual y el ZIP lo advierte.

## 15. Dar de baja la iglesia

Se pide al equipo de Vive ADN, igual que la exportación. Conviene **exportar antes los datos**. Al darse de baja, la cuenta pasa a **borrado suave**: queda suspendida y se puede recuperar durante **30 días**. Pasado ese plazo, los datos de tu iglesia se borran por completo, con sus archivos y las cuentas de acceso del equipo. Según nuestros textos legales, los datos desaparecen de los sistemas activos a los 30 días de la baja y de las copias de seguridad en un máximo de 14 días más (esta cifra está pendiente de comprobarse con la configuración real de las copias). La plataforma conserva un registro de la fecha de baja, sin datos de personas.

## 16. Tus datos personales y los de tu gente

La iglesia es la **responsable** de los datos de sus miembros y Vive ADN actúa por su cuenta como encargada del tratamiento. Los términos de uso incluyen el contrato de encargo. Los datos de pertenencia a una comunidad religiosa son de categoría especial: guárdalos solo con el consentimiento de cada persona, atiende sus peticiones de acceso, corrección o borrado, y usa la pantalla de consentimientos para demostrar qué aceptó cada una. Las políticas completas están en la web, en `/privacidad`, `/terminos`, `/aviso-legal` y `/cookies`, y pendientes de revisión por un abogado.

## 17. Si algo no funciona

| Síntoma | Qué hacer |
| --- | --- |
| Una pantalla no aparece en el menú | Tu rol no tiene permiso, o el módulo no está en el plan de la iglesia. Pídelo a un superadministrador |
| «PLAN_LIMITE» al crear un miembro o un usuario | La iglesia llegó al tope de su plan. Pide cambiar de plan al equipo de Vive ADN |
| No llega un correo de invitación o de contraseña | Revisa spam. Si no llega, copia el enlace de invitación y envíaselo a la persona |
| El enlace de invitación dice que no es válido | Caducó a los 15 días o ya se usó. Crea uno nuevo |
| El registro por QR dice «cerrado» | Solo está abierto poco antes y poco después del evento |
| El registro por QR dice que se alcanzó el máximo | El evento llegó a su tope de registros. Pide ayuda al equipo |
| Una persona no recibe mensajes | Mira su consentimiento en el canal: solo recibe quien consta como suscrito |
| Aparece la pantalla «La aplicación se ha actualizado» | Se publicó una versión nueva mientras tenías la página abierta. Pulsa «Recargar la página» |
| La importación se detuvo | Lo ya importado se conserva. Vuelve a subir el archivo: los repetidos se omiten |
| Un informe da error de permiso o de periodo | Comprueba tu rol y que el periodo elegido es válido |
