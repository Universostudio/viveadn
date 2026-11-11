# Textos legales: versión 1, fuentes y pendientes

Estado a 11 de noviembre de 2026. Etiquetas de evidencia: **[E]** informado por Desarrollo con una prueba repetible, **[H]** deducido o citado de memoria y sin contrastar en esta sesión, **[NV]** no verificable desde aquí. Esto **no es asesoría jurídica**: Gerencia ordenó publicar una versión 1 sin esperar al abogado, que la revisará después.

## 1. Qué hay publicado en la web

| Documento | Ruta | Contenido |
| --- | --- | --- |
| Política de privacidad | `/privacidad` | Quién es responsable y quién encargado, datos y bases legales, registro por QR y comunicaciones, subencargados, conservación, derechos, seguridad |
| Términos de uso | `/terminos` | Condiciones del servicio, responsabilidad de la iglesia, uso aceptable, planes, baja y exportación, y el contrato de encargo del tratamiento (artículo 28 del RGPD) como anexo |
| Aviso legal | `/aviso-legal` | Datos del titular (artículo 10 de la LSSI), condiciones del sitio, propiedad intelectual, ley y jurisdicción |
| Política de cookies | `/cookies` | Qué guarda la web en el dispositivo y por qué no pide consentimiento |

Cada página existe en español, inglés, francés y portugués de Brasil, con enlaces en el pie de las pantallas públicas y del menú, versión y fecha visibles y un historial de versiones **[E]**. El registro de la iglesia enlaza la política y los términos junto a la casilla de consentimiento.

Reparto de papeles que reflejan los textos: **cada iglesia es responsable del tratamiento de sus miembros y visitantes; Vive ADN (el titular) es encargada** y actúa con el contrato de encargo del anexo. Vive ADN es responsable solo de los datos de las cuentas, de la seguridad y del soporte. Los textos describen también la baja, la exportación completa en JSON y CSV y el borrado con su plazo fijo de 30 días, tal como los hace hoy la plataforma **[E]** (`docs/MULTITENANT.md`, `docs/EXPORTACION.md`).

## 2. Datos del titular: configuración, nunca inventados

El titular es **Visualiza Studio, Sevilla**, según Gerencia. El resto no consta en ningún sitio del repositorio y se configura:

| Variable de la web | Dato | Estado |
| --- | --- | --- |
| `VITE_LEGAL_TITULAR` | Nombre del titular | Visualiza Studio (valor por defecto) |
| `VITE_LEGAL_NIF` | NIF | **Falta**, lo confirma Gerencia |
| `VITE_LEGAL_DOMICILIO` | Domicilio completo | **Falta** |
| `VITE_EMAIL_LEGAL` | Correo de privacidad y legal | **Falta** |
| `VITE_EMAIL_SOPORTE` | Correo de soporte | **Falta** |
| `VITE_LEGAL_REGISTRO` | Inscripción en un registro público, solo si existe | Vacío: el párrafo no se muestra |
| `ADN_EMAIL_SOPORTE` | Correo de soporte de la función de invitaciones | Reserva: el valor que ya usaba la función |

Si falta un dato, el documento muestra un aviso amarillo y el marcador `[dato pendiente de configurar]` en lugar de un valor inventado **[E]**. Antes de publicar, `npm run check:config-legal` falla si falta alguno o si un correo no tiene forma de correo, y no imprime los valores.

## 3. Versiones y control de cambios

El registro está en `src/legal/versiones.json`: por documento, versión, fecha, resumen y la huella SHA-256 del contenido en cada idioma. `npm run check:legal` **[E]** comprueba que:

- los cuatro idiomas tienen las mismas secciones, los mismos párrafos y listas y los mismos marcadores, sin guiones largos;
- el texto de cada documento e idioma coincide con la huella de su última versión. Cambiar una palabra sin crear una versión nueva hace fallar la comprobación (probado cambiando una palabra del inglés).

Para publicar una versión nueva: añadir una entrada en `versiones.json` con su número, fecha y resumen, editar los textos y ejecutar `npm run check:legal -- --registrar`.

El texto del registro por QR tiene su propio control: `npm run check:textos` y las tablas `adn_consentimiento_textos` y `adn_consentimiento_evidencias` (`docs/COMUNICACION.md`).

## 4. Fuentes consultadas

Consultadas en esta sesión, con texto recuperado de la fuente oficial **[E]**:

- **Ley 34/2002, de 11 de julio (LSSI)**, BOE-A-2002-13758, texto consolidado con última actualización de 23 de enero de 2025. Artículo 10.1 (información general: denominación, domicilio, correo, inscripción registral, NIF, precios, códigos de conducta), artículo 21 (prohibición de comunicaciones comerciales no solicitadas y obligación de ofrecer una dirección válida para oponerse) y artículo 22.2 (almacenamiento en el terminal del usuario: excepción para lo técnico y estrictamente necesario para un servicio expresamente solicitado). https://www.boe.es/buscar/act.php?id=BOE-A-2002-13758
- **Guía sobre el uso de las cookies, Agencia Española de Protección de Datos** (con ADIGITAL, Anunciantes, AUTOCONTROL e IAB Spain). Incluye entre las cookies exentas las de autenticación, las de seguridad, las de entrada del usuario y las de personalización de la interfaz, y recomienda informar de ellas aunque estén exentas. https://www.aepd.es/guias/guia-cookies.pdf
- **Ley Orgánica 3/2018 (LOPDGDD)**, BOE-A-2018-16673, texto consolidado con última actualización de 27 de diciembre de 2025: comprobado que existe y su versión; el texto literal de los artículos 7 y 11 **no** se recuperó.
- **Reglamento (UE) 2016/679 (RGPD)**, DOUE L 119, 4.5.2016, https://www.boe.es/doue/2016/119/L00001-00088.pdf y EUR-Lex CELEX 32016R0679: se descargó el documento, pero la extracción solo devolvió un fragmento (artículo 9.2.j). Los artículos 6.1, 9.2.d, 12.3, 13, 14, 28.3, 32 y 33 están citados de memoria **[H]**.

Comprobación propia: la web no usa cookies ni conecta con servidores de terceros al cargar los cuatro documentos, en un Chromium real: 0 cookies y ningún servidor distinto del propio **[E]**. El inicio de sesión y el idioma usan el almacenamiento local del navegador (la clave de idioma está en `src/i18n/index.ts`; la sesión la guarda el cliente de autenticación) **[E]**.

## 5. Lo que el abogado debe revisar

Decisiones de redacción mías, sin respaldo en el repositorio ni en una instrucción, que el abogado debe confirmar o cambiar:

1. **Planes y cobros**: los términos dicen que hoy no hay cobros reales y que, si los hubiera, se informará antes del precio, de los impuestos y de la forma de pago, y se requerirá aceptación. Es un compromiso que redacté yo.
2. **Jurisdicción**: ley española y tribunales de Sevilla, sin perjuicio del fuero de consumidores. Para iglesias de otros países puede no ser lo adecuado.
3. **Limitación de responsabilidad** (apartado 8 de los términos): redacción genérica, sin tope económico.
4. **Contrato de encargo**: autorización general de subencargados con aviso de cambios, notificación de violaciones «sin dilación indebida» (sin plazo en horas), auditorías «razonables». Cada punto es una opción de negociación.
5. **Edad**: el texto cita los 14 años del artículo 7 de la LOPDGDD y el registro por QR ya exige declarar esa edad. Los términos prohíben registrar a menores sin autorización de quien ejerza la patria potestad.
6. **Base legal de las iglesias para datos que revelan religión**: el texto cita el artículo 9.2.d del RGPD (entidades religiosas respecto de sus miembros) y el consentimiento explícito, y deja la responsabilidad en cada iglesia. Si una iglesia sin personalidad jurídica propia puede acogerse al 9.2.d es una pregunta jurídica.
7. **Transferencias internacionales y subencargados**: el texto no nombra a los proveedores y dice que la lista y la región se facilitan a quien las pida. Qué proveedores son (la base de datos, la autenticación y los archivos; el alojamiento web; el correo de invitaciones) sale del código, pero **la región donde están los datos es [NV]**. Conviene fijarla y nombrarla.
8. **Purga y copias**: el texto promete el borrado suave de 30 días y después la purga, pero hoy la purga es manual **[E]** (`docs/CONTEXTO.md`) y las copias de seguridad no tienen plazo fijado (`docs/RESTAURACION.md`). Hasta programar la purga y fijar el plazo de copias, la promesa depende de que alguien la ejecute.
9. **Delegado de protección de datos** y **inscripción en registro público**: el repositorio no dice si existen. El texto no afirma ni niega el primero y muestra el segundo solo si se configura.
10. **Comunicaciones por correo, SMS y WhatsApp**: el texto dice que hoy la plataforma no envía mensajes reales y describe las reglas para cuando lo haga. WhatsApp exige además plantillas aprobadas (`docs/COMUNICACION.md`, apartado 5).
11. **Traducciones**: las hizo un modelo de lenguaje a partir del español, con comprobación mecánica de estructura y marcadores. Reservas de las traducciones: «dolo» (wilful misconduct, dol), «patria potestad o tutela», «borrado suave» (soft deletion, exclusión lógica), «aviso legal» como «mentions légales», que en Francia tiene otro contenido normativo, y la cláusula de ley y tribunales españoles ante usuarios de Brasil, donde no se cita la LGPD. Las versiones inglesa, francesa y portuguesa deben revisarse con el español como texto de referencia.

## 6. Cómo se publica

1. Gerencia confirma los valores del apartado 2 y alguien los define en la configuración de la web (y `ADN_EMAIL_SOPORTE` en la función de invitaciones).
2. `npm run check:config-legal`, `npm run check:legal` y `npm run check:textos` pasan.
3. Aprobación de Harold para desplegar. Nada de esto está desplegado: está en la rama de Gerencia.
4. Tras desplegar, abrir los cuatro documentos en los cuatro idiomas y comprobar que no queda ningún aviso amarillo.
