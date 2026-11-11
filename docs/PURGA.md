# Purga programada, plazo de las copias y libro de purgadas

Estado a 11 de noviembre de 2026. Etiquetas de evidencia: **[E]** informado por Desarrollo con una prueba repetible, **[H]** deducido, **[NV]** no verificable desde aquí. Gerencia aprobó el diseño de este documento el mismo día: opción A para la tarea programada, 14 días para las copias propias y un libro externo de purgadas. Lo escrito en el repositorio funciona solo en local. **Nada está activo en una base real**: no hay tarea programada, el secreto no existe y no se ha tocado ninguna base de producción ni de pruebas de Supabase.

## 1. Dónde estamos

- Una iglesia que se da de baja pasa a borrado suave con un plazo **fijo de 30 días**, durante el cual se puede recuperar [E, `adn_ciclo_vida.sql`, `adn_purga_programada.sql`].
- Pasado el plazo, la purga la lanza hoy **a mano** un administrador desde el panel (acción `purgar_vencidas` de la función `plataforma`), por lotes de hasta 20. La vía para una tarea programada existe (cabecera `x-adn-cron` con el secreto `ADN_CRON_SECRET`) pero está cerrada mientras el secreto no exista [E].
- Los textos legales dicen desde las versiones 1.2 de la política de privacidad y 1.1 de los términos que los datos desaparecen de los sistemas activos a los 30 días de la baja y de las copias de seguridad en un máximo de 14 días más (`docs/LEGAL.md`). Esa frase solo es cierta si la purga ocurre sola y las copias rotan a 14 días: ambas cosas están diseñadas aquí y ninguna está activa.
- El artículo 28.3.g del RGPD, cotejado con el texto oficial, obliga al encargado a suprimir o devolver los datos al terminar el servicio y a suprimir las copias existentes, salvo que una norma exija conservarlas. Si la rotación de copias basta como supresión es una pregunta para el abogado, recogida en `docs/LEGAL.md`.

## 2. La tarea programada (opción A, aprobada)

**Qué hace**: una llamada cada 6 horas a la función `plataforma` con `{"accion":"purgar_vencidas"}` y la cabecera `x-adn-cron`. Es idempotente, purga cada iglesia por completo (base, archivos y cuentas de acceso) y deja su rastro en la auditoría, que sobrevive a la purga [E]. Con lotes de 5 por llamada (máximo 20) se purgan hasta 20 iglesias al día y cada una queda purgada, como mucho, unas 6 horas después de vencer. Si hubiera más vencidas que el lote, la siguiente llamada continúa: la respuesta incluye cuántas quedan.

**Cómo, con `pg_cron` y `pg_net` dentro de la propia base**, de modo que el secreto no sale de la plataforma. Reparto de tareas acordado con Gerencia:

1. Gerencia **genera** el secreto (al menos 32 caracteres) y lo guarda en la bóveda de secretos de la plataforma con el nombre `adn_cron_secret`, y lo define también como `ADN_CRON_SECRET` en los secretos de la función. Desarrollo no lo genera, no lo ve y no se escribe en ningún archivo del repositorio.
2. Gerencia verifica en la **rama de pruebas** que las extensiones están disponibles y activas **[NV]**: en la base local no existen, así que nada de esto se ha podido ejecutar aquí.
3. Con esos dos pasos hechos, se programa la tarea con un esquema como este (**sin aplicar**; los marcadores se sustituyen en la rama de pruebas, no en el repositorio):

```sql
-- Cada 6 horas. <FUNCIONES> es la dirección de las funciones del proyecto; el secreto se lee de la bóveda.
select cron.schedule('adn-purga-vencidas', '0 */6 * * *', $$
  select net.http_post(
    url := '<FUNCIONES>/functions/v1/plataforma',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-adn-cron', (select decrypted_secret from vault.decrypted_secrets where name = 'adn_cron_secret')),
    body := '{"accion":"purgar_vencidas"}'::jsonb);
$$);
```

4. Se comprueba de extremo a extremo en la rama de pruebas con una iglesia ficticia de plazo vencido: que la tarea corre, que purga y que el estado (apartado 5) vuelve a cero. Solo entonces se plantea hacerlo en la base real, y eso requiere la aprobación de Harold.

Una limitación de la opción A: `pg_net` guarda las respuestas en la propia base, de modo que **el libro externo (apartado 4) no puede ser la respuesta de la tarea**. Lo alimenta otro proceso, descrito allí.

## 3. El plazo de las copias: X = 14 días

Línea de tiempo con la política aprobada:

| Momento | Qué pasa con los datos de la iglesia |
| --- | --- |
| Día 0 | Baja. Borrado suave: suspendida y recuperable |
| Día 30 | Vence el plazo. Desde aquí, la purga programada |
| Día 30 y unas 6 horas | Purga completa de los sistemas activos |
| Hasta el día 44, más el retraso de la purga | Las copias que contenían los datos se renuevan y los datos desaparecen de ellas |

Copias propias (volcados cifrados fuera de la plataforma, `docs/RESTAURACION.md`) con retención de **14 días** y borrado automático de las más antiguas: unos 44 días desde la baja como máximo, más las horas que tarde la purga. Esa rotación **no está configurada ni se ha demostrado [NV]**: no existe ninguna copia propia programada. Las copias de la plataforma dependen del plan y su retención hay que leerla en el panel **[NV]**; si es más larga que 14 días, la frase de los textos legales no sería cierta y manda la retención más larga. Es una comprobación previa a publicar los textos.

## 4. El libro externo de purgadas

Restaurar una copia anterior a una purga resucita los datos de una iglesia ya borrada, y la auditoría de la purga vive en la misma base, así que la restauración la pierde. La solución aprobada es un **libro fuera de la base** con solo el identificador de cada iglesia purgada y la fecha: ningún dato de personas ni de iglesias.

**Qué hay hecho [E, migración `20261111250000_adn_purgas_libro`, 27 comprobaciones en `adn_libro_purgas.sql`, reversión probada]**

- `adn_purgas_desde(p_desde)` exporta el libro desde la auditoría: identificador y fecha, por orden de purga, sin ningún otro campo. Con fecha devuelve lo posterior o igual; sin ella, todo.
- `adn_repurgar_registradas(p_ids, p_actor)` toma identificadores del libro y marca como vencidas las iglesias que reaparecen en la base restaurada; ignora las que ya no existen y rechaza listas nulas o de más de 5000. No borra por sí misma: la purga normal las elimina después con sus archivos y cuentas. Repetirla con el libro entero es inocuo.
- En la función `plataforma`: la acción `libro_purgas` (admite la clave de la tarea), la acción `repurgar_registradas` (solo administrador, exige `confirmar: "REPURGAR"` y queda auditada) y el campo `registro` en la respuesta de `purgar_vencidas`. Estas tres piezas están comprobadas solo en tipos (tsc con un sustituto de Deno), **no se han ejecutado contra una función desplegada [NV]**.

**Cómo se mantiene fuera de la base [H, no existe aún]**: el mismo proceso que hace la copia propia, fuera de la plataforma, llama a `libro_purgas` con la fecha de la última entrada que ya tiene y la añade a un archivo que guarda junto a las copias, con el mismo cifrado. Cuanto más a menudo se actualice, menos purgas pueden perderse: las que ocurran después de la última actualización y antes de un desastre no estarían en el libro, igual que los datos posteriores a la última copia no están en la copia. Por eso conviene actualizarlo al terminar cada pasada de purga y no solo con la copia diaria.

**Uso tras una restauración**: antes de abrir la base restaurada al público, `repurgar_registradas` con el libro entero y después `purgar_vencidas` hasta que `restantes` sea cero. Es una condición para dar por buena una restauración real (`docs/RESTAURACION.md`, paso 7).

## 5. Vigilancia

`adn_purga_estado()` devuelve solo cifras: iglesias en borrado suave, vencidas, horas de la más atrasada y un `atrasada` que salta a las 48 horas [E, 28 comprobaciones en `adn_purga_programada.sql`]. Ahora se ve de dos formas:

- **En el panel de superadministración** hay una tarjeta «Purga programada» que muestra las tres cifras y un aviso verde o rojo según `atrasada`. Si la consulta falla, la tarjeta lo dice y el resto del panel sigue funcionando. Usa la acción `estado_purga` de `plataforma` (admite también la clave de la tarea, para un vigilante). Está verificada con tipos, compilación y las pruebas de la batería; **no la he visto renderizada en un navegador con una sesión de administrador [NV]**.
- **Aviso por correo a Harold**: aprobado, pero hoy no existe un remitente propio de la plataforma fuera de las invitaciones y de la confirmación (apagada). Mientras tanto vale el indicador del panel. Cuando haya remitente, el aviso consiste en una llamada a `estado_purga` desde el programador y un correo si `atrasada` es verdadero; no está escrito.

## 6. Qué hay hecho y qué no

| Pieza | Estado |
| --- | --- |
| `adn_purga_estado`, con su prueba y su reversión | Hecho, solo local [E]. Migración `20261111240000` |
| Libro de purgadas y re-purga, con su prueba y su reversión | Hecho, solo local [E]. Migración `20261111250000` |
| Acciones `estado_purga`, `libro_purgas`, `repurgar_registradas` y tarjeta del panel | Escritas y comprobadas en tipos y compilación; sin ejecutar desplegadas [NV] |
| Purga por lotes, plazo de 30 días, recuperación y auditoría que sobrevive | Ya existían y están probados [E] |
| Tarea programada con `pg_cron` y `pg_net` | **Diseñada y aprobada, nada creado**; depende de Gerencia (secreto en la bóveda, extensiones en la rama de pruebas) |
| Secreto `ADN_CRON_SECRET` | **No existe**; lo genera Gerencia |
| Archivador del libro junto a las copias propias | Sin hacer; depende de que exista la copia propia |
| Aviso por correo a Harold | Sin hacer; espera a que exista un remitente |
| Rotación de 14 días de las copias propias y retención de las de la plataforma | **[NV]**; se lee y se configura en la plataforma |
| Texto legal con los 14 días | Hecho: política de privacidad 1.2 y términos 1.1 [E, `npm run check:legal`] |

Decisiones que siguen sin ser de Desarrollo: quién guarda el archivo del libro y su clave; si el abogado acepta la rotación de copias como cumplimiento del 28.3.g; y quién recibe el aviso de purga atrasada cuando exista remitente.
