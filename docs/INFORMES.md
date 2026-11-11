# Informes en PDF y Excel

Desde Reportes, quien tiene permiso descarga tres informes en PDF o en Excel: miembros, asistencia y crecimiento. Etiquetas: **[V]** verificado ejecutándolo en esta sesión, **[NV]** no verificable aquí. Todo lo verificado usa datos sintéticos.

## Qué contiene cada informe

| Informe | Permiso | Contenido |
| --- | --- | --- |
| Miembros | `miembros.exportar` (dato sensible: lleva datos personales) | Resumen (total, activos, inactivos, bautizados, con correo, con teléfono, sin casa), cifras por nivel de compromiso y la lista completa con código, nombre, apellido, correo, teléfono, nacimiento, casa, nivel, bautizado, conversión, activo y fecha de registro. Apaisado |
| Asistencia | `reportes.ver` | Un período de 4 a 52 semanas: resumen y porcentaje de reuniones de casa y de eventos, gráfico de presentes por semana, y tablas por semana, por casa de oración (con personas distintas) y por evento |
| Crecimiento | `reportes.ver` | Los últimos 6 a 36 meses: miembros registrados, nuevos, conversiones, bautizos y consolidaciones iniciadas y completadas, con gráfico de nuevos por mes y tabla mensual con el acumulado |

El PDF lleva cabecera con el nombre de la iglesia y la fecha, tablas que repiten su cabecera en cada página, gráfico de barras y "Página X de N". El Excel lleva una hoja de resumen y una hoja por tabla, con fechas reales, números con formato, cabecera fija, filtro y anchos de columna. Los textos salen en el idioma de quien descarga (español, inglés, francés y portugués).

## Cómo se garantiza que las cifras son las de la iglesia

Cuatro funciones de lectura (`adn_informe_crecimiento`, `adn_informe_asistencia`, `adn_informe_miembros_resumen` y `adn_informe_miembros`) se ejecutan con los permisos de quien las llama. La seguridad por filas decide qué cuenta, así que un informe nunca incluye lo que esa persona no podría ver en pantalla, y cada función exige además el permiso de su informe [V, 48 comprobaciones en `supabase/tests/adn_informes.sql`: cifras exactas, ventanas de fechas, un colaborador y un líder de casa rechazados, un visitante rechazado, y aislamiento entre iglesias en las tres funciones]. Solo leen: la migración no toca tablas ni datos y su reversión solo borra las funciones.

## Cómo se verifican los archivos

`npm run test:informes` genera los archivos y los abre con lectores independientes que no son los míos: `pypdf` en modo estricto y `pdfplumber` para el PDF, `openpyxl` para el Excel [V]:

- Un informe de 420 miembros ocupa varias páginas apaisadas, cada miembro sale una sola vez, la cabecera de la tabla se repite, el pie dice "Página N de total" con el total real, las propiedades llevan el título y los paréntesis, las comillas, la barra invertida y los acentos sobreviven.
- Un Excel de 12.000 filas se vuelve a leer con las 12.000 filas; las fechas son fechas, los números son números, el panel está congelado y el filtro cubre exactamente los datos.
- Los tres informes se construyen en los cuatro idiomas sin que falte una clave. La prueba cazó dos defectos reales mientras se escribía: `Intl` usa en francés un espacio estrecho que WinAnsi no tiene (salía como `?`), y una columna demasiado estrecha recortaba el código del miembro.
- También se miraron a ojo, renderizados a imagen, el PDF en español y en francés, y el Excel se abre en LibreOffice [V].

## Seguridad de los archivos

Un texto que empieza por `=`, `+`, `-` o `@` (por ejemplo un nombre mal puesto en un contacto importado) se guarda en el Excel como texto y no se evalúa como fórmula, a diferencia de lo que pasa con un CSV abierto en una hoja de cálculo [V: se lee de vuelta como texto]. El informe de miembros avisa en pantalla de que contiene datos personales.

## Límites, sin edulcorar

- **PDF y alfabetos no latinos.** El PDF usa Helvetica estándar, sin incrustar tipografías: los caracteres que no son del alfabeto latino (chino, árabe, ruso, emoji) salen como `?`. El Excel conserva todo. Incrustar una tipografía Unicode lo arreglaría a costa de varios cientos de kilobytes por archivo.
- **Celdas largas.** En el PDF una celda que no cabe se recorta con `...`; el Excel lleva el texto completo.
- **Tamaño.** Se generan en el navegador. Con 12.000 filas el PDF tarda unos segundos; una iglesia con muchas más puede necesitar generarse en el servidor [NV, no se midió en navegadores reales]. La lista de miembros se pide por páginas de 1000.
- **Crecimiento y fechas de registro.** "Nuevos miembros" cuenta por la fecha en que se registró la persona en ViveADN. Quien se importó de golpe aparece en el mes de la importación aunque se convirtiera años antes; por eso el informe trae aparte las conversiones, que cuentan por la fecha de conversión cuando existe.
- **Sin gráficos nativos en Excel.** El gráfico solo está en el PDF; el Excel trae los mismos datos en su tabla.
- **Sin registro de quién descarga.** No queda constancia de quién bajó el informe de miembros. Recomendado para una segunda fase, dado que lleva datos personales.
- [NV] La pantalla de descarga compila y pasa tipos, pero no se ejecutó en un navegador contra una base real. El CI instala `openpyxl`, `pypdf` y `pdfplumber` con versiones fijas en un paso nuevo del flujo, que tampoco se ejecutó aquí.
