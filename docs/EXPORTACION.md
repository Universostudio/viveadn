# Exportación completa de una iglesia

Formato `viveadn-exportacion-2`. Sirve para entregar a una iglesia todos sus datos (portabilidad y supresión, RGPD), para copias de seguridad que se puedan leer sin Vive ADN y para mover una iglesia a otra base. Cada afirmación lleva su etiqueta: **[E]** verificado ejecutándolo en esta sesión, **[NV]** no verificable aquí.

## Qué contiene

El panel de plataforma entrega un ZIP con tres tipos de archivo.

| Archivo | Contenido |
| --- | --- |
| `manifest.json` | Para cada tabla: filas, columnas con su tipo, columnas omitidas, orden de carga, `huella` (md5 del contenido) y `md5_csv`. También el total de filas y las reglas del CSV. |
| `datos.json` | Todos los datos de la iglesia: la fila de `iglesias` y, por tabla, sus filas. |
| `csv/<tabla>.csv` | Un CSV por tabla. UTF-8 sin BOM, separador coma, fin de línea CRLF (RFC 4180). Un campo vacío sin comillas es NULL; una cadena vacía va entre comillas (`""`). Las fechas llevan zona (UTC) y los numéricos conservan su escala exacta. |

Entran 32 tablas [E]: la iglesia, toda tabla con `iglesia_id` y `rol_permisos`. Una prueba compara el manifiesto con el catálogo de la base y falla si una tabla nueva queda fuera, igual que la clasificación de `permisos.sql`. Los archivos de Storage no viajan: la función de borde añade su listado (`archivos`) para pedirlos aparte.

## Qué no sale, y por qué

Los tokens del QR de eventos y de invitaciones y las huellas de IP son secretos: quien tuviera el archivo podría registrar asistencia o aceptar invitaciones. Tampoco salen los secretos anidados en la auditoría ni las marcas internas del borrado suave. El manifiesto lista las columnas omitidas de cada tabla [E, la prueba busca los valores secretos en todos los archivos y no aparecen]. Los datos de otras iglesias tampoco salen [E]. Las cuentas de acceso (Auth) no viajan: las personas deben volver a ser invitadas.

Una advertencia que también va en el `LEEME.txt` del ZIP: los CSV conservan el texto tal cual, de modo que una celda que empiece por `=`, `+`, `-` o `@` puede interpretarse como fórmula si se abre en una hoja de cálculo. Los informes en Excel (trabajo 4) neutralizan esas celdas; la exportación no, porque debe devolver exactamente lo guardado.

## Cómo se genera

`adn_exportar_paquete(iglesia)` devuelve todo en una sola llamada, solo para `service_role`, desde la función de borde `plataforma` (acción `exportar`, restringida a administradores de plataforma y auditada). El CSV se construye en la base y no en el navegador para no perder la escala de los numéricos. `exportar_iglesia`, la función anterior, no se modificó: si la migración no está aplicada o se revierte, la función de borde vuelve a ella y el panel descarga el JSON de siempre [E en sus tipos; NV de extremo a extremo].

La exportación **no** incluye `plataforma_auditoria` (decisión de Gerencia, 11-11): son acciones internas de la plataforma y pueden llevar notas de administración. Queda disponible aparte, solo para administradores de plataforma, con la acción `auditoria_iglesia` de la función de borde `plataforma` (sin las huellas de IP). La exportación de reserva anterior, que sí la incluía, se filtra en la misma función. Por eso el manifiesto cubre 28 tablas y no 29 [E, `exportacion_carga.sh` comprueba que no sale].

## Prueba de carga en una base vacía

`supabase/tests/exportacion_carga.sh` (parte de `ejecutar.sh` y del CI) [E, 12 comprobaciones]:

1. Crea una iglesia sintética con filas en las 32 tablas y datos incómodos para un CSV: comas, comillas, saltos de línea CRLF, tabulaciones, emoji, caracteres japoneses, espacios al borde, la cadena `NULL`, una barra seguida de `N`, textos que parecen fórmulas, vacío frente a NULL y un numérico con ceros finales. Añade una segunda iglesia que no debe aparecer.
2. Exporta, separa los archivos y comprueba que el md5 de cada CSV es el del manifiesto.
3. Carga el JSON en una base vacía y los CSV en otra, ambas con el esquema y las migraciones.
4. Compara, tabla a tabla, filas y contenido con el manifiesto mediante `adn_verificar_carga`: **las 32 tablas coinciden en las dos cargas** (164 filas).
5. Comprueba que las 64 claves foráneas se cumplen en la base cargada, que solo entró una iglesia y que los secretos se regeneraron.
6. Demuestra que la comparación no es vacua: detecta un dato cambiado y una fila borrada, y no se alarma por un numérico equivalente.

## Procedimiento de restauración de referencia

Es el que usa la prueba, en `supabase/tests/exportacion/`. No se instala en producción: restaurar escribe en una base y requiere superusuario.

1. Preparar una base vacía con el esquema, el catálogo (`seed.sql`) y las migraciones.
2. Cargar sin disparadores (`session_replication_role = replica`, como `pg_restore --disable-triggers`), en el `orden_carga` del manifiesto. Con CSV: `\copy` por tabla con las columnas del manifiesto. Con JSON: `jsonb_populate_recordset`. Las columnas de identidad se cargan con `overriding system value` y luego se reajusta su secuencia.
3. Las columnas omitidas que la tabla exige (`evento_checkin.token`, `invitaciones.token_hash`, `checkin_registros.ip_hash`) se aflojan para cargar y se rellenan con 64 caracteres hexadecimales nuevos. Las invitaciones pendientes quedan inservibles y los eventos tienen un enlace QR nuevo.
4. Crear las cuentas de acceso: cada `perfiles.id` debe existir en Auth. En Supabase eso exige reinvitar a las personas [NV: no se probó contra Auth real].
5. Verificar con `adn_verificar_carga(manifiesto)`: todas las filas devueltas deben tener `ok`.

La red de iglesias no se restaura sola: `iglesia_madre_id` apunta a otra iglesia que no viaja en el paquete.

## Exportación por páginas

El panel de plataforma ya no pide el paquete entero. La función `plataforma` ofrece dos acciones, `exportar_plan` (las tablas, sus columnas y sus cifras) y `exportar_pagina` (hasta 5000 filas de una tabla, con cursor por clave primaria). Cada página la calcula la base de datos: el texto JSON, el texto CSV y el md5 de cada fila, que es el mismo que usa `adn_verificar_carga`. El navegador recorre cada tabla dos veces, una en JSON para `datos.json` y otra en CSV para `csv/<tabla>.csv`, y escribe un ZIP en flujo (`src/lib/zipFlujo.ts`, método almacenado, con descriptores de datos) sin tener nunca el paquete entero en memoria. Solo retiene los md5 de las filas, unos 54 bytes por fila, para calcular la huella de cada tabla; el manifiesto se escribe al final con las cifras de lo que de verdad se leyó. Si una página falla, se repite con espera creciente (tres intentos); si la iglesia cambia mientras se exporta, el manifiesto lo marca en `cambios_durante_la_exportacion` y el panel avisa.

`adn_exportar_paquete` sigue en la base como respaldo: el panel lo usa solo si la migración de las páginas no está desplegada.

## Prueba de volumen

`supabase/tests/volumen/exportacion_volumen.sh <personas>` crea una iglesia sintética (nueve filas por persona: ficha, correo alternativo, tres consentimientos y cuatro asistencias) y mide las dos vías sobre la misma base. Máquina de pruebas de 4 núcleos, PostgreSQL local, sin red entre la base y el cliente [E: repetible con el script].

| Personas | Filas | Una sola respuesta | Por páginas de 1000 filas |
|---|---|---|---|
| 10.000 | 90.202 | 11,4 s; respuesta de 48,6 MB; cliente psql 101 MB | 20,9 s; ZIP de 48,3 MB; pico del proceso 133 MB |
| 100.000 | 902.002 | **Falla** a los 100,6 s: `total size of jsonb object elements exceeds the maximum of 268435455 bytes` | 192,4 s; ZIP de 482,7 MB; pico del proceso 184 MB |

Qué dicen las cifras:

- La vía de una sola respuesta tiene un tope duro de 256 MB en la base, que alcanza una iglesia de unas 50.000 a 60.000 personas con este perfil de datos [H: se deduce de 48 MB por 10.000 personas]. Mucho antes toparía con la memoria de la función de borde [NV]. Por eso la vía por páginas es la que se ofrece.
- La vía por páginas tarda más, porque calcula cada tabla dos veces, pero su coste es lineal: unos 100 ms por página a 10.000 y a 100.000 personas, de modo que el cursor por clave no se degrada con el tamaño. El pico de memoria crece solo con los md5 retenidos (unos 51 MB más al pasar de 90.000 a 902.000 filas, que cuadra con los 54 bytes por fila medidos aparte).
- El número de filas del ZIP coincide con el recuento de la base y el ZIP pasa la comprobación de integridad de Python. La recarga completa en bases vacías con `adn_verificar_carga` se probó con la iglesia sintética pequeña (`tests/exportacion_paginada_carga.sh`, páginas de 2 y de 1000 filas), no con las 902.000 filas [NV a ese volumen].

## Límites

- Lo que no se midió: el tiempo real de la función de borde con la red de Supabase entre medias (cada página es una llamada), el tope de memoria del navegador de un teléfono con 180 MB de proceso, y la descarga de un ZIP de 480 MB en una conexión doméstica [NV: exige el entorno de pruebas desplegado]. Una iglesia de 100.000 personas es muy improbable en el producto; las cifras sirven para saber dónde está el límite, no como objetivo.
- Si la iglesia escribe mientras se exporta, el paquete puede mezclar dos instantes: queda marcado en el manifiesto, y la recomendación es repetir la exportación.
- La función de borde no se ejecutó de extremo a extremo (no hay entorno Supabase de prueba aquí) [NV]. Se comprobaron sus tipos en modo estricto, la base de datos, el recorrido del cliente contra PostgreSQL real y el empaquetado del ZIP (`npm run test:exportacion-paginada`, validado con el lector de Python).

## Orden de despliegue

La migración `20261111130000_adn_exportacion` y la `20261111260000_adn_exportacion_paginada` primero y la función de borde después. Su reversión está en `supabase/reversiones/` y se probó junto con la del ciclo de vida: esquema idéntico al anterior y sin pérdida de datos.
