# Pruebas de aislamiento entre iglesias

Estado a 11 de noviembre de 2026. Etiquetas de evidencia (carta de gerencia, 11-11): **[V]** comprobado por Gerencia, **[E]** informado por Desarrollo con una prueba repetible (el comando está en «Cómo repetir las pruebas», `docs/CONTEXTO.md`), **[H]** deducido, **[NV]** no verificable.

## 1. Qué se prueba

Dos usuarios de prueba, cada uno propietario de una iglesia sintética distinta. La iglesia A tiene filas en todas las tablas con `iglesia_id`; la B tiene filas en cinco. Cada usuario ataca a la otra iglesia en **todas** las tablas con `iglesia_id` (27 tablas hoy) y en cada tabla intenta cuatro cosas:

| Ataque | Resultado exigido |
| --- | --- |
| Leer filas de la otra iglesia, con y sin filtro | Cero filas, o permiso denegado |
| Modificar filas de la otra iglesia | Cero filas afectadas, o permiso denegado |
| Borrar filas de la otra iglesia | Cero filas afectadas, o permiso denegado |
| Insertar una copia de una fila de la otra iglesia, con su `iglesia_id` | Rechazada por la política o por falta de permiso. La inserción se hace sin `RETURNING`, porque devolver la fila exigiría poder leerla y ocultaría una inserción a ciegas |

Además, la prueba SQL comprueba:

- **Controles positivos.** Cada usuario sí ve sus propias filas (la última ejecución: A ve filas propias en 30 tablas y no tiene acceso a 2; B, en 6 y sin acceso a 2). Sin ellos, una base que negara todo pasaría la prueba.
- **Sin sesión y sin iglesia.** El rol `anon` no lee nada en ninguna de las 38 tablas; un usuario autenticado sin perfil no ve miembros ni iglesias y no puede calcular un envío ni importar.
- **Funciones.** Ninguna función pública que reciba una iglesia (exportar, borrar, purgar, recuperar, auditar) es ejecutable por usuarios ni por `anon`.
- **Datos derivados.** El panel de inicio, los cuatro informes y la vista previa de envío de cada usuario solo contienen datos de su iglesia, y sí contienen los suyos.
- **Envío y bajas.** El buzón de pruebas de A no contiene destinatarios ni textos de B. Una baja de una dirección en A no afecta a B aunque compartan esa dirección.
- **Importación.** Importar en A un correo que ya existe en B no modifica al miembro de B y crea uno nuevo en A: la deduplicación por correo no cruza iglesias.
- **Claves foráneas compuestas.** A no puede asignar un miembro a una casa de B, ni colgar un contacto de un miembro de B, ni mover una casa a una zona de B.
- **Nada cambia.** Tras los ataques, los datos de ambas iglesias siguen intactos.

## 2. La prueba detecta fugas, no solo pasa

Una prueba de aislamiento que nunca falla no prueba nada. Se inyectaron a propósito seis fugas dentro de la transacción de prueba, y cada una hizo fallar el script con el mensaje esperado [E]:

| Fuga inyectada | Mensaje de fallo |
| --- | --- |
| Política de lectura abierta en `casas_oracion` | filas de otra iglesia visibles |
| Lectura y modificación abiertas en `casas_oracion`, con la lectura ignorada | se modificaron filas ajenas |
| Lectura y borrado abiertos en `casas_oracion`, con la lectura ignorada | se borraron filas ajenas |
| Política de inserción abierta en `enlaces_dar` | la inserción no la rechazó la política |
| Permiso de lectura y política abierta para `anon` en `miembros` | anon lee filas |
| Permiso de ejecución de `exportar_iglesia` a usuarios | función ejecutable |

Esto reveló dos debilidades de la primera versión, ya corregidas: una colisión de clave primaria o de clave única ocultaba una política de inserción abierta, y `RETURNING` ocultaba una inserción a ciegas. Por eso hoy, en el estado sano, **ningún** rechazo de inserción puede venir de una causa distinta de la política o del permiso; si algún día una tabla nueva se rechaza por otra razón, la prueba falla y obliga a revisarla.

## 3. Cómo se ejecuta

- **SQL (en CI).** `supabase/tests/ejecutar.sh` lanza `adn_aislamiento_total.sql` dentro de `exportacion/origen.sql`, que siembra las dos iglesias y deshace todo al terminar. Se niega a correr si hay iglesias reales [E].
- **API (manual).** `supabase/tests/aislamiento_api.sh <base> [url]` siembra los datos, lanza `aislamiento_api.py` contra PostgREST y los borra aunque falle. El script repite los mismos ataques como peticiones HTTP firmadas con el secreto de `postgrest.conf`, llama a las funciones que no debe poder llamar, prueba a un visitante sin sesión y compara una instantánea de la base (filas y huella por iglesia y tabla) antes y después.

## 4. Límites

- **[NV] La versión por API no se ha ejecutado contra un PostgREST real.** Se probó con un servidor HTTP simulado que valida la siembra, el descubrimiento de tablas, las instantáneas, la limpieza y las 291 peticiones, y el único fallo fue el esperado: los dos controles positivos, porque el simulado no devuelve filas. El binario oficial de PostgREST se descargó, pero la política de permisos de la sesión no autorizó ejecutarlo. Para ejecutarla basta arrancar PostgREST 12 con `supabase/tests/postgrest.conf` y lanzar el script (ver `supabase/README.md`); no está en CI porque falta un paso que instale PostgREST con una versión y una huella fijas.
- La inserción por API envía copias de filas ajenas; si el rechazo viene de una columna generada y no de la política, esa tabla queda cubierta solo por la prueba SQL, que es la estricta.
- Se prueban usuarios con rol de propietario. Los roles de menor alcance (líder, consolidador, colaborador) tienen sus propias pruebas en `aislamiento.sql`, `roles_nuevos.sql` y `permisos.sql`.
- No se prueba el aislamiento del almacenamiento de archivos ni de Auth, que viven fuera de las tablas públicas (el de archivos está en `archivos.sql`).
- Una política mal escrita en una tabla con rol de servicio, `service_role`, queda fuera: ese rol salta la seguridad por filas por diseño, y solo lo usan las funciones de borde.
