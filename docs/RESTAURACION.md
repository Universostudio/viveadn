# Restauración de la base completa y del almacenamiento

Estado a 11 de noviembre de 2026. Etiquetas de evidencia: **[E]** informado por Desarrollo con una prueba repetible, **[H]** deducido, **[NV]** no verificable desde aquí. Este documento es un procedimiento para **ensayar en la rama de pruebas de Supabase**. Nada de lo que describe se ha ejecutado contra una base real, y ninguno de sus pasos debe ejecutarse en producción sin la aprobación de Harold.

## 1. Qué hay que poder recuperar

Una pérdida seria obliga a recuperar cinco cosas, y una copia de la base de datos solo cubre una parte.

| Pieza | Dónde vive | Lo cubre una copia de la base | Cómo se recupera |
| --- | --- | --- | --- |
| Datos de las iglesias | 44 tablas de `public`, de las que 32 entran en la exportación por iglesia **[E]** | Sí | Apartado 4, pasos 1 a 3 |
| Cuentas de acceso | `auth.users` y tablas de Auth | Depende de cómo se copie **[NV]** | Apartado 4, paso 4 |
| Archivos | Dos cubos de Storage: `iglesia-marca` (público) e `iglesia-archivos` (privado), con la iglesia como primera carpeta de la ruta **[E]** | **No** **[H]**: la base solo guarda los metadatos de los objetos | Apartado 4, paso 5 |
| Esquema, permisos, catálogo y los cubos con sus políticas | `supabase/migrations`, `schema/seed.sql` | Sí, y además están en git | Se reaplican desde el repositorio **[E]** |
| Código y funciones de borde | Git y el despliegue | No hace falta | Se vuelve a desplegar desde el repositorio |
| Secretos y ajustes del proyecto | Panel de la plataforma y secretos de las funciones | **No** | Apartado 4, paso 6. **[NV]** quién los guarda y dónde |

Los secretos que las funciones de borde esperan son estos, y solo estos **[E]** (`grep Deno.env.get`): la dirección del proyecto, la clave pública, la clave de servicio, `ADN_CRON_SECRET` (la purga programada: Gerencia lo generará y guardará en la bóveda; hoy no está definido, `docs/PURGA.md`) y `BIRD_API_KEY` (las invitaciones). Las dos primeras las inyecta la propia plataforma.

## 2. Qué copias existen hoy

| Copia | Qué contiene | Estado |
| --- | --- | --- |
| Copias automáticas de la plataforma de base de datos | La base completa. Frecuencia, retención y restauración a un punto en el tiempo dependen del plan **[NV]** | Hay que leer en el panel qué plan tiene el proyecto y qué ofrece; este documento no lo afirma |
| Copia lógica propia (`pg_dump`) | La base completa, en un formato que se restaura sin la plataforma | Procedimiento ensayado en local **[E]** (apartado 3). No existe ninguna programada |
| Exportación por iglesia (`adn_exportar_paquete`) | Todos los datos de una iglesia, sin secretos, con huellas | Probada, recargada en dos bases vacías **[E]** (`docs/EXPORTACION.md`). Sirve para entregar datos a una iglesia, **no** sustituye a una copia de la plataforma: no lleva cuentas, archivos ni otras iglesias |
| Copia de los archivos de Storage | Los objetos de los dos cubos | **No existe** **[E]** |

## 3. Ensayo hecho en local

`supabase/tests/restauracion_base_completa.sh` **[E]** monta una base con el esquema, el catálogo, las migraciones y una iglesia sintética con filas en todas las tablas; hace un `pg_dump` en formato personalizado; restaura con `pg_restore` en una base vacía y compara. Resultado de la última ejecución:

- La restauración termina sin errores.
- El esquema restaurado es idéntico al original.
- Las 47 tablas de `public`, `auth` y `storage` tienen las mismas filas con el mismo contenido (419 filas, md5 del contenido ordenado de cada tabla).
- Las secuencias de identidad continúan donde estaban, de modo que las filas nuevas no chocan con las restauradas.
- La base restaurada exporta la iglesia de prueba con las mismas 164 filas.
- La seguridad por filas y los permisos se restauran como estaban.
- La comparación no es vacua: detecta un dato cambiado y filas borradas.

Repetirlo: `PGUSER=postgres supabase/tests/restauracion_base_completa.sh` con PostgreSQL local arrancado. Crea y borra `viveadn_rest_origen` y `viveadn_rest_destino`.

Lo que este ensayo **no** demuestra, y solo la rama de pruebas puede demostrar:

1. Una restauración en Supabase, cuyos esquemas gestionados por la plataforma (Auth, Storage, extensiones, tiempo real) no se tratan como los de una base ordinaria. En local el esquema de Auth es un sustituto mínimo.
2. Que las personas puedan iniciar sesión después de restaurar, porque depende de cómo se recuperen las cuentas.
3. Tiempos reales (cuánto tarda y cuánta información se pierde).
4. Nada de lo relativo a Storage.

## 4. Procedimiento para la rama de pruebas

Se hace en una rama o un proyecto de pruebas **creado para esto**, vacío o con datos sintéticos, y con estas condiciones: sin clave de correo (`BIRD_API_KEY` sin definir), sin ningún dato real de iglesias, y sin tocar el proyecto de producción. La clave de servicio se usa solo desde el entorno de quien ejecuta, nunca en un archivo del repositorio.

**Paso 0. Punto de partida.** Anotar la hora. Cargar en la rama de pruebas datos sintéticos (por ejemplo `tests/exportacion/origen.sql` con `-v salida=<archivo> -v conservar=1`, que deja dos iglesias ficticias con filas en todas las tablas) y guardar las huellas: filas y md5 de cada tabla con la consulta de `restauracion_base_completa.sh`. Subir un archivo pequeño a cada cubo para el paso 5.

**Paso 1. Hacer la copia.** Dos caminos, y conviene ensayar los dos:
- *Plataforma*: pedir una copia desde el panel, o usar la última automática **[NV]**.
- *Lógica*: `supabase db dump` para el esquema y para los datos, o `pg_dump -Fc --no-owner` contra la cadena de conexión de la rama. Guardar el archivo cifrado y fuera de la plataforma. **[NV]** qué esquemas gestionados hay que excluir al volcar, y si el volcado de datos incluye `auth`.

**Paso 2. Provocar el daño.** En la rama de pruebas, borrar a propósito: una iglesia entera con `adn_borrar_suave` y después con la purga, una tabla de datos y un archivo de cada cubo. Anotar qué se borró.

**Paso 3. Restaurar la base.** Sobre una rama nueva y vacía, no sobre la dañada, para no depender del estado en que quedó:
- *Plataforma*: restaurar la copia en la rama o proyecto nuevo, a un momento anterior al daño si el plan lo permite **[NV]**.
- *Lógica*: aplicar el esquema y las migraciones, y después los datos. `pg_restore --no-owner --exit-on-error` si la copia es en formato personalizado.

**Paso 4. Cuentas de acceso.** Cada fila de `perfiles` debe corresponder a una cuenta de Auth. Comprobar con una consulta que no hay perfiles huérfanos y que `auth.users` no tiene valores nulos que rompan el inicio de sesión (`supabase/tests/auth_usuarios_sin_nulos.sql`, ya preparada). Si la copia no incluyó Auth, las personas tendrán que restablecer la contraseña: eso hay que medirlo y decidirlo **[NV]**. Iniciar sesión con una cuenta sintética de prueba y abrir su iglesia.

**Paso 5. Restaurar el almacenamiento.**
1. Comprobar que los dos cubos existen con sus límites y políticas: los crea la migración `20261105222115_archivos_por_iglesia.sql`, no la copia.
2. Recuperar los objetos desde la copia de archivos. Como esa copia **no existe**, este paso solo se puede ensayar si antes se crea: listar con la API de Storage cada cubo y cada carpeta (la primera es el identificador de la iglesia), descargar cada objeto a una carpeta cifrada y registrar su ruta, tamaño y huella. El listado de rutas de una iglesia ya sale en su exportación **[E]**.
3. Subir de nuevo cada objeto a la misma ruta y comparar tamaño y huella.
4. Para `iglesia-archivos`, comprobar que se lee con una URL firmada y que otra iglesia no puede leerlo **[E]** para la política, **[NV]** contra Storage real.

**Paso 6. Secretos y configuración.** Volver a definir en la rama los secretos de las funciones, las direcciones de retorno de Auth y la lista de orígenes permitidos (`docs/REVISION-TRANSVERSAL.md`), y desplegar las ocho funciones de borde desde el repositorio. Anotar quién tenía cada secreto y de dónde salió.

**Paso 7. Verificar.** Los criterios para dar el ensayo por bueno:
- Las huellas del paso 0 coinciden tabla a tabla, salvo lo borrado a propósito en el paso 2 que el punto de restauración no recuperó.
- Las pruebas SQL de permisos y de aislamiento total (`supabase/tests/permisos.sql`, `adn_aislamiento_total.sql`) pasan contra la rama restaurada, y `aislamiento_api.sh` pasa contra su API real **[NV: aún no se ha ejecutado]**. Estas pruebas crean y deshacen iglesias de prueba y se niegan a correr si hay iglesias reales: en una rama con datos reales no se ejecutan.
- Una cuenta sintética inicia sesión, ve su iglesia y no ve la otra.
- Cada archivo recuperado tiene el tamaño y la huella anotados.
- Ninguna fila de `adn_mensajes` ha cambiado y no ha salido ningún correo.
- **Condición para aceptar una restauración real: el libro externo de purgadas.** Antes de abrir la base restaurada, se aplica el libro (`repurgar_registradas` con todos los identificadores, después `purgar_vencidas` hasta que `restantes` sea cero) para que no reviva ninguna iglesia ya borrada; ver `docs/PURGA.md`, apartado 4. Sin el libro, o con un libro anterior a alguna purga, la restauración resucita datos que prometimos borrar y **no se acepta**. **Requisito de custodia:** el archivo del libro se guarda fuera de la plataforma y cifrado, y su clave se custodia aparte. Quién lo hace: «le diré» (puerta B, `docs/PENDIENTES-PRODUCCION.md`). En pruebas se ensaya con un archivo y una clave de prueba que se borran después. El archivo contiene solo identificadores y fechas, pero sin él no se puede garantizar el borrado tras una restauración.

**Paso 8. Medir y registrar.** Rellenar la tabla de abajo y entregarla a Gerencia. Sin estas cifras no hay política de copias, solo intención.

| Dato | Valor |
| --- | --- |
| Hora del último cambio antes del daño y hora del punto restaurado (pérdida de información) | |
| Hora de inicio y de fin de la restauración (tiempo de recuperación) | |
| Tablas con diferencias y motivo | |
| Archivos no recuperados | |
| Personas que tendrían que restablecer la contraseña | |
| Pasos que hubo que improvisar | |

## 5. Decisiones pendientes de producción («le diré»)

En pruebas no bloquean nada: se ensaya con datos y claves de prueba. Cuentan en la puerta B (`docs/PENDIENTES-PRODUCCION.md`).

1. **Cuánta información se puede perder y cuánto tiempo puede estar caída la plataforma.** De ahí salen la frecuencia de las copias y el plan de la base de datos.
2. **Dónde se guardan las copias lógicas y los archivos, y quién custodia la clave que las cifra.** Una copia contiene datos de pertenencia religiosa (categoría especial en el RGPD **[H]**), así que el sitio y quién accede lo debe decidir una persona con responsabilidad, no el script.
3. **Cuánto tiempo se conservan las copias**, porque una iglesia que pide la supresión de sus datos sigue estando en las copias anteriores. Decidido por Gerencia el 11 de noviembre: **14 días** para las copias propias, y consta en la política de privacidad 1.3 y los términos 1.2. Falta configurarlo y demostrarlo **[NV]**, leer la retención de las copias de la plataforma (si es mayor, manda la mayor) y que el abogado confirme que la rotación basta para el 28.3.g (`docs/LEGAL.md`).
4. **Quién ejecuta una restauración real y quién la autoriza.** Restaurar sobre producción sobrescribe datos y requiere la aprobación de Harold.

## 6. Límites conocidos

- La purga de iglesias hoy es manual; la programada está diseñada y aprobada, sin activar (`docs/PURGA.md`). Una restauración posterior a una purga no devuelve a la iglesia borrada si el punto elegido es más reciente que la purga; solo la exportación de esa iglesia, si se entregó antes, o una copia anterior. Una restauración **anterior** a una purga sí la devuelve: de ahí el libro externo de la condición del paso 7.
- La red de iglesias no se restaura sola desde una exportación: `iglesia_madre_id` apunta a otra iglesia que no viaja en el paquete.
- Las copias de la plataforma no sustituyen una copia propia: si la cuenta de la plataforma se pierde o se bloquea, se pierden con ella.
