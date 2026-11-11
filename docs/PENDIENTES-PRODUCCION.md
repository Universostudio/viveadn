# Pendientes de producción (puerta B)

Estado a 11 de noviembre de 2026. Regla de Harold, transmitida por Gerencia: mientras el entorno sea de pruebas, todo dato o decisión que dependa de Harold se marca **PENDIENTE** con la fórmula **«le diré»**, no se le vuelve a pedir y no cuenta como bloqueo. Solo cuenta en la **puerta B**, el paso a producción. Este documento es la única lista de esas cosas: si algo depende de Harold y no está aquí, falta anotarlo.

El entorno de pruebas se construye y se comporta como un producto real, completo y operativo de punta a punta (`docs/PUESTA-EN-MARCHA.md`). Para que funcione sin esos datos, cada fila dice qué hace el sistema mientras tanto.

Etiquetas de evidencia: **[E]** informado por Desarrollo con una prueba repetible, **[H]** deducido, **[NV]** no verificable desde aquí, **[V]** solo Gerencia.

## 1. Datos del titular

| Pendiente | Dónde se usa | En pruebas | Estado |
| --- | --- | --- | --- |
| NIF del titular | `VITE_LEGAL_NIF`: política de privacidad, términos y aviso legal | Los textos muestran el marcador `[nif pendiente de configurar]` en lugar de un dato inventado [E] | «le diré» |
| Domicilio completo | `VITE_LEGAL_DOMICILIO`: mismos textos | Igual, con su marcador | «le diré» |
| Correo de privacidad y legal | `VITE_EMAIL_LEGAL`: textos y contacto para derechos | Igual | «le diré» |
| Correo de soporte | `VITE_EMAIL_SOPORTE` y `ADN_EMAIL_SOPORTE`: textos y respuesta de los correos | Las invitaciones usan la dirección de reserva que ya existía en el código | «le diré» |
| Inscripción en un registro público, si existe | `VITE_LEGAL_REGISTRO` | El párrafo no se muestra [E] | «le diré» |

`npm run check:config-legal` falla mientras falte alguno de estos datos, y es el control de la puerta B: no se publica con un marcador a la vista.

## 2. Revisión jurídica

| Pendiente | Qué hay hecho | En pruebas | Estado |
| --- | --- | --- | --- |
| Revisión por un abogado de los cuatro textos de la versión 1 (privacidad 1.3, términos 1.2, aviso legal y cookies) | Textos completos en cuatro idiomas, cotejados con el RGPD y la LOPDGDD, con once puntos para el abogado en `docs/LEGAL.md` | Los textos se muestran como están, con el aviso de que esperan revisión | «le diré» |
| Pregunta del artículo 28.3.g sobre las copias | Formulada en `docs/LEGAL.md` | Sin efecto | «le diré» |
| Base legal de los mensajes y del envío real | `docs/COMUNICACION.md`, apartado 5 | El envío real no está encendido en pruebas | «le diré» |
| Retención de las copias de la plataforma y que la frase de 14 días sea cierta | Las copias de la plataforma dependen del plan; lo lee Gerencia en el panel **[V]** | La frase está en los textos y consta como no verificada | Gerencia lo confirma; si no se cumple, se corrige el texto antes de publicar |

## 3. Correo, buzones y avisos

| Pendiente | Qué hay hecho | En pruebas | Estado |
| --- | --- | --- | --- |
| Dominio de envío verificado (SPF, DKIM, DMARC y dirección de respuesta) | Ver `docs/COMUNICACION.md` | No sale ningún correo real: las pruebas usan buzones controlados o el buzón de pruebas del proveedor | «le diré» |
| Aprobación del envío real de mensajes a personas | El envío real y la doble confirmación están apagados por defecto | Apagados | «le diré» |
| Buzón al que llegan los avisos de la monitorización y de purga atrasada | Ruta de salud, tarjeta de purga en el panel y script de verificación | El indicador del panel basta; quien ejecute la verificación ve el resultado | «le diré» |
| Remitente propio de la plataforma para avisos por correo | Sin construir | El aviso por correo de purga atrasada espera a esto | «le diré» |

## 4. Copias, custodia y restauración

| Pendiente | Qué hay hecho | En pruebas | Estado |
| --- | --- | --- | --- |
| Custodia del archivo del libro de purgadas y de su clave | Funciones de exportación y de re-purga, probadas en local (`docs/PURGA.md`, apartado 4) | Se ensaya con un archivo de prueba y una clave de prueba que se borran después | «le diré» |
| Dónde se guardan las copias propias y quién custodia su clave | Procedimiento de copia y restauración (`docs/RESTAURACION.md`) | Se ensaya en la rama de pruebas con datos sintéticos | «le diré» |
| Quién autoriza y quién ejecuta una restauración real | Sin definir | Un ensayo no necesita autorización: es una rama de pruebas | «le diré» |
| Copia de los archivos de Storage | No existe; procedimiento escrito | Se ensaya creándola en la rama de pruebas | «le diré» |

## 5. Producción y cobros

| Pendiente | En pruebas | Estado |
| --- | --- | --- |
| Aprobación para desplegar a producción y para escribir en bases reales | Nada se escribe fuera de pruebas | «le diré» |
| Cobro del plan y pasarela (`docs/COBRO.md`) | No hay cobros en pruebas ni se construyen | «le diré» |
| Documentación de contratación con valores reales: condiciones comerciales, precios y datos fiscales | `docs/CONTRATACION-Y-OPERACION.md` está completo con estos campos marcados «le diré» | «le diré» |
| Nombre y dirección definitivos de la web de producción y del dominio | Las pruebas usan la dirección de pruebas (`docs/PUESTA-EN-MARCHA.md`) | «le diré» |

## 6. Lo que decide Gerencia, no Harold

Se anota aquí solo para que no se pierda. No lleva «le diré» porque no depende de Harold: reescribir o no el historial del repositorio público por los identificadores de infraestructura que ya contiene `supabase/README.md` (`docs/CONTEXTO.md`, apartado 8), y la retención de las copias de la plataforma.

## 7. Cómo se cierra la puerta B

Antes de pasar a producción, en este orden: se rellenan los datos de las secciones 1 y 5, se pasa la revisión de la sección 2, se decide la sección 4, y se ejecutan `npm run check:config-legal`, `npm run check:legal` y la batería de `docs/CONTEXTO.md`, apartado 9. Mientras tanto, nada de este documento detiene el trabajo en pruebas.
