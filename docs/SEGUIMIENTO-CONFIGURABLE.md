# Diseño: método de seguimiento configurable («Seguimiento de nuevas personas»)

Documento de diseño. **No se construye nada con él todavía**: no hay migración, ni código, ni cambio de pantalla. Lo pidió Gerencia (paso F) para decidir antes de tocar la base de datos. Las etiquetas de evidencia son las de siempre: [E] comprobado en el código o en la base, [H] hipótesis o propuesta, [NV] no verificado.

## 1. Qué se decide y por qué

Hoy Vive ADN llama «consolidación» a un único método, **OP72**: tres contactos en 72 horas con un semáforo de cuatro colores. Está escrito en la base de datos y en la interfaz como si fuera el modelo general del seguimiento de una persona nueva. No lo es: es una **plantilla**, la que usan las iglesias que siguen OP72 al pie de la letra. Otra iglesia puede querer un solo llamado en la primera semana, o sus propios plazos.

La propuesta, resumida:

1. El método de seguimiento pasa a ser **un dato**, no una constante: una tabla de métodos por iglesia.
2. Hay tres plantillas de partida: **OP72** (los valores de hoy, sin cambiar nada), **Seguimiento simple** y **Propio** (una copia editable por la iglesia).
3. Cada proceso de seguimiento apunta a su método con `consolidaciones.metodo_id`, con **OP72 por defecto**, de modo que todo lo existente queda exactamente igual.
4. El módulo se llama, de cara a la persona usuaria, **«Seguimiento de nuevas personas»**. Las claves internas no cambian.

## 2. Cómo está hoy [E]

Todo lo que sigue sale de leer el código y el esquema; no hay nada nuevo que averiguar en producción.

| Pieza | Dónde vive | Qué fija de OP72 |
| --- | --- | --- |
| Tabla `consolidaciones` | `supabase/schema/esquema_completo.sql` | Tres huecos de contacto fijos (`primer`, `segundo`, `tercer_contacto_fecha` y `_notas`), `fecha_limite`, `estado_alerta`, `resultado`, `completado` |
| Disparador de consolidaciones | mismo archivo | `fecha_limite = fecha_conversion + 72 horas` al insertar; colores a 24, 48 y 72 horas |
| Color en pantalla | `src/lib/alertas.ts` (`alertaDe`) | Verde hasta 24 h, amarillo hasta 48 h, naranja hasta 72 h, rojo después; se calcula al leer porque `estado_alerta` envejece |
| Barra de progreso | `src/views/consolidacion/ConsolidacionView.vue` (línea 483) | Horas divididas entre 72 |
| Métricas de pago | migración `20261105231653_op72_avanzado.sql` (`metricas_op72`) | Primer contacto en 24 h, cumplimiento a 72 h, vencido pasadas 72 h |
| Recuentos del panel de inicio | `src/views/DashboardView.vue` (paso E) | Críticas a más de 72 h, en alerta a más de 48 h |
| Insignia del menú | `src/layouts/AppLayout.vue` | Más de 48 h sin completar |
| Apertura desde el registro por QR | `registrar_checkin` (paso D) | Abre una consolidación con los valores de OP72 |
| Módulos del plan | `modulos` y `plan_modulos` | `consolidacion` en todos los planes (parte gratuita), `op72_avanzado` de pago en Básico y Premium, y `consolidacion_etapas` en Premium («Etapas con Gatekeeper hasta el bautismo», sin uso en el código todavía) |
| Permisos | `consolidacion.*` | `ver`, `ver_asignados`, `ver_casa`, `ver_zona`, `ver_propios`, `crear`, `editar`, `eliminar`, `reasignar` y `registrar_contacto` |

Consecuencia: cambiar un plazo hoy exige tocar al menos seis sitios a la vez, y no se puede ofrecer a una iglesia un método distinto sin bifurcar el código.

## 3. Principios

1. **Lo existente no cambia.** Ninguna fila actual cambia de color, de fecha límite ni de resultado. Se demuestra con una prueba de equivalencia, no se afirma.
2. **El color se calcula siempre al leer** a partir de la fecha de conversión y del método, igual que hoy. Nunca se confía en una columna guardada que envejece.
3. **El método es un dato sin datos personales.** Una plantilla o un método propio solo contiene nombres, plazos y umbrales; nunca nombres de personas.
4. **Una iglesia no ve ni edita los métodos de otra.** Las plantillas de plataforma las leen todas y no las edita ninguna iglesia.
5. **Objetos nuevos con prefijo `adn_`, reversión escrita y probada antes del cambio**, y paquete numerado para el entorno de pruebas.
6. **Sin servicio de pago nuevo y sin envío real.** Esto es esquema y pantalla, no una integración.

## 4. Modelo de datos propuesto [H]

### 4.1 Tabla de métodos

`adn_seguimiento_metodos`

| Columna | Tipo | Sentido |
| --- | --- | --- |
| `id` | uuid | Clave. Las plantillas de plataforma tienen uuid fijo y conocido |
| `iglesia_id` | uuid, nulo | Nulo en las plantillas de plataforma; el de la iglesia en un método propio |
| `clave` | texto | `op72`, `simple` o una clave libre de la iglesia (única por iglesia) |
| `nombre` | texto | Lo que se muestra: «OP72», «Seguimiento simple», «Mi método» |
| `plantilla_origen` | uuid, nulo | De qué plantilla se copió, para poder comparar y restaurar |
| `pasos` | smallint, 1 a 3 | Número de contactos (ver 4.4 sobre pasar de tres) |
| `plazo_horas` | entero | Tiempo total del proceso; define `fecha_limite` |
| `umbral_amarillo_horas`, `umbral_naranja_horas` | enteros | Desde cuándo cada color; el rojo empieza al pasar `plazo_horas` |
| `primer_contacto_horas` | entero, nulo | Objetivo del primer contacto para las métricas (24 en OP72) |
| `archivado_en` | timestamptz, nulo | Un método se archiva, no se borra, mientras haya procesos que lo usan |

Restricciones: `0 < umbral_amarillo < umbral_naranja <= plazo_horas`, `pasos` entre 1 y 3, `plazo_horas` entre 1 y 720, y un método propio exige `iglesia_id` no nulo mientras una plantilla de plataforma lo exige nulo. El prefijo de seguridad es el de siempre: política de lectura para las plantillas y para los métodos de la propia iglesia, y de escritura solo sobre los de la propia iglesia con permiso de configuración.

### 4.2 Qué método usa cada proceso

- `consolidaciones.metodo_id uuid not null references adn_seguimiento_metodos(id) default <uuid de la plantilla OP72>`.
- Al añadir la columna con ese valor por defecto, **todas las filas existentes pasan a OP72** sin que cambie ningún dato propio: es la garantía del principio 1.
- Un disparador comprueba que el método sea de plataforma o de la misma iglesia que la consolidación, para que la base impida mezclar iglesias aunque alguien escriba un uuid ajeno.
- Si la iglesia cambia su método activo, **los procesos ya abiertos conservan el suyo**; el cambio solo vale para los nuevos.

### 4.3 Método activo de la iglesia

`adn_seguimiento_config (iglesia_id pk, metodo_id)`. Sin fila, la iglesia usa OP72. Es una tabla aparte para no alterar `iglesias`, que ya tiene muchas dependencias. Quien abre un proceso (el botón «Nuevo», el registro por QR del paso D) toma el método activo de la iglesia.

### 4.4 El límite de tres contactos

Hoy los contactos son tres pares de columnas. Para la primera entrega se acepta el límite: **cualquier método tiene de 1 a 3 pasos** y reutiliza esas columnas, lo que evita migrar datos. Si una iglesia necesita más de tres, la fase 4 introduce una tabla `adn_seguimiento_contactos (consolidacion_id, paso, fecha, notas)` con una vista de compatibilidad para las tres columnas actuales. No se hace antes porque es lo único del diseño que mueve datos existentes.

## 5. Las tres plantillas

### OP72 [E] (valores de hoy, sin cambiar)

| Campo | Valor |
| --- | --- |
| Pasos | 3 |
| Plazo | 72 horas |
| Verde | hasta 24 h |
| Amarillo | de 24 a 48 h |
| Naranja | de 48 a 72 h |
| Rojo | más de 72 h sin completar |
| Primer contacto | objetivo de 24 h para las métricas |

Es la plantilla por defecto. Verificado contra `alertaDe`, el disparador y `metricas_op72`: los tres usan estos mismos números.

### Seguimiento simple [H]

Para una iglesia que quiere acompañar sin cuenta atrás de 72 horas. **Los valores son una propuesta que Harold debe validar**, no un dato:

| Campo | Valor propuesto |
| --- | --- |
| Pasos | 1 |
| Plazo | 168 horas (una semana) |
| Amarillo | desde 72 h |
| Naranja | desde 120 h |
| Rojo | más de 168 h |
| Primer contacto | objetivo de 72 h |

PENDIENTE: le diré (qué plazo y qué colores quiere Harold para esta plantilla; no bloquea el diseño).

### Propio [H]

No es una plantilla con valores: es la **acción de copiar** una plantilla a la iglesia para editarla. El resultado es una fila en `adn_seguimiento_metodos` con `iglesia_id` de la iglesia y `plantilla_origen` apuntando a la de partida. Se editan nombre, número de pasos (1 a 3), plazo, umbrales y objetivo de primer contacto, siempre dentro de las restricciones de 4.1. «Restaurar» recarga los valores de la plantilla de origen.

## 6. Cálculo del color con método [H]

Una sola definición, con dos implementaciones que se prueban con la **misma tabla de casos**:

- TypeScript: `alertaDe(conversion, completado, metodo, ahora)` en `src/lib/alertas.ts`, pura.
- SQL: `adn_seguimiento_alerta(conversion, completado, metodo_id, ahora)`, para contar en la base.

La regla es la de hoy con números tomados del método: verde hasta el umbral amarillo, amarillo hasta el naranja, naranja hasta `plazo_horas`, rojo después, y verde si está completado. Con OP72 da lo mismo que el código actual en todos los puntos; la prueba lo fija incluyendo los bordes exactos (24, 48 y 72 horas).

Los recuentos del panel de inicio y la insignia del menú **dejan de usar 48 y 72 escritos a mano**: cuentan con `fecha_limite` (ya existe) y con una vista `adn_seguimiento_estado` que devuelve el color por proceso. Así «críticas» sigue siendo «pasado su plazo», sea el plazo el que sea.

## 7. El módulo «Seguimiento de nuevas personas»

- Se cambia el **nombre que se ve**: la etiqueta del módulo (hoy «Consolidación 72 horas»), la entrada del menú y los textos, en los cuatro idiomas.
- **No se renombran** las claves internas: el módulo sigue siendo `consolidacion`, el de pago `op72_avanzado`, los permisos `consolidacion.*` y la tabla `consolidaciones`. Renombrarlas movería permisos de todos los roles de todas las iglesias para ganar solo un nombre.
- `op72_avanzado` conserva su nombre y su sentido: las métricas avanzadas siguen siendo del método OP72, y la propuesta es que pasen a hablar de «el método de la iglesia» (primer contacto, cumplimiento del plazo, vencidos) sin cambiar quién las contrata.
- Plantillas OP72 y Simple: en todos los planes, dentro de la parte gratuita. **Método propio**: la propuesta es un módulo nuevo `seguimiento_propio` como interruptor del plan, una fila en `modulos` y en `plan_modulos`, sin coste nuevo. **No** se reutiliza `consolidacion_etapas`: ese módulo ya existe con otro sentido (etapas con Gatekeeper hasta el bautismo, una idea distinta que sigue sin construir) y mezclarlos confundiría lo que cada iglesia contrata. Decidir si `seguimiento_propio` va en Premium, como complemento o en todos los planes es una decisión de producto y de precio. PENDIENTE: le diré.
- Quién configura: se propone reutilizar `iglesia.configurar` (propietario y administrador) en lugar de crear un permiso nuevo. Se puede separar más adelante con `seguimiento.configurar` si hace falta.

## 8. Qué cambia en cada capa

| Capa | Cambio |
| --- | --- |
| Base de datos | Dos tablas y una vista nuevas con `adn_`; columna `metodo_id` con OP72 por defecto; disparador de integridad; `fecha_limite` calculada con el plazo del método al insertar; `metricas_op72` y `registrar_checkin` leen el método |
| Interfaz | `alertaDe` con método; barra de progreso y etiquetas con el plazo del método; recuentos del panel de inicio y de la insignia sin 48 ni 72 fijos; pantalla «Método de seguimiento» en Configuración; mostrar el método en la ficha del proceso |
| Registro por QR | Abre el proceso con el método activo de la iglesia (por defecto OP72) |
| Mi panel y panel de inicio | Los mismos recuentos, ahora por método |
| Comunicación | El segmento «en consolidación» no cambia: sigue siendo «procesos no completados» |
| Exportación | Incluye `metodo_id` y el nombre del método en el paquete de datos de la iglesia |
| Documentos | `docs/MANUAL-IGLESIAS.md`, `docs/MULTITENANT.md` y `docs/MAPA-ACCESOS.md` |

## 9. Fases de construcción [H]

Cada fase se entrega por separado, con su reversión escrita y probada antes, sus pruebas «N de N» y su paquete numerado.

1. **Esquema sin cambio visible.** Tablas, plantillas sembradas, `metodo_id` con OP72 por defecto, función de color y disparador. Prueba de equivalencia: sobre datos sintéticos de todas las edades, el color por método y el color actual coinciden en todos los casos. Nada cambia en pantalla.
2. **La interfaz lee el método.** `alertaDe` con método, barra, recuentos y métricas. Con todo en OP72 la pantalla es idéntica.
3. **Configuración y método propio.** Pantalla para elegir plantilla, copiar a «Propio» y editar, con validación y errores visibles. Pruebas de aislamiento entre iglesias.
4. **Más de tres pasos.** Tabla de contactos y vista de compatibilidad; es la única fase que mueve datos y se decide aparte.

## 10. Pruebas previstas

- **Equivalencia**: color y fecha límite con el método OP72 frente al comportamiento de hoy, en los bordes exactos de 24, 48 y 72 horas.
- **Paridad TypeScript y SQL** con la misma tabla de casos, y mutación (cambiar un umbral debe romper una prueba).
- **Aislamiento**: una iglesia no lee ni edita los métodos de otra, nadie edita las plantillas de plataforma, y la base rechaza un `metodo_id` ajeno.
- **Restricciones**: umbrales ascendentes, pasos de 1 a 3, plazo dentro de rango.
- **Reversión**: aplicar, revertir y volver a aplicar deja el esquema idéntico; revertir conserva los procesos existentes.
- **Interfaz**: errores visibles al guardar, método archivado que sigue mostrándose en procesos antiguos, cambio de método activo que no toca los procesos abiertos.

## 11. Riesgos y decisiones abiertas

1. **Cambiar el plazo a mitad de proceso.** Decidido: un proceso conserva su método; solo los nuevos usan el cambio. Editar los valores de un método propio sí afecta a los procesos que lo usan; la pantalla avisará de cuántos hay antes de guardar. [H]
2. **Archivar un método en uso.** Se archiva, no se borra; los procesos abiertos lo conservan. [H]
3. **Valores de «Seguimiento simple», plan del método propio y relación con «Etapas hasta el bautismo» (`consolidacion_etapas`).** Dependen de Harold: si esas etapas serán otro método, una extensión de la fase 4 o algo aparte. PENDIENTE: le diré.
4. **El nombre «Seguimiento de nuevas personas»** convive con la expresión «nuevo creyente» del registro por QR (paso D): la pregunta sigue siendo si la persona se declara nueva creyente, y el método decide qué se hace después. No hay conflicto, pero conviene revisar los textos en los cuatro idiomas al hacer la fase 2. [H]
5. **Dato sensible.** Un método no guarda nada sobre la persona; el proceso ya existía. No añade tratamiento de datos de creencias. [H]
6. **Tamaño.** Las fases 1 y 2 son de tamaño medio y de bajo riesgo si la prueba de equivalencia se cumple; la 3 es la que más pantalla añade; la 4 es la única de riesgo real porque mueve datos. [H]

## 12. Estado de construcción

Aprobado por Gerencia el 16 de noviembre de 2026: se construyen las fases 1, 2 y 3, cada una como paquete numerado, sin aplicar en pruebas hasta que Gerencia lo ordene. La fase 4 queda en espera. El método propio entra en Premium para las pruebas de desarrollo (el empaquetado real por plan queda como «PENDIENTE: le diré»), los valores de «Seguimiento simple» siguen **por validar**, y las «Etapas hasta el bautismo» son un diseño aparte que no se mezcla con esto.

| Fase | Paquete | Estado |
| --- | --- | --- |
| 1. Esquema sin cambio visible | `20261111320000_adn_seguimiento_metodos` | Hecha, sin aplicar. Tablas `adn_seguimiento_metodos` y `adn_seguimiento_config`, columna `consolidaciones.metodo_id` con OP72 por defecto, disparador que lee el método, `adn_seguimiento_alerta()` y la vista `adn_seguimiento_estado` [E, `supabase/tests/adn_seguimiento_metodos.sql` 48 comprobaciones y `supabase/tests/adn_seguimiento_metodos.sh` 8 con datos previos] |
| 2. La interfaz lee el método | `20261111330000_adn_seguimiento_metricas` | Hecha, sin aplicar. Las pantallas calculan el color y el plazo con el método de cada proceso (`src/lib/alertas.ts`, `src/stores/seguimiento.ts`) y las métricas avanzadas de OP72 usan el plazo y el objetivo de primer contacto de cada método, con las mismas claves de siempre. Con todos los procesos en OP72 el resultado es idéntico al anterior [E, `supabase/tests/adn_seguimiento_metricas.sh`, 4 comprobaciones, la primera compara el JSON completo de 14 procesos]. Si la migración de la fase 1 no está aplicada, la interfaz detecta que falta `adn_seguimiento_metodos` y sigue con 48 y 72 horas, de modo que el orden de despliegue no importa [E, `scripts/probar-inicio-ui.mjs`, modos con y sin métodos] |
| 3. Configuración y método propio | pendiente | |
| 4. Más de tres pasos | en espera | |

Detalles de la fase 1 que afinan este diseño [E]: el color usa umbrales «hasta» (verde hasta el umbral amarillo, amarillo hasta el naranja, naranja hasta el plazo, rojo después), que con OP72 dan 24, 48 y 72; una plantilla copiada solo puede venir de una plantilla de plataforma o de la propia iglesia; y las claves foráneas hacia `adn_seguimiento_metodos` son simples (no compuestas con la iglesia) porque las plantillas no tienen iglesia, con la integridad entre iglesias dada por disparadores y probada.

## 13. Qué NO se hace ahora

Este apartado describe lo que decidió el paso F (solo diseño). Hoy, la fase 1 ya está construida en el repositorio (apartado 12) y nada se aplica en ningún entorno hasta que Gerencia lo ordene.
