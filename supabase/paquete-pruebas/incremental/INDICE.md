# Incremental del paquete de aplicación (tras 20261111370000)

Para un proyecto que ya tiene el paquete completo aplicado hasta la migración 20261111370000. Generado por `scripts/entorno/generar-paquete.sh`; no sustituye al paquete completo (que sigue valiendo para un proyecto vacío).

| Archivo | Bytes | Contenido |
| --- | --- | --- |
| `01_aplicar_incremental.sql` | 2208 | 20261111380000_adn_purga_tarea_estado |
| `99_verificacion_incremental.sql` | 1555 | Verificación de lo añadido (solo lectura) |

**Orden.** 1) Aplicar `01_aplicar_incremental.sql` una sola vez y detenerse si falla (avisar a Desarrollo con el texto del error). 2) Ejecutar `99_verificacion_incremental.sql`: todas las filas con `ok = true` y `zz_todo_ok` en `true`. Repetirlo no hace daño (las funciones se crean con `create or replace` y los permisos se repiten tal cual), pero no hace falta.

**Reversión.** Está escrita y probada (`supabase/reversiones/`), pero solo se ejecuta si Gerencia lo ordena.
