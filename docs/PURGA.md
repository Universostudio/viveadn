# Purga programada y plazo de las copias

Estado a 11 de noviembre de 2026. Etiquetas de evidencia: **[E]** informado por Desarrollo con una prueba repetible, **[H]** deducido, **[NV]** no verificable desde aquí. Es una **propuesta**: nada de esto está activo, ningún secreto se ha creado y no se ha tocado ninguna base real. La única pieza nueva en el código es una función de lectura, `adn_purga_estado`, con su prueba local.

## 1. Dónde estamos

- Una iglesia que se da de baja pasa a borrado suave con un plazo **fijo de 30 días**, durante el cual se puede recuperar [E, `adn_ciclo_vida.sql`, `adn_purga_programada.sql`].
- Pasado el plazo, la purga la lanza **a mano** un administrador desde el panel (acción `purgar_vencidas` de la función `plataforma`), por lotes de hasta 20. La vía para una tarea programada existe (cabecera `x-adn-cron` con el secreto `ADN_CRON_SECRET`), pero está **cerrada**: el secreto no existe, por decisión de Gerencia [E]. No hay ninguna tarea programada.
- Los textos legales dicen que, tras los 30 días, se produce la purga y que las copias de seguridad «pueden conservar datos durante un tiempo limitado más». Hoy eso depende de que alguien purgue, y ese «tiempo limitado» no tiene número (`docs/LEGAL.md`, apartado 5, punto 8).
- El artículo 28.3.g del RGPD, cotejado con el texto oficial, obliga al encargado a suprimir o devolver los datos al terminar el servicio **y a suprimir las copias existentes**, salvo que una norma exija conservarlas. Para que el texto sea cierto hace falta que la purga ocurra sola y que las copias tengan un plazo fijado y cumplido.

## 2. La tarea programada

**Qué hace**: una llamada periódica a la función `plataforma` con `{"accion":"purgar_vencidas"}` y la cabecera `x-adn-cron`. Es idempotente, purga cada iglesia por completo (base, archivos y cuentas de acceso) y deja su rastro en la auditoría, que sobrevive a la purga [E]. Con lotes de 5 por llamada (el valor por defecto, máximo 20), una llamada cada 6 horas purga hasta 20 iglesias al día y deja a cada una purgada, como mucho, unas 6 horas después de vencer su plazo. Si hubiera más vencidas que el lote, la siguiente llamada continúa: la respuesta incluye cuántas quedan.

**Dos opciones sin coste**; la elección es de Harold porque implica dónde se guarda el secreto:

| | Cómo | A favor | En contra |
| --- | --- | --- | --- |
| A | Una tarea de `pg_cron` dentro de la propia base que llama a la función con `pg_net`, con el secreto en la bóveda de secretos | El secreto no sale de la plataforma; no depende de ningún otro servicio | **[NV]** que el proyecto tenga esas extensiones disponibles y activas: en la base local de pruebas no están, así que no se pudo probar nada de esto aquí |
| B | Un flujo programado de GitHub Actions que llama a la función, con el secreto en los «secretos» del repositorio | No necesita extensiones; los avisos de fallo llegan por correo | El secreto vive en otro sitio. Los flujos programados corren solo desde la rama principal, con retraso posible, y se desactivan tras 60 días sin actividad en un repositorio público **[H]** |

Recomendación: A si la plataforma lo permite, B si no. En ambos casos el secreto, de al menos 32 caracteres, lo **genera y guarda una persona** (Harold o quien Gerencia designe) y solo en los secretos de la función y del programador; no lo genero yo ni se escribe en ningún archivo.

Esquema de A, **sin aplicar**, con marcadores en lugar de valores:

```sql
-- Cada 6 horas. <FUNCIONES> es la dirección de las funciones del proyecto y el secreto se lee de la bóveda.
select cron.schedule('adn-purga-vencidas', '0 */6 * * *', $$
  select net.http_post(
    url := '<FUNCIONES>/functions/v1/plataforma',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-adn-cron', (select decrypted_secret from vault.decrypted_secrets where name = 'adn_cron_secret')),
    body := '{"accion":"purgar_vencidas"}'::jsonb);
$$);
```

**Vigilancia**: `adn_purga_estado()` devuelve solo cifras (iglesias en borrado suave, vencidas, horas de la más atrasada y un `atrasada` que salta a las 48 horas por defecto) y no purga nada [E, 28 comprobaciones en `adn_purga_programada.sql`: con lotes de 2, tres vencidas se purgan en dos pasadas; lo que no ha vencido no se toca; dentro del plazo se recupera; solo el servidor la ejecuta]. Para que alguien se entere de que la tarea no corre, falta exponerla al vigilante (`docs/MONITORIZACION.md`): una acción de solo lectura en `plataforma` para la tarea programada y que el flujo de la opción B falle si `atrasada` es verdadero. No está hecho.

## 3. El plazo de las copias

Línea de tiempo con la política propuesta:

| Momento | Qué pasa con los datos de la iglesia |
| --- | --- |
| Día 0 | Baja. Borrado suave: suspendida y recuperable |
| Día 30 | Vence el plazo. Desde aquí, la purga programada |
| Día 30 y unas 6 horas | Purga completa de los sistemas activos |
| Hasta el día 30 + X | Las copias de seguridad que contenían los datos se renuevan y los datos desaparecen de ellas |

**X** es el plazo máximo de retención de las copias, **y debe decidirlo Gerencia o Harold**. Mi propuesta: copias propias (volcados cifrados fuera de la plataforma, `docs/RESTAURACION.md`) con retención de **14 días** y borrado automático de las más antiguas, lo que da un máximo de unos 45 días desde la baja; con 30 días saldrían unos 61. Las copias de la plataforma dependen del plan y su retención hay que leerla en el panel **[NV]**; si es más larga que la elegida, manda la más larga.

Si se decide X, el texto legal debería decir algo como: «Los datos desaparecen de los sistemas activos a los 30 días de la baja y de las copias de seguridad en un máximo de X días más». Es un cambio de las dos versiones (política de privacidad y términos) en los cuatro idiomas, que `npm run check:legal` obliga a registrar como versión nueva. **No lo he aplicado**: espera a que se fije X y se confirme que el abogado lo admite como forma de cumplir el 28.3.g, o si prefiere otra fórmula (por ejemplo, conservar bloqueados los datos mientras pueda haber responsabilidades, cuyo régimen en la ley orgánica no he cotejado).

## 4. Un riesgo que hay que cerrar: restaurar una copia antigua resucita lo purgado

Si se restaura una copia anterior a una purga, vuelven los datos de una iglesia que ya se había borrado. La auditoría de la purga vive en la misma base y se pierde con la restauración, así que **la base restaurada no sabe qué purgas hubo después**. Hace falta un registro fuera de la base: solo los identificadores de las iglesias purgadas y la fecha, sin datos de personas. Propuesta: que la respuesta de `purgar_vencidas` incluya esos identificadores y que el programador los anote; tras cualquier restauración se vuelven a purgar. Está sin implementar y es una condición para dar por buena una restauración real (`docs/RESTAURACION.md`, paso 7).

## 5. Qué hay hecho y qué no

| Pieza | Estado |
| --- | --- |
| `adn_purga_estado`, con su prueba y su reversión | Hecho, solo local [E]. Migración `20261111240000` |
| Purga por lotes, plazo de 30 días, recuperación y auditoría que sobrevive | Ya existían y están probados [E] |
| Tarea programada (A o B) | **Propuesta**, nada creado |
| Secreto `ADN_CRON_SECRET` | **No existe**; lo debe crear una persona |
| Acción de estado para el vigilante y lista de identificadores purgados | Sin hacer |
| Plazo X de las copias y cambio del texto legal | Pendiente de decisión |
| Todo lo que depende de la plataforma real (`pg_cron`, `pg_net`, bóveda, retención de copias, la función de borde de extremo a extremo) | **[NV]** |

Decisiones que no son de Desarrollo: A o B; quién genera y guarda el secreto; el valor de X; si el abogado acepta la rotación de copias como cumplimiento del 28.3.g; y quién recibe el aviso de purga atrasada.
