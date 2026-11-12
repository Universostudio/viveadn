# Paquete de aplicación del esquema de Vive ADN (proyecto de pruebas)

Generado por `scripts/entorno/generar-paquete.sh`. Reproduce `scripts/entorno/montar-rama.sh` sin psql: esquema base, catálogo y 48 migraciones, en archivos SQL numerados.

**Reglas.** Solo sobre un proyecto de pruebas VACÍO. Aplicar los archivos en orden con una herramienta que ejecute SQL; **detenerse en el primer error** y avisar a Desarrollo con el texto del error. No hay reintento seguro: un archivo que falla puede dejar el proyecto a medias, y entonces se recrea el proyecto vacío. Cada archivo empieza con su propio `set search_path`, así que no depende de la conexión. Los archivos no contienen claves ni datos de personas.

## Orden

| Archivo | Bytes | Contenido | Privilegios que exige |
| --- | --- | --- | --- |
| `00_comprobar_base_vacia.sql` | 1122 | Comprobación de base vacía (solo lectura) | Ninguno |
| `01_aplicar_01.sql` | 47.299 | schema/esquema_completo, schema/seed, 20261024013525_roles_y_permisos_por_iglesia, 20261024015036_catalogo_modulos_y_planes, 20261024015537_panel_plataforma_base, 20261024015554_plataforma_auditoria | CREATE EXTENSION (ya existen: no hace nada); Claves foráneas a auth.users (exige REFERENCES sobre esa tabla); CREATE SCHEMA private |
| `02_aplicar_02.sql` | 58.703 | 20261025080000_endurecer_aislamiento_y_privilegios, 20261027090000_permisos_explicitos, 20261030000000_roles_superadmin_zona_colaborador, 20261030010000_invitaciones, 20261104133745_enlaces_dar, 20261105021940_eventos_asistencia, 20261105022526_asistencia_evento_ver_propia, 20261105025055_checkin_qr, 20261105025422_checkin_serializar | ALTER DEFAULT PRIVILEGES FOR ROLE postgres (exige ser postgres o miembro) |
| `03_aplicar_03.sql` | 53.123 | 20261105030433_dar_plantillas, 20261105080527_red_iglesias, 20261105195348_registro_autoservicio, 20261105210545_limites_plan_e_indices, 20261105210912_referencias_compuestas, 20261105211108_limites_plan_definer, 20261105211929_ciclo_vida_iglesia, 20261105212425_ciclo_vida_guardia, 20261105221251_exportar_borrar_iglesia, 20261105221748_exportar_sin_secretos_anidados, 20261105222115_archivos_por_iglesia, 20261105223418_modo_alias, 20261105231653_op72_avanzado, 20261105232000_completado_at_automatico | Políticas sobre storage.objects (propiedad de supabase_storage_admin); INSERT en storage.buckets |
| `04_aplicar_04.sql` | 57.014 | 20261105235306_motor_formacion, 20261106000222_motor_formacion_endurecer, 20261106000439_motor_formacion_cerrojo, 20261106011008_certificados_formacion, 20261111120000_adn_ciclo_vida, 20261111130000_adn_exportacion, 20261111140000_adn_importar_contactos | Ninguno especial |
| `05_aplicar_05.sql` | 57.590 | 20261111150000_adn_informes, 20261111160000_adn_comunicacion, 20261111170000_adn_panel_inicio, 20261111180000_adn_descargas_informe, 20261111190000_adn_consentimiento | Ninguno especial |
| `06_aplicar_06.sql` | 45.676 | 20261111200000_adn_consentimiento_auditoria, 20261111210000_adn_consentimiento_evidencia, 20261111220000_adn_checkin_canales | Ninguno especial |
| `07_aplicar_07.sql` | 41.378 | 20261111230000_adn_doble_confirmacion, 20261111240000_adn_purga_estado, 20261111250000_adn_purgas_libro, 20261111260000_adn_exportacion_paginada, 20261111270000_adn_autoservicio_datos, 20261111280000_adn_envios_topes | Ninguno especial |
| `99_verificacion.sql` | 6478 | Verificación del esquema (solo lectura) | Lectura del catálogo y de storage.buckets |

## Resultado esperado

- `00`: una fila `ok: base vacía de Supabase, rol postgres`. Si el rol no es `postgres`, falla a propósito (las migraciones fijan permisos por defecto para ese rol).
- `01` a `07`: sin filas de error. Los avisos `NOTICE` de objetos que no existían son normales.
- `99`: todas las filas con `ok = true` y la última, `zz_todo_ok`, en `true`. Valores de referencia: 47 tablas en `public`, 107 funciones en `public` y `private`, 47 permisos, 40 filas de plan_modulos, 3 planes, 0 iglesias y 2 cubos de archivos.

## Qué puede fallar por privilegios (no se ha podido probar en Supabase real) [NV]

- `ALTER DEFAULT PRIVILEGES FOR ROLE postgres` (migraciones `20261025080000` y `20261027090000`): exige ejecutar como `postgres` o como miembro de ese rol. Por eso el archivo 00 lo comprueba.
- Políticas e inserción de cubos en `storage` (`20261105222115_archivos_por_iglesia`): `storage.objects` pertenece a `supabase_storage_admin`. El rol `postgres` suele poder crear políticas ahí, pero hoy no se ha comprobado. Si falla, el error será `must be owner of table objects`; avisar a Desarrollo.
- Claves foráneas a `auth.users` (esquema base): exigen REFERENCES sobre esa tabla; `postgres` lo tiene en Supabase [NV].
- `CREATE EXTENSION IF NOT EXISTS`: las extensiones ya existen, así que no hace nada.

## Funciones de borde y datos de demostración

- `funciones.json`: las 11 funciones de borde con su `verify_jwt`, sus archivos (ruta relativa, bytes y sha256 completo). Sin verificación de JWT: baja, confirmar-suscripcion, enviar-confirmaciones; las demás la llevan. Al desplegar con una herramienta, cada archivo va con su ruta relativa (`index.ts` y los que importa, como `./ciclo.ts`) y se comprueba el sha256 antes. Los imports `npm:` no necesitan nada más.
- `datos_demo.sql`: 300 personas, 6 zonas y 18 casas sintéticas **sin psql**. Exige que la iglesia `iglesia-demo` exista y esté marcada como demostración (se crea desde `/plataforma`); es de un solo uso.

## Comprobación hecha en local

En una base local vacía con un esquema `auth` mínimo, los archivos aplicados con psql tal cual (sin variables de sesión) dan una verificación con todas las filas `ok`, y un `pg_dump` del esquema idéntico al de `montar-rama.sh` (`supabase/tests/paquete_pruebas.sh`). Si el proyecto real da otro valor en alguna fila, la letra de la fila dice dónde mirar: `a` recuentos, `b` estructura (tablas, columnas, funciones con su código, restricciones, índices, políticas, disparadores), `c` permisos, `d` datos de catálogo.
