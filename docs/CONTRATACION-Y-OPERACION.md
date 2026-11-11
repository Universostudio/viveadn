# Contratación y operación del servicio

Estado a 11 de noviembre de 2026. Describe cómo una iglesia pasa a ser cliente de Vive ADN, qué recibe, qué obligaciones tiene cada parte y cómo se opera el servicio durante su vida y al terminar. Es el documento de contratación y operación; no es un contrato ni asesoramiento jurídico. Cada campo que depende de Harold o de un abogado consta como **«le diré»** y se recoge en `docs/PENDIENTES-PRODUCCION.md`: no bloquea nada en el entorno de pruebas, que se comporta como un producto real. Etiquetas de evidencia: **[E]** informado por Desarrollo con una prueba repetible, **[H]** deducido, **[NV]** no verificable desde aquí.

## 1. Partes y roles

| Parte | Quién es | Papel |
| --- | --- | --- |
| Proveedor del servicio | Visualiza Studio, Sevilla | Titular de Vive ADN y **encargado del tratamiento** de los datos de las iglesias |
| Cliente | Cada iglesia | **Responsable del tratamiento** de los datos de sus miembros y asistentes |
| Personas interesadas | Miembros y asistentes de cada iglesia | Titulares de los datos |

Datos fiscales y de contacto del proveedor (NIF, domicilio, correo legal y de soporte, inscripción registral si existe): **«le diré»**. Mientras tanto, los textos legales muestran un marcador visible en lugar de un dato inventado [E].

## 2. Qué se contrata

Tres planes, definidos en el catálogo de la base de datos [E, `supabase/schema/seed.sql`]:

| Plan | Límites | Contenido |
| --- | --- | --- |
| Semilla | 50 miembros y 3 usuarios | El núcleo del sistema: miembros, casas de oración, zonas, asistencia, consolidación 72 horas, identidad, usuarios y roles |
| Básico | 300 miembros y 10 usuarios | El núcleo más formación, reportes y comunicación por correo |
| Premium | Hasta 5.000 miembros, sin tope de usuarios | Todo lo disponible. Más de 5.000, plan a medida |

Se añaden como complementos, **[H: según cómo se clasifican en el catálogo, que los marca como especiales]**, la App con marca propia, las Credenciales con foto y QR y la Consolidación por etapas. Los límites los hace cumplir la base de datos: al alcanzarlos, el alta se rechaza con `PLAN_LIMITE` [E].

**Precios, condiciones de pago, duración y renovación, y condiciones de reembolso: «le diré».** El modelo de cobro está diseñado en `docs/COBRO.md` y no hay cobros ni pasarela en el entorno de pruebas ni se construyen.

## 3. Alta del cliente

1. **Solicitud.** La iglesia pide acceso al equipo de Vive ADN. Contacto comercial: «le diré».
2. **Código de acceso.** Durante la etapa de pruebas el registro exige un código que crea el equipo desde el panel (`docs/MANUAL-PLATAFORMA.md`, apartado 3). Se entrega a la persona de contacto de la iglesia.
3. **Registro.** La persona de contacto registra la iglesia en `/registro` y se convierte en su superadministrador. Recibe un correo para crear su contraseña.
4. **Segundo superadministrador.** La plataforma exige siempre dos. Hasta que se invite al segundo, el panel de inicio lo recuerda [E].
5. **Aceptación de los términos.** El registro lleva el consentimiento a los términos y a la política de privacidad **[NV: el texto exacto de la casilla y el momento en que se registra la aceptación no se han revisado en esta tarea]**.
6. **Carga de datos.** La iglesia importa a sus personas (`docs/MANUAL-IGLESIAS.md`, apartado 4) o las da de alta una a una.

Una iglesia puede entrar también por alta directa desde el panel, o como iglesia de demostración con datos sintéticos.

## 4. Qué obligaciones tiene cada parte

**Vive ADN, como encargada.** Trata los datos solo por cuenta de la iglesia y siguiendo sus instrucciones; aplica las medidas de seguridad descritas en la política de privacidad; recurre solo a los proveedores necesarios para prestar el servicio, con las mismas obligaciones de protección de datos; ayuda a la iglesia a atender los derechos de las personas y le traslada las solicitudes que reciba; notifica sin dilación indebida las violaciones de seguridad; y al terminar el servicio suprime o devuelve los datos. Estas condiciones recogen los apartados a a h del artículo 28.3 del RGPD y están en los términos de uso, con su revisión jurídica pendiente: **«le diré»** (`docs/LEGAL.md`).

**La iglesia, como responsable.** Decide para qué usa los datos, obtiene el consentimiento de cada persona (en especial para los datos de pertenencia a una comunidad religiosa, que son de categoría especial), registra ese consentimiento por canal y respeta las bajas, mantiene al menos dos superadministradores, y custodia los informes que descarga: el de miembros contiene datos personales.

## 5. Operación durante el servicio

| Tema | Cómo se hace | Referencia |
| --- | --- | --- |
| Soporte | Por el correo de soporte: **«le diré»**. Horarios y plazos de respuesta: **«le diré»** | |
| Cambios de plan y de módulos | Los hace el equipo desde el panel y quedan auditados | `docs/MANUAL-PLATAFORMA.md`, apartado 4 |
| Disponibilidad | Ruta de salud y verificación del entorno. Un compromiso de nivel de servicio: **«le diré»** | `docs/MONITORIZACION.md` |
| Copias de seguridad | Copias de la plataforma según el plan, y copias propias a 14 días; la configuración real consta como **[NV]** | `docs/RESTAURACION.md` |
| Nuevas versiones | Las publica el equipo; si una página estaba abierta, la persona ve el aviso de recargar | `docs/MONITORIZACION.md` |
| Envío de mensajes | Apagado en pruebas. Su activación exige proveedor aprobado, dominio verificado y base legal revisada: **«le diré»** | `docs/COMUNICACION.md` |
| Incidencias de seguridad | Aviso a la iglesia sin dilación indebida; procedimiento interno de notificación: **«le diré»** | `docs/MANUAL-PLATAFORMA.md` |

## 6. Terminar el servicio

1. La iglesia lo pide al equipo (en pruebas, desde Configuración, pestaña Seguridad, apartado «Tus datos y la baja»).
2. Se **exporta** y se entrega el paquete de todos sus datos en JSON y CSV, con la huella de cada tabla (`docs/EXPORTACION.md`).
3. Se **borra con plazo**: la cuenta queda suspendida y recuperable durante 30 días.
4. Pasado ese plazo se **purga** por completo: base de datos, archivos y cuentas de acceso, con un rastro mínimo y sin datos personales.
5. Los datos desaparecen de los sistemas activos a los 30 días de la baja y de las copias de seguridad en un máximo de 14 días más. **Esa promesa solo es cierta cuando la purga programada está activa y la rotación de copias está configurada y demostrada [NV]**, y consta como pendiente de confirmar con la configuración real de las copias de la plataforma y de la revisión del abogado.
6. Si más tarde se restaura una copia anterior a la purga, se aplica el libro externo de purgadas antes de abrir la base, para que la iglesia no reaparezca (`docs/PURGA.md`, apartado 4).

## 7. Transferencias y ubicación de los datos

Los datos se alojan en la región `eu-west-1`, situada en la Unión Europea. Algunos proveedores pertenecen a grupos con sede fuera del Espacio Económico Europeo; en ese caso las transferencias se apoyan en las garantías del capítulo V del RGPD, como una decisión de adecuación o las cláusulas contractuales tipo. La lista actualizada de subencargados se facilita a quien la pida al correo legal: **«le diré»**.

## 8. Datos que faltan para firmar o publicar

Todos están en `docs/PENDIENTES-PRODUCCION.md` y llevan **«le diré»**: datos del titular, precios y condiciones comerciales, correo y horario de soporte, nivel de servicio, procedimiento de notificación de incidentes, revisión jurídica de los términos y del contrato de encargo, y dirección definitiva de producción. Ninguno impide ensayar el servicio completo en pruebas.
