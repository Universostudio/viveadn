# Paquete de traspaso al proyecto real (viveadn-saas)

Generado por `scripts/entorno/generar-traspaso.sh`. Lleva el real, que tiene las migraciones hasta `20261106011008`, al estado de la rama (29 migraciones más). **Solo añade**: no importa ninguna fila de pruebas ni copia `casa-reino`. Ningún archivo de aplicación contiene drop, delete ni truncate; lo único destructivo está aislado en el archivo `DROP_HAROLD`.

## Orden (19 archivos)

| N de 19 | Archivo | Bytes | sha256 | Contenido |
| --- | --- | --- | --- | --- |
| 1 de 19 | `00_comprobar_estado_real.sql` | 1451 | `b4f1fa14da4cba0d` | Comprobación previa (solo lectura) |
| 2 de 19 | `01_tramo_01_de_15.sql` | 13.611 | `88be34fc4f9c321d` | tramo 1 de 15: adn_ciclo_vida, adn_exportacion |
| 3 de 19 | `02_tramo_02_de_15.sql` | 11.153 | `b95b56acc0665824` | tramo 2 de 15: adn_importar_contactos |
| 4 de 19 | `03_tramo_03_de_15.sql` | 16.534 | `75eeb703f1d1f1ac` | tramo 3 de 15: adn_informes |
| 5 de 19 | `04_tramo_04_de_15.sql` | 16.580 | `cc220a5705b58570` | tramo 4 de 15: adn_comunicacion |
| 6 de 19 | `05_tramo_05_de_15.sql` | 15.129 | `bfcf6a09a3018282` | tramo 5 de 15: adn_panel_inicio, adn_descargas_informe, adn_consentimiento |
| 7 de 19 | `06_tramo_06_de_15.sql` | 18.476 | `021e9c72132266e2` | tramo 6 de 15: adn_consentimiento_auditoria |
| 8 de 19 | `07_tramo_07_de_15.sql` | 16.896 | `4ea137cf4eb17154` | tramo 7 de 15: adn_consentimiento_evidencia |
| 9 de 19 | `08_tramo_08_de_15.sql` | 17.032 | `cabb766fb8dfb0cc` | tramo 8 de 15: adn_checkin_canales, adn_doble_confirmacion |
| 10 de 19 | `09_tramo_09_de_15.sql` | 16.435 | `70c1f27176e6bdd7` | tramo 9 de 15: adn_purga_estado, adn_purgas_libro, adn_exportacion_paginada |
| 11 de 19 | `10_tramo_10_de_15.sql` | 16.634 | `fad16126208b2204` | tramo 10 de 15: adn_autoservicio_datos, adn_envios_topes |
| 12 de 19 | `11_tramo_11_de_15.sql` | 14.425 | `58312144d9da5b31` | tramo 11 de 15: adn_plataforma_resumen, adn_checkin_nuevo_creyente, adn_asistencias_unico |
| 13 de 19 | `12_tramo_12_de_15.sql` | 16.516 | `ab745408ad90615d` | tramo 12 de 15: adn_seguimiento_metodos, adn_seguimiento_metricas |
| 14 de 19 | `13_tramo_13_de_15.sql` | 16.181 | `652204526c31e550` | tramo 13 de 15: adn_seguimiento_propio, adn_soporte |
| 15 de 19 | `14_tramo_14_de_15.sql` | 16.237 | `dc1cc7e23690c36b` | tramo 14 de 15:  |
| 16 de 19 | `15_tramo_15_de_15.sql` | 12.651 | `1cd5f266c2229049` | tramo 15 de 15: adn_precios_plan, adn_prueba_vencida_lectura, adn_purga_tarea_estado, adn_soporte_prueba_vencida, adn_agregados_plataforma |
| 17 de 19 | `16_DROP_HAROLD_firma_antigua_registrar_checkin.sql` | 962 | `410cc63a8b372ed3` | DROP_HAROLD: quita la firma antigua de registrar_checkin (única orden destructiva) |
| 18 de 19 | `17_verificacion.sql` | 6470 | `5155d37d6c639f61` | Verificación del esquema (solo lectura) |
| 19 de 19 | `18_registro_migraciones.sql` | 1891 | `4f298eafcb76b9a2` | Registro de las migraciones en supabase_migrations (paso aparte, tras verificar) |

1. Aplicar los archivos en orden, uno a uno, ninguno de más de 20 KB. Cada tramo se puede aplicar solo y **repetir sin error** (si ya está aplicado, no hace nada) y falla si falta el tramo anterior. **Detenerse en el primer error** y avisar con el texto del error: cada tramo es un solo bloque, así que o se aplica entero o no se aplica nada.
2. El de comprobación (1 de 19) no cambia nada y debe decir «ok». Si dice otra cosa, no se sigue.
3. Tras los de aplicación, `DROP_HAROLD` (a mano), y después la verificación: todas las filas con `ok = true`.
4. Solo entonces: siembra de demostraciones (`sembrar_iglesias_prueba.sql`), funciones de borde (`funciones.json`), Vault y tareas (ver `docs/TRASPASO-AL-REAL.md`).
5. El registro en `supabase_migrations` es un paso aparte, después de verificar.

## Reversión

- `reversion/R01_revertir_01_de_07.sql` (17.357 bytes, sha256 `714f43c0b7b9adc7`): adn_agregados_plataforma, adn_soporte_prueba_vencida, adn_purga_tarea_estado, adn_prueba_vencida_lectura, adn_precios_plan, adn_soporte, adn_seguimiento_propio, adn_seguimiento_metricas, adn_seguimiento_metodos, adn_asistencias_unico
- `reversion/R02_revertir_02_de_07.sql` (12.044 bytes, sha256 `a57bc3d2d1bc705d`): adn_checkin_nuevo_creyente, adn_plataforma_resumen, adn_envios_topes, adn_autoservicio_datos, adn_exportacion_paginada, adn_purgas_libro, adn_purga_estado
- `reversion/R03_revertir_03_de_07.sql` (14.629 bytes, sha256 `26ea5e0e42a7cd41`): adn_doble_confirmacion, adn_checkin_canales
- `reversion/R04_revertir_04_de_07.sql` (14.773 bytes, sha256 `36d641fe32491408`): adn_consentimiento_evidencia
- `reversion/R05_revertir_05_de_07.sql` (4615 bytes, sha256 `70b7204b56263113`): adn_consentimiento_auditoria
- `reversion/R06_revertir_06_de_07.sql` (17.320 bytes, sha256 `ee3af08086cd4275`): adn_consentimiento, adn_descargas_informe
- `reversion/R07_revertir_07_de_07.sql` (7683 bytes, sha256 `af2621cefa7cd616`): adn_panel_inicio, adn_comunicacion, adn_informes, adn_importar_contactos, adn_exportacion, adn_ciclo_vida

Se aplican en orden R01, R02… y solo si Gerencia lo ordena. Probada en local: deja el esquema idéntico al del real antes del traspaso.

## Huella

`HUELLAS.sha256` lista el sha256 completo de cada archivo y el de todo el paquete. Comprobar con `sha256sum -c HUELLAS.sha256` antes de aplicar.

Qué cambia el compilador respecto a las migraciones originales: `CAMBIOS_SOBRE_LAS_MIGRACIONES.md`.
