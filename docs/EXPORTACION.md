# Exportación completa de una iglesia

Formato `viveadn-exportacion-2`. Sirve para entregar a una iglesia todos sus datos (portabilidad y supresión, RGPD), para copias de seguridad que se puedan leer sin ViveADN y para mover una iglesia a otra base. Cada afirmación lleva su etiqueta: **[E]** verificado ejecutándolo en esta sesión, **[NV]** no verificable aquí.

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

## Límites

- **Pendiente prioritaria antes de producción: paginación o generación del ZIP en el servidor.** Todo el paquete viaja en una sola respuesta de la función de borde, y el CSV duplica el JSON. Con iglesias de decenas de miles de filas la respuesta puede superar los límites de tamaño y de tiempo de la función [NV: no se midió; la prueba usa 150 filas]. Hasta que se resuelva, la exportación es fiable para iglesias pequeñas y medianas, y no debe ofrecerse a una iglesia grande.
- La función de borde no se ejecutó de extremo a extremo (no hay entorno Supabase de prueba aquí) [NV]. Se comprobaron sus tipos en modo estricto, la base de datos y el empaquetado del ZIP (`npm run test:exportacion`, validado con el lector de Python).

## Orden de despliegue

La migración `20261111130000_adn_exportacion` primero y la función de borde después. Su reversión está en `supabase/reversiones/` y se probó junto con la del ciclo de vida: esquema idéntico al anterior y sin pérdida de datos.
