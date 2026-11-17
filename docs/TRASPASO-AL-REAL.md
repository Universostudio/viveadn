# Traspaso al proyecto real (viveadn-saas)

Estado a 17 de noviembre de 2026. Orden de Harold: el proyecto real (`viveadn-saas`, `xrjbvjqhpwjjtcfdlsbq`) pasa a ser el único y se usa también para probar hasta el lanzamiento; el cobro será en modo de prueba de Stripe. Este documento prepara el traspaso desde `viveadn-pruebas` (`ormhltsjbilgxatamuur`). **No se ha tocado nada en ninguno de los dos proyectos**: todo lo medido aquí salió de consultas de solo lectura, y el paquete solo se ha aplicado a bases locales. Gerencia aprueba, aplica y verifica; después Harold borra `viveadn-pruebas`.

Etiquetas de evidencia: **[E]** medido o probado con una prueba repetible, **[H]** deducido, **[NV]** no verificable desde aquí.

## 1. Qué tiene cada proyecto hoy [E, consultas de solo lectura del 17 de noviembre]

| | Real | Pruebas |
| --- | --- | --- |
| Tablas públicas | 33 | 50 (+17, todas `adn_*`) |
| Políticas (public y storage) | 95 | 115 |
| Funciones en `public` y `private` | 54 | 123 |
| Disparadores públicos | 21 | 34 |
| Funciones de borde | 7 | 11 |
| Migraciones registradas | 31, hasta `20261106011008` | 0 (se aplicó el paquete SQL) |
| Iglesias | 7 (2 reales, 5 demostración) | 10 (todas demostración) |
| Usuarios, perfiles, miembros | 2, 1, 2 | 2, 1, 545 |
| Extensiones | `pg_stat_statements`, `pgcrypto`, `plpgsql`, `supabase_vault`, `uuid-ossp` | además `pg_net` |
| Vault | vacío | vacío |

El real tiene exactamente el esquema de las migraciones hasta `20261106011008`: las huellas del catálogo (tablas, columnas, restricciones, índices, políticas, disparadores, permisos) coinciden con las de una base local montada hasta esa migración. La única diferencia es que seis funciones del real (`aplicar_modo_alias`, `sincronizar_etapa`, `trg_minimo_superadmins`, `gestionar_consolidacion`, `info_checkin`, `registrar_checkin`) no llevan los comentarios internos del texto del repositorio; el código es el mismo. Las seis las reemplaza el traspaso.

Datos del real que el traspaso respeta (CRM confirma que `casa-reino` e `iglesia-en-linea-vive` no se tocan y que `prueba-borrado-ficticia` está pendiente de borrar desde el panel): `casa-reino` (iglesia real, modo alias, enlazada a una madre) e `iglesia-en-linea-vive` (real), cinco iglesias de demostración (`demo-con-problemas`, `demo-grande`, `demo-nueva`, `demo-pequena`, `prueba-borrado-ficticia`), 2 usuarios y 2 miembros. Nada se importa desde pruebas.

## 2. El paquete: `supabase/paquete-traspaso/` (19 archivos, ninguno de más de 20 KB, más reversión)

Se construye desde las migraciones del repositorio posteriores a `20261106011008` (29 migraciones), no desde el estado de pruebas, que aún no tiene las de la 350000 a la 400000. Solo añade. `INDICE.md` lista cada archivo con su `N de 19`, sus bytes y su sha256; `HUELLAS.sha256` lleva el sha256 completo de todos y el del conjunto.

| N de 19 | Archivo | Qué hace |
| --- | --- | --- |
| 1 | `00_comprobar_estado_real.sql` | Solo lee. Exige rol `postgres`, 33 tablas públicas, la firma antigua de `registrar_checkin` y que no esté ya aplicado nada del traspaso |
| 2 a 16 | `01_tramo_01_de_15.sql` a `15_tramo_15_de_15.sql` | Las 29 migraciones compiladas, en orden, partidas entre sentencias en 15 tramos de 11 a 18,5 KB. Cada tramo es un solo bloque (se aplica entero o no se aplica nada), **se puede aplicar solo y repetir sin error** (si su último objeto nuevo ya existe, no hace nada), falla si falta el tramo anterior y termina con una fila `ok: tramo i de 15 aplicado` |
| 17 | `16_DROP_HAROLD_firma_antigua_registrar_checkin.sql` | **Lo único destructivo**: quita la firma de 6 parámetros de `registrar_checkin` que el real tiene y que la migración nueva sustituye (`if exists`, repetible). Solo quita una función, no toca datos. Se aplica a mano, **justo después del tramo 15** |
| 18 | `17_verificacion.sql` | Solo lee. 18 huellas del esquema; todas deben salir `ok` |
| 19 | `18_registro_migraciones.sql` | Paso aparte, solo tras verificar: inserta las 29 versiones en `supabase_migrations.schema_migrations` con `created_by` vacío. Repetible |

Complementos: `reversion/R01` a `R07` (reversión, de 7 a 17 KB cada uno, solo si Gerencia lo ordena), `sembrar_iglesias_prueba.sql` (demostraciones, con la mega como `prueba-mega` porque `casa-reino` es real), `despues/programar.sql` y `despues/verificar.sql` (tarea de purga), `funciones.json` (funciones de borde con sha256 de cada archivo) y `CAMBIOS_SOBRE_LAS_MIGRACIONES.md` (las 71 diferencias entre el compilado y el texto original, una por una).

**Ningún archivo de aplicación contiene `drop`, `delete from` ni `truncate`**; la comprobación es automática y falla si aparece alguno. Para lograrlo, el compilador hace cuatro cosas, todas listadas en `CAMBIOS_SOBRE_LAS_MIGRACIONES.md`: quita las guardas `drop policy/trigger/constraint if exists` de objetos que aún no existen; cuando una migración sustituye algo creado antes en la misma cadena (cuatro políticas de soporte, restricciones de evidencias, firmas de `registrar_checkin`, `adn_registrar_consentimiento` y `adn_aplicar_consentimiento`), deja solo la definición final; manda a `DROP_HAROLD` lo que reemplaza algo que el real ya tiene; y sustituye la limpieza de asistencias duplicadas (un `delete`) por una comprobación que falla si hubiera duplicados, porque el real tiene 0 asistencias.

### Prueba de que sirve [E, `scripts/entorno/generar-traspaso.sh`, repetible]

El script monta en local el estado del real con datos sintéticos que imitan sus situaciones (iglesia real, demostración, modo alias con madre, iglesia en receso, una `casa-reino` real) y comprueba, en este orden:

1. Aplicar el paquete compilado da un esquema **idéntico**, comparado con `pg_dump`, al de aplicar las migraciones originales sin tocar.
2. Los **datos** quedan idénticos en las 56 tablas (filas sin fechas ni ids), y las filas de iglesias, personas, zonas, casas, asistencias y eventos siguen siendo las mismas.
3. La verificación del paquete da sus 18 comprobaciones en verde.
4. La siembra de demostraciones crea las suyas con `es_demo = true` y no toca ninguna existente, `casa-reino` incluida.
5. El registro de migraciones inserta las 29 versiones y se puede repetir sin duplicar.
6. Ningún archivo de aplicación contiene una orden destructiva.
7. La reversión devuelve el **esquema y los datos exactamente** al estado de partida.

[NV] Lo que no se ha podido probar desde aquí: aplicar con la herramienta de Gerencia sobre Supabase real. Dos avisos: si la herramienta quita los comentarios del cuerpo de las funciones, la huella `b03_funciones_con_su_codigo` fallará aunque el código sea el mismo (el real ya muestra ese efecto en seis funciones); en ese caso la diferencia son solo comentarios y se comprueba por la huella del código sin comentarios. Y, si la herramienta corta un tramo por su tamaño o su contenido, se repite solo ese (es repetible) y se dice cuál: no se esquiva el control.

## 3. Orden de ejecución

0. **Coordinación con «Vive ADN CRM»** (dueña del real). Respuesta recibida el 17 de noviembre, con lecturas suyas: no hay migraciones del real posteriores a `20261106011008`; las nueve funciones que cambian son idénticas al repositorio salvo comentarios y ninguna se tocó a propósito, así que se pueden reemplazar; no usa Vault, `pg_cron` ni `pg_net` (el real tiene `supabase_vault` con 0 secretos; `pg_cron` y `pg_net` no están instalados); `invitaciones` lleva `verify_jwt` apagado **a propósito** (`docs/MULTITENANT.md`, apartado 3) y no se cambia. Regla del entorno único: toda iglesia de prueba lleva `es_demo = true` y slug con prefijo `demo-` o `prueba-`.
   **Orden decidido**: primero este traspaso, con la versión final de `trg_sembrar_roles` del repositorio (conserva `sembrar_eventos` y `sembrar_formacion` y añade `sembrar_comunicacion`); después CRM rehace sobre él sus tres PR con migraciones sin aplicar: #31 `credenciales_miembro` (`20261106020000`, que añade `sembrar_credencial` a `trg_sembrar_roles`), #35 precios (`20261116120000`) y #36 altas (`20261116130000`, apilada sobre #35). **Cuando el paquete esté aplicado y verificado, hay que avisar a CRM** (Gerencia o esta sesión): hasta entonces no puede rebasar.
1. **Punto de restauración** del real antes de empezar (copia o PITR de Supabase) **[NV]**. Tiene datos reales mínimos, pero es lo único que no se puede rehacer.
2. Comprobar las huellas del paquete: `sha256sum -c HUELLAS.sha256`.
3. Aplicar `00` y exigir «ok». Después los tramos `01` a `15`, uno a uno, parando en el primer error (cada uno devuelve su fila `ok: tramo i de 15 aplicado`; si un tramo se corta, se repite solo ese). Después `16_DROP_HAROLD` a mano, sin pausa. Después `17_verificacion`: todas las filas `ok`.
4. Desplegar las funciones de borde (apartado 4) **después** de `16_DROP_HAROLD`, porque mientras conviven las dos firmas de `registrar_checkin` una llamada de 6 argumentos sería ambigua.
5. Sembrar demostraciones: `sembrar_iglesias_prueba.sql`.
6. Activar `pg_cron` y `pg_net` (panel de Supabase, Database, Extensions), crear los secretos de Vault y de las funciones (apartado 5) y aplicar `despues/programar.sql`; comprobar con `despues/verificar.sql`.
7. Apuntar Vercel (apartado 6) y redesplegar.
8. `18_registro_migraciones.sql`, ya con todo verificado.
9. Gerencia comprueba con `npm run check:entorno` y recorre los flujos principales. Solo entonces Harold borra `viveadn-pruebas`.

**Reversión.** `reversion/R01` a `R07`, en ese orden, solo por orden de Gerencia. Si ya se había aplicado `16_DROP_HAROLD`, la reversión recrea la firma antigua de `registrar_checkin` (probado). Quitar la tarea de purga: `scripts/entorno/purga-programada/desprogramar.sql`.

## 4. Funciones de borde

El real tiene 7 (`dar-publico` v2, `verificar-certificado` v1, `checkin-evento` v2, `plataforma` v8, `registro-iglesia` v2, `invitaciones` v3, `red-resumen` v1). El repositorio tiene 11. `funciones.json` lista cada archivo con su sha256.

| Función | En el real | Acción | `verify_jwt` |
| --- | --- | --- | --- |
| `plataforma` | v8 | Redesplegar (acciones de soporte, facturación, purga, agregados) | sí |
| `checkin-evento` | v2 | Redesplegar (nueva firma de `registrar_checkin`, doble confirmación) | sí |
| `datos-iglesia` | no existe | Desplegar | sí |
| `enviar-confirmaciones` | no existe | Desplegar | **no** (la llama la tarea con su clave) |
| `confirmar-suscripcion` | no existe | Desplegar | **no** (enlace público) |
| `baja` | no existe | Desplegar | **no** (enlace público) |
| `dar-publico`, `verificar-certificado`, `registro-iglesia`, `red-resumen` | existen | Comparar el sha256 con `funciones.json`; redesplegar solo si difiere | sí |

La función `plataforma` que se redespliega ya lee el cuerpo como texto con tope de 32 KB: responde 413 si el tamaño declarado o el real lo supera y 400 si no es un objeto JSON (`leerCuerpoJson`, con prueba). `supabase/functions/politicas.json` ya está en esta rama, con el formato de CRM (rama `seg/superficie-y-funciones`, fusionada): `datos-iglesia` con `verify_jwt` sí; `baja` y `confirmar-suscripcion` sin JWT con `token_en_enlace`; `enviar-confirmaciones` sin JWT con `secreto_de_servidor` y `sin_navegador`. Esas cuatro funciones leen el cuerpo con `req.text()` y un tope (`MAX_CUERPO`, 4 KB; 16 KB en `datos-iglesia`; 1 KB en `enviar-confirmaciones`) y responden 413 si lo declarado o lo leído lo supera. `npm run test:funciones` pasa con las 11 funciones. Al desplegar, `verify_jwt` debe ser exactamente el de `politicas.json` y `funciones.json`.
Cambió también la política de `adn_novedades_vistas` (ahora filtra además por iglesia, regla nueva de CRM en `permisos.sql`): está en la migración 350000, ya recompilada en los tramos 13 y 14.

| `invitaciones` | v3 | Redesplegar solo si su sha256 difiere. **`verify_jwt` se queda en `false`**: es a propósito (acciones públicas con token; las autenticadas validan con `auth.getUser`). El manifiesto ya lo refleja | **no** |

## 5. Vault, secretos y tarea programada

Hoy el Vault del real está vacío y no tiene `pg_net` ni `pg_cron` **[E]**.

**Vault** (Database, Vault; los valores no se escriben en archivos ni en mensajes):

| Nombre | Qué es |
| --- | --- |
| `adn_cron_secret` | 32 caracteres o más; el mismo valor que el secreto de función `ADN_CRON_SECRET` |
| `adn_anon_key` | La clave pública (anon, formato JWT) del real |
| `adn_funciones_url` | `https://xrjbvjqhpwjjtcfdlsbq.supabase.co`, sin barra final |

**Secretos de las funciones** (Edge Functions, Secrets; `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` los inyecta la plataforma):

| Secreto | Valor | Nota |
| --- | --- | --- |
| `ADN_ORIGENES_EXTRA` | Direcciones `https` exactas de la web, separadas por comas, máximo 10 | Sin él, el navegador bloquea las llamadas por CORS. Las vistas previas por despliegue no sirven: hace falta un alias estable de la rama |
| `ADN_CRON_SECRET` | El mismo valor que `adn_cron_secret` | Abre solo la vía de la tarea programada |
| `ADN_WEB_URL` | Dirección de la web | Va en los enlaces de los correos de confirmación |
| `ADN_CONFIRMACION_ACTIVA`, `ADN_ENVIO_ACTIVO`, `ADN_EMAIL_ALERTAS`, `ADN_EMAIL_SOPORTE`, `ADN_ENVIO_PLAN`, `ADN_ENVIO_TOPE_GLOBAL` | **Sin definir** | El correo masivo y la doble confirmación siguen apagados |

Tarea programada: `despues/programar.sql` crea `adn-purga-vencidas` (diaria, 03:15 UTC, hasta 10 iglesias por pasada) y `adn-avisar-purga` (08:30 UTC, apagada mientras no haya envío). Comprueba las extensiones y los tres secretos antes de programar y falla con un mensaje claro si falta alguno. `despues/verificar.sql` muestra las tareas y su última pasada, y «Sistema» en el Panel Maestro lo enseña.

## 6. Vercel: proyecto `viveadn` (`prj_RalAvIob926nVGnAHRSD24CZbeG4`, equipo VisualizaStudio)

Lectura del 17 de noviembre [E]: el proyecto ya tiene `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` apuntando al **real** en los tres entornos (producción, vista previa y desarrollo). Encima, tres variables solo de la rama `gerencia/contexto-2026-11-11` (vista previa) lo desvían a pruebas: `VITE_SUPABASE_URL` (id `2sZoaT9A4MFCZqv2`), `VITE_SUPABASE_ANON_KEY` (id `rBQLWQigMEJR8V9J`) y `VITE_REGION_DATOS` (id `7BFwdaxGOgow1cp3`). `VITE_REGION_DATOS` no existe en el nivel general, y `VITE_ENTORNO` no está definida.

Plan, después de verificar el traspaso y desplegar las funciones:

1. **Borrar las tres variables propias de la rama.** La rama y las demás vistas previas caen entonces en los valores generales, que ya son los del real.
2. **Añadir `VITE_REGION_DATOS=eu-west-1`** en producción, vista previa y desarrollo (la región del real es `eu-west-1`; los textos legales la muestran).
3. **Añadir `VITE_ENTORNO=pruebas` en producción y vista previa** mientras todo sea de pruebas. Sin ella, producción se comporta como `produccion` y el Panel Maestro deja las demostraciones fuera de las cifras por defecto; con ella dentro. Al lanzar, se cambia a `produccion`.
4. Dejar vacías las variables legales (`VITE_LEGAL_NIF`, `VITE_LEGAL_DOMICILIO`, `VITE_EMAIL_LEGAL`, `VITE_EMAIL_SOPORTE`, `VITE_LEGAL_REGISTRO`): siguen pendientes de Harold.
5. **Volver a desplegar** (las `VITE_` entran en la compilación): rama y producción.
6. **Supabase Auth del real**: la dirección del sitio y las URL de redirección deben incluir el dominio de producción y el alias estable de la rama; si no, las invitaciones y el inicio de sesión desde la vista previa fallan **[NV]**.
7. `ADN_ORIGENES_EXTRA` con ese mismo alias estable (apartado 5).
8. Comprobar con `npm run check:entorno` y `/api/salud`.

La rama `gerencia/contexto-2026-11-11` es la que contiene todo el trabajo; ninguna vista previa antigua debe seguir apuntando a `viveadn-pruebas` antes de borrarlo (se comprueba en la lista de despliegues).

## 7. Qué no hace este traspaso

- No importa ninguna fila de pruebas ni toca `casa-reino`, `iglesia-en-linea-vive`, usuarios ni miembros.
- No enciende el correo masivo, la doble confirmación ni ningún aviso del sistema.
- No toca el almacenamiento (los dos cubos ya son idénticos) ni Auth.
- No cambia `verify_jwt` de ninguna función existente.
- No incluye la fase 4 del seguimiento, que sigue en espera.

## 8. Riesgos a revisar con Gerencia y CRM

| Riesgo | Mitigación |
| --- | --- |
| Choque con las migraciones sin aplicar de CRM (#31, #35, #36), sobre todo `trg_sembrar_roles` | Se aplica primero este traspaso y CRM rebasa después; la comprobación `00` falla si el real no tiene 33 tablas o ya tiene objetos del traspaso |
| La herramienta de aplicación quita comentarios de las funciones | La huella `b03` puede fallar solo por eso; se compara sin comentarios |
| Entre los tramos y `16_DROP_HAROLD` conviven dos firmas de `registrar_checkin` | Aplicar `16_DROP_HAROLD` justo después del tramo 15, sin pausas, y no desplegar `checkin-evento` antes. Mientras conviven las dos firmas, una llamada del check-in QR con 6 argumentos puede fallar por ambigüedad **[H]**: es una ventana de minutos, y el real tiene 0 registros de check-in |
| La herramienta de base de datos corta un archivo | Ninguno pasa de 20 KB. Si se corta uno, se repite solo ese tramo (es repetible) y se dice cuál para reducirlo o aislarlo; no se esquiva el control |
| Las demostraciones nuevas aparecen en el Panel Maestro del real | Es lo pedido; con `VITE_ENTORNO=pruebas` entran en las cifras por defecto y el interruptor las saca |
