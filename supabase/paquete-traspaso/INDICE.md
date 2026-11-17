# Paquete de traspaso al proyecto real (viveadn-saas)

Generado por `scripts/entorno/generar-traspaso.sh`. Lleva el real, que tiene las migraciones hasta `20261106011008`, al estado de la rama (29 migraciones más). **Solo añade**: no importa ninguna fila de pruebas ni copia `casa-reino`. Ningún archivo de aplicación contiene drop, delete ni truncate; lo único destructivo está aislado en el archivo `DROP_HAROLD`.

## Orden (8 archivos)

| N de 8 | Archivo | Bytes | sha256 | Contenido |
| --- | --- | --- | --- | --- |
| 1 de 8 | `00_comprobar_estado_real.sql` | 1450 | `599437df3448bdcd` | Comprobación previa (solo lectura) |
| 2 de 8 | `01_aplicar_01_de_04.sql` | 60.659 | `f1af258c3e3b9f75` | adn_ciclo_vida, adn_exportacion, adn_importar_contactos, adn_informes, adn_comunicacion, adn_panel_inicio |
| 3 de 8 | `02_aplicar_02_de_04.sql` | 55.728 | `20b327dda0b50266` | adn_descargas_informe, adn_consentimiento, adn_consentimiento_auditoria, adn_consentimiento_evidencia, adn_checkin_canales |
| 4 de 8 | `03_aplicar_03_de_04.sql` | 59.716 | `5deb88ae9a934b23` | adn_doble_confirmacion, adn_purga_estado, adn_purgas_libro, adn_exportacion_paginada, adn_autoservicio_datos, adn_envios_topes, adn_plataforma_resumen, adn_checkin_nuevo_creyente, adn_asistencias_unico, adn_seguimiento_metodos |
| 5 de 8 | `04_aplicar_04_de_04.sql` | 45.971 | `4ecb93b6516bbe0e` | adn_seguimiento_metricas, adn_seguimiento_propio, adn_soporte, adn_precios_plan, adn_prueba_vencida_lectura, adn_purga_tarea_estado, adn_soporte_prueba_vencida, adn_agregados_plataforma |
| 6 de 8 | `05_DROP_HAROLD_firma_antigua_registrar_checkin.sql` | 903 | `59fce99a0d083f5b` | DROP_HAROLD: quita la firma antigua de registrar_checkin (única orden destructiva) |
| 7 de 8 | `06_verificacion.sql` | 6468 | `fa634c44673566e0` | Verificación del esquema (solo lectura) |
| 8 de 8 | `07_registro_migraciones.sql` | 1889 | `22de7b22a3d1df3b` | Registro de las migraciones en supabase_migrations (paso aparte, tras verificar) |

1. Aplicar los archivos en orden, uno a uno. **Detenerse en el primer error** y avisar con el texto del error: no hay reintento seguro de un archivo a medias.
2. El de comprobación (1 de 8) no cambia nada y debe decir «ok». Si dice otra cosa, no se sigue.
3. Tras los de aplicación, `DROP_HAROLD` (a mano), y después la verificación: todas las filas con `ok = true`.
4. Solo entonces: siembra de demostraciones (`sembrar_iglesias_prueba.sql`), funciones de borde (`funciones.json`), Vault y tareas (ver `docs/TRASPASO-AL-REAL.md`).
5. El registro en `supabase_migrations` es un paso aparte, después de verificar.

## Reversión

- `reversion/R01_revertir_01_de_02.sql` (58.020 bytes, sha256 `da76c879b307161d`): adn_agregados_plataforma, adn_soporte_prueba_vencida, adn_purga_tarea_estado, adn_prueba_vencida_lectura, adn_precios_plan, adn_soporte, adn_seguimiento_propio, adn_seguimiento_metricas, adn_seguimiento_metodos, adn_asistencias_unico, adn_checkin_nuevo_creyente, adn_plataforma_resumen, adn_envios_topes, adn_autoservicio_datos, adn_exportacion_paginada, adn_purgas_libro, adn_purga_estado, adn_doble_confirmacion, adn_checkin_canales, adn_consentimiento_evidencia
- `reversion/R02_revertir_02_de_02.sql` (29.096 bytes, sha256 `46491a4beb04443b`): adn_consentimiento_auditoria, adn_consentimiento, adn_descargas_informe, adn_panel_inicio, adn_comunicacion, adn_informes, adn_importar_contactos, adn_exportacion, adn_ciclo_vida

Se aplican en orden R01, R02… y solo si Gerencia lo ordena. Probada en local: deja el esquema idéntico al del real antes del traspaso.

## Huella

`HUELLAS.sha256` lista el sha256 completo de cada archivo y el de todo el paquete. Comprobar con `sha256sum -c HUELLAS.sha256` antes de aplicar.

Qué cambia el compilador respecto a las migraciones originales: `CAMBIOS_SOBRE_LAS_MIGRACIONES.md`.
