# Manual de operación de la plataforma

Estado a 11 de noviembre de 2026. Es el manual del equipo que opera Vive ADN: altas, planes, bajas, purga, copias, restauración e incidencias. Complementa a `docs/PUESTA-EN-MARCHA.md` (cómo se monta el entorno) y a `docs/MANUAL-IGLESIAS.md` (lo que ven las iglesias). Etiquetas de evidencia: **[E]** informado por Desarrollo con una prueba repetible, **[H]** deducido, **[NV]** no verificable desde aquí. Lo que depende de Harold consta como «le diré» en `docs/PENDIENTES-PRODUCCION.md`. Todo lo que sigue se ensaya en el entorno de pruebas; nada de esto se ha ejecutado contra producción.

## 1. Dónde se opera

El panel está en `/plataforma` y solo lo abren las cuentas de `plataforma_admins`. Todas sus acciones pasan por la función de borde `plataforma`, que valida a quien llama, usa la clave de servicio y deja constancia en la auditoría de la plataforma. Ningún cambio se hace a mano en el editor SQL de una base con datos reales.

## 2. Rutinas

| Cuándo | Qué | Cómo |
| --- | --- | --- |
| Cada día | Comprobar la tarjeta «Purga programada» | Debe decir «Al día». Si está en rojo, ver el apartado 8 |
| Cada día | Comprobar que la web y las cuentas responden | `GET /api/salud` debe devolver `{"ok":true}` |
| Cada semana | Revisar el registro de las funciones de borde | Solo escriben errores con `console.error`; nadie los mira sin esta rutina. Anotar la fecha de la revisión |
| Cada semana | Verificar el entorno | `npm run check:entorno` con las variables de `docs/PUESTA-EN-MARCHA.md`, apartado 3, paso 8 |
| Tras cada purga o antes de cada copia | Añadir las purgas nuevas al libro externo | Apartado 9 |
| Cada mes | Confirmar que la rotación de copias sigue en 14 días y que existe una copia reciente | Apartado 10 |
| Tras cambiar secretos o direcciones | Repetir `npm run check:entorno` | `docs/PUESTA-EN-MARCHA.md`, apartado 7 |

## 3. Altas de iglesias

**Por su cuenta.** Con el registro abierto, la iglesia entra en `/registro` con un código de acceso. En el panel, la tarjeta «Registro de iglesias» controla dos interruptores: «Registro abierto» y «Exigir código de acceso» (durante las pruebas, activo). «Crear código» pide una etiqueta, el número de usos y los días de vigencia, y **muestra el código una sola vez**: hay que copiarlo en ese momento. Un código se puede activar o desactivar después. La respuesta del registro es la misma para un correo nuevo que para uno que ya tiene cuenta, para no revelar quién existe [E].

**Desde el panel.** «Nueva iglesia» pide nombre, dirección corta (`slug`), país, ciudad y los datos del propietario, y permite marcarla como demostración. La iglesia nace con sus roles de partida **[NV: el detalle de la invitación al propietario no se ha revisado en esta tarea]**.

## 4. Planes, módulos y etapas

- **Plan.** Cada iglesia tiene un plan: Semilla (50 miembros y 3 usuarios), Básico (300 y 10) o Premium (5.000 miembros y sin tope de usuarios; más de eso, a medida). El límite lo hace cumplir la base de datos al dar de alta, con el error `PLAN_LIMITE`: no se supera ni por error [E].
- **Complementos.** El panel activa o quita módulos por iglesia (por ejemplo, App con marca propia o Credenciales). Los módulos que ya vienen en el plan se muestran como incluidos en él.
- **Etapa.** Una iglesia pasa por En alta, En prueba (con una fecha límite de prueba), Activa, En receso y Suspendida. **Receso y suspendida cierran el acceso de la iglesia; los datos se conservan.** El panel pide confirmación antes de cambiar la etapa.

Los cambios de plan, de módulos y de etapa quedan en la auditoría de la plataforma.

## 5. Red de iglesias

«Vincular red» hace que una iglesia sea sede de otra y fija el acceso de la madre a sus cifras: «ninguno» (solo nombre y ciudad) o «resumen» (cifras agregadas, sin datos personales). Una madre no puede ser sede ni una sede tener sedes, y la base lo rechaza.

## 6. Exportar los datos de una iglesia

**Cuándo.** A petición de la iglesia (portabilidad) y siempre antes de una baja. **Cómo.** En la ficha de la iglesia, «Exportar datos» descarga un ZIP con `manifest.json`, `datos.json`, un CSV por tabla y un `LEEME.txt`. La acción queda auditada. Contenido y límites en `docs/EXPORTACION.md`.

**Límite que hay que respetar [NV].** Todo el paquete viaja en una sola respuesta de la función. No se ha medido con iglesias de decenas de miles de filas: hasta que se pagine, no debe ofrecerse a una iglesia grande, y si la respuesta falla, se avisa a Desarrollo en lugar de reintentar sin fin. Las notas de administración de la plataforma no entran en la exportación de la iglesia; se consultan aparte con la acción `auditoria_iglesia`, solo para administradores de plataforma.

**Comprobar el paquete.** El manifiesto lleva una huella por tabla. Al cargarlo en otra base se verifica con `adn_verificar_carga`; el procedimiento de referencia está en `docs/EXPORTACION.md`.

## 7. Baja de una iglesia

1. **Exportar** sus datos (apartado 6) y entregarlos a la iglesia.
2. **Borrar (30 días).** En la ficha, «Borrar (30 días)» pide escribir la dirección corta de la iglesia como confirmación y un motivo opcional. La iglesia queda suspendida y se programa la purga a 30 días [E]. El motivo es texto libre: no debe llevar datos de personas, y se anula al purgar.
3. **Recuperar.** Dentro del plazo, «Recuperar» devuelve la iglesia a la etapa que tenía y cancela la purga. Pasado el plazo, ya no se puede [E].
4. **Purga.** Vencido el plazo, la purga elimina la base de datos de la iglesia, sus archivos de los dos cubos de Storage y las cuentas de acceso de su equipo, y deja un rastro en la auditoría que sobrevive a la purga y no contiene datos de personas [E]. La lanza la tarea programada o, si falta, un administrador desde el panel.

El panel conserva también «Programar borrado» y «Borrar ahora», anteriores al borrado suave. El procedimiento normal es «Borrar (30 días)»; los otros solo con indicación expresa de Gerencia.

## 8. La purga programada

**Qué es.** Una tarea de la propia base (`pg_cron` y `pg_net`) que cada 6 horas llama a la función con el secreto. Diseño y esquema en `docs/PURGA.md`; pasos de activación en `docs/PUESTA-EN-MARCHA.md`, apartado 5. Hoy **no está activa [NV]**.

**Vigilarla.** La tarjeta «Purga programada» del panel muestra iglesias en borrado suave, con el plazo vencido y las horas de la más atrasada. Pasa a rojo cuando una lleva más de 48 horas esperando.

**Si está en rojo:**

1. Ver si la tarea corre: en la rama, `select * from cron.job_run_details order by start_time desc limit 5;` y buscar un error o una ausencia de ejecuciones **[NV]**.
2. Ejecutar `npm run check:entorno` con el secreto. Si dice «el secreto no coincide», el de la bóveda y el de la función son distintos: se vuelven a fijar los dos.
3. Un 401 de la pasarela significa que a la tarea le falta la clave pública (`adn_anon_key` en la bóveda); un 403 de la función, que el secreto no coincide.
4. Mientras se arregla, purgar a mano: el administrador del panel lanza la purga de lo vencido, por lotes. La respuesta indica cuántas quedan; se repite hasta que sea cero.
5. Anotar la causa y la hora.

**Rotar el secreto.** Se genera uno nuevo (al menos 32 caracteres), se cambia en los secretos de la función y en la bóveda a la vez, y se repite `npm run check:entorno`. Mientras no coincidan, la tarea recibe 403 y el indicador avisa a las 48 horas. Nunca se escribe en un archivo del repositorio ni en un mensaje.

## 9. El libro externo de purgadas

**Para qué.** Restaurar una copia anterior a una purga devuelve los datos de una iglesia ya borrada. La auditoría de la purga vive en la misma base y se pierde con la restauración, así que se guarda una lista **fuera de la base** con solo el identificador de cada iglesia purgada y la fecha. Ningún dato de personas ni de iglesias.

**Cómo se mantiene [H, aún no existe el archivador].** Quien hace la copia propia llama a la acción `libro_purgas` de la función, con la fecha de la última entrada que ya tiene, y añade el resultado a un archivo cifrado que guarda junto a las copias. Se hace al terminar cada pasada de purga y no solo con la copia diaria: las purgas posteriores a la última actualización y anteriores a un desastre no estarían en el libro. La custodia del archivo y de su clave: «le diré» (`docs/PENDIENTES-PRODUCCION.md`, sección 4).

**Uso tras una restauración.** Antes de abrir la base restaurada: `repurgar_registradas` con todos los identificadores del libro (la acción exige confirmar con la palabra `REPURGAR`), y después la purga de lo vencido hasta que no quede nada. Está probado en local con una restauración simulada [E, `adn_libro_purgas.sql`]; **la función desplegada no se ha ejecutado [NV]**. Una restauración sin el libro actualizado no se acepta.

## 10. Copias y restauración

- **Qué hay.** Copias automáticas de la plataforma, cuya retención depende del plan y la lee Gerencia en el panel [V]; copias propias con `pg_dump` cifradas y fuera de la plataforma, con retención de **14 días**, que no están configuradas **[NV]**; y la exportación por iglesia. No existe copia de los archivos de Storage.
- **Procedimiento.** `docs/RESTAURACION.md` describe el ensayo completo en una rama de pruebas: copia, daño provocado, restauración, cuentas de acceso, archivos, secretos y verificación, con la tabla de medidas que hay que rellenar. El ensayo local de la base completa se repite con `supabase/tests/restauracion_base_completa.sh` [E].
- **Condición para aceptar una restauración real:** el libro de purgadas aplicado (apartado 9), las cuentas de acceso comprobadas con `supabase/tests/auth_usuarios_sin_nulos.sql`, y las pruebas de permisos y aislamiento superadas sobre la rama restaurada.
- **Quién autoriza una restauración real:** «le diré». En pruebas, un ensayo no necesita autorización.

## 11. Cambios de código y de base de datos

1. Toda migración nueva es un archivo en `supabase/migrations`, con los objetos nuevos prefijados `adn_`, sus permisos, su seguridad por filas y sus políticas en el mismo archivo.
2. **La reversión se escribe y se prueba antes** de aplicar nada: `supabase/reversiones/<migración>.down.sql`, y `supabase/tests/adn_reversion.sh` demuestra que el esquema vuelve a ser idéntico al anterior.
3. Antes de aplicar una migración deben pasar la batería completa (`PGUSER=postgres supabase/tests/ejecutar.sh`) y las comprobaciones de `docs/CONTEXTO.md`, apartado 9.
4. Nunca se cambia un dato real a mano, ni se pone una clave en un archivo.

## 12. Incidencias frecuentes

| Síntoma | Causa probable | Qué hacer |
| --- | --- | --- |
| La web carga pero ninguna llamada funciona y el navegador habla de CORS | La web no está en los orígenes permitidos de las funciones | Definir `ADN_ORIGENES_EXTRA` con la dirección exacta de la web y repetir la verificación |
| `/api/salud` devuelve 503 | El alojamiento no ve `VITE_SUPABASE_URL` o `VITE_SUPABASE_ANON_KEY`, o Auth no contesta | Revisar las variables del alojamiento y el estado del proyecto de Supabase |
| Una persona no puede iniciar sesión tras crear su cuenta por SQL | Un NULL en una columna de texto de `auth.users` rompe el servicio de cuentas | Ejecutar `supabase/tests/auth_usuarios_sin_nulos.sql`; crear las cuentas con el panel de Auth o la API de administración |
| Las invitaciones redirigen a otra dirección | La dirección de la web no figura en las Redirect URLs de Auth | Añadir `<WEB>/**` en la configuración de URL de Auth |
| La invitación no llega | No hay clave de correo configurada (es lo normal en pruebas) o cayó en spam | Copiar el enlace desde la pantalla de usuarios y enviarlo a mano |
| Una iglesia alcanza «PLAN_LIMITE» | Llegó al tope de su plan | Cambiar el plan desde el panel |
| La purga no corre | Secreto distinto, clave pública ausente o extensiones no activas | Apartado 8 |
| Una persona no recibe mensajes | No consta como suscrita en ese canal | Pantalla de consentimientos de su iglesia: solo recibe quien está suscrito |
| Un enlace de baja dice «inválido» | Ya se usó, caducó o es incorrecto | Se crea otro enlace; no se puede reconstruir el anterior porque la base solo guarda su huella |
| La aplicación pide recargar | Se publicó una versión mientras había páginas abiertas | Es lo esperado; recargar |

## 13. Qué queda fuera de este manual

El envío real de mensajes, la doble confirmación por correo y los cobros no están en marcha en pruebas (`docs/PUESTA-EN-MARCHA.md`, apartado 6). Cuando se activen, este manual necesitará sus procedimientos: dominio de envío verificado, gestión de rebotes y bajas, y avisos por correo de purga atrasada. Todo ello depende de datos que constan en `docs/PENDIENTES-PRODUCCION.md`.
