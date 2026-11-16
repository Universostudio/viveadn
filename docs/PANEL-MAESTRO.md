# Panel Maestro: el panel del administrador de la plataforma

Estado a 16 de noviembre de 2026. Vive ADN es el patrón: este documento describe la estructura para que otros productos (Vivepase, Viverelay, Viveplayer) copien las piezas genéricas y escriban solo su adaptador. Solo Vive ADN lo implementa hoy. Lo que se comprobó con prueba repetible lleva [E]; lo deducido, [H]; lo que no se puede comprobar desde el repositorio, [NV].

## 1. Por qué existe

Un producto con muchos inquilinos (iglesias, organizaciones, canales) necesita dos paneles distintos: el que usa cada inquilino para su gente y el que usa quien administra la plataforma para gobernar a los inquilinos y sus procesos. Antes, el administrador aterrizaba en el panel de una iglesia vacía y la ruta de plataforma era un ítem más de ese menú. Ahora es una aplicación aparte dentro del mismo proyecto, con su propio layout, su menú y su portada [E, `scripts/probar-panel-maestro-ui.mjs`].

## 2. Principio de privacidad

El administrador de plataforma ve conteos, estados, planes, fechas y nombres de inquilino. Nunca ve a las personas de un inquilino: ni nombres, ni correos, ni teléfonos, ni listas de miembros. Se hace cumplir en tres sitios [E]:

1. La base: las funciones `adn_plataforma_resumen`, `adn_plataforma_actividad` y `adn_plataforma_historial` solo devuelven identificadores, nombres de iglesia, acciones, fechas y números. De la auditoría de plataforma nunca sale el detalle, que puede contener datos que no deben verse. La prueba SQL falla si cambian las columnas de salida o si el detalle sembrado aparece en una respuesta (`supabase/tests/adn_plataforma_resumen.sql`).
2. La función de borde: toda respuesta de las lecturas nuevas pasa por `salidaSegura` (`supabase/functions/plataforma/panel.ts`), que lanza un error si encuentra claves como email, correo, teléfono, apellido, token o secreto a cualquier profundidad. La prueba comprueba cada clave y se verificó con mutaciones (`npm run test:panel-funcion`).
3. El adaptador del navegador: `aInquilino` copia solo campos permitidos; aunque la entrada traiga datos personales, no llegan a la salida (`npm run test:panel-adaptador`).

## 3. Pantallas y rutas de Vive ADN

| Ruta | Pantalla | Datos |
| --- | --- | --- |
| `/plataforma` | Portada «Control global» | Siete indicadores, alertas críticas, actividad global, salud del sistema, facturación reciente (sin conectar) y las iglesias más recientes |
| `/plataforma/iglesias` | Tabla de iglesias | Buscador, filtros Todas, Activas, Prueba, Suspendidas y Demo, acciones por estado |
| `/plataforma/nueva-iglesia` | La tabla con el diálogo de alta abierto | Alta con opción de demostración |
| `/plataforma/iglesias/:id` | Gestionar | Plan, etapa, red madre y sedes, complementos, exportación, borrado programado, recuperación, borrado suave y definitivo, historial de acciones |
| `/plataforma/pruebas` | Pruebas activas | Iglesias en prueba por orden de vencimiento |
| `/plataforma/planes` | Planes y módulos | Matriz de lectura: qué incluye cada plan |
| `/plataforma/registro` | Registro y códigos | Apertura del registro y códigos de acceso |
| `/plataforma/sistema` | Sistema | Estado de la purga, libro de purgas, funciones de envío, auditoría de plataforma |
| `/plataforma/reportes` | Reportes | Crecimiento de iglesias por mes, altas y bajas, distribución por plan y etapa, personas y módulos con acceso; uso real y retención «sin conectar» |
| `/plataforma/facturacion` | Facturación | Precio por plan y estimación del ingreso mensual esperado, etiquetada «Datos de prueba»; los cobros reales siguen «sin conectar» (`docs/FACTURACION.md`) |
| `/plataforma/soporte` | Soporte | Tickets, novedades y avisos dentro de la aplicación, sin servicios externos de pago. «Sin conectar» solo mientras la base no tenga la migración `20261111350000_adn_soporte` |

Regla de honestidad: si un bloque no tiene datos reales detrás, muestra «Sin conectar» y una línea que dice qué falta. No hay cifras inventadas ni datos de ejemplo en pantalla [E].

### Indicadores de la portada

Iglesias activas (con las altas de 30 días frente a los 30 anteriores), en prueba (y cuántas vencen en 7 días), suspendidas, demos, miembros totales, facturación recurrente mensual (sin conectar) y alertas críticas. Las demos no cuentan en los totales reales. Las alertas son tipos de problema activos, no iglesias: purga atrasada, pruebas vencidas sin convertir y borrados programados vencidos sin purgar. Cada una enlaza a su pantalla [E].

### Contexto: panel o iglesia

1. Tras iniciar sesión, un administrador de plataforma aterriza en `/plataforma`. Las rutas de iglesia le redirigen allí.
2. Si además tiene perfil de iglesia, el pie del Panel Maestro ofrece «Entrar a mi iglesia» y la aplicación de iglesia muestra una barra con «Volver al Panel Maestro».
3. La elección vive en `sessionStorage` (clave `adn_contexto`): dura la pestaña y nunca se guarda en la base. Una pestaña nueva empieza en el panel.
4. No existe «entrar como otra iglesia» ni suplantación. El soporte ve conteos y estados desde Gestionar [E].

### 3.1 Demostraciones y una sola regla para las cifras

Las iglesias de demostración (`es_demo`) pueden entrar o no en las cifras, pero **siempre con la misma regla para todas a la vez**. El interruptor «Incluir demostraciones» (visible solo si hay alguna demo) decide una lista, `visibles` en `src/stores/plataforma.ts` (`vistaDe` en `src/views/plataforma/adaptador.ts`), y de ella salen las cifras de la portada, los filtros con su número, las filas del listado, los contadores del menú y las cuentas por plan. Las demostraciones se cuentan aparte en su propia tarjeta («Incluidas en las cifras» o «Fuera de las cifras»). Valor por defecto: sí en pruebas, no en producción (`VITE_ENTORNO`, ver `docs/PUESTA-EN-MARCHA.md`); la elección se recuerda en el navegador. Cuando entran, una demostración cuenta en su estado (activa, prueba...) y también en el filtro «Demo»; las pruebas por vencer no avisan por una demo. La equivalencia entre portada, filtros y listado, en las dos posiciones del interruptor, está fijada en `scripts/probar-panel-adaptador.mts` y `scripts/probar-panel-maestro-ui.mjs` [E].

### 3.2 Estados de vida

Suspendidas, en receso y en baja tienen tarjeta en la portada, filtro con su número y, en «Gestionar», un bloque que explica el estado en lenguaje llano con sus botones. No se solapan: una iglesia con purga o borrado programado cuenta solo como «en baja». La política que aplica el código y la propuesta mejorada están en `docs/CICLO-DE-VIDA.md`.

### 3.3 Soporte dentro de la plataforma

Tres piezas, todas en la base y la función `plataforma`, sin servicios de pago [E, `supabase/tests/adn_soporte.sql`, `scripts/probar-soporte-ui.mjs`].

- **Tickets.** La iglesia (quien tiene `iglesia.configurar`) abre un ticket con asunto, prioridad y texto desde «Soporte» en su menú y conversa dentro de él. La plataforma lo ve en «Soporte», responde y cierra. Estados: abierto, respondido (cuando responde la plataforma) y cerrado; un ticket cerrado no admite más mensajes. Límites: 10 tickets abiertos por iglesia y 200 mensajes por ticket. La iglesia solo ve lo suyo por seguridad de filas; no puede borrar ni editar nada. La lista de la plataforma lleva iglesia, asunto, prioridad, estado, fechas y número de mensajes. **El texto solo se ve al abrir un ticket concreto, y abrirlo queda en la auditoría** (`ticket_abrir`); responder y cerrar también (`ticket_responder`, `ticket_cerrar`). La pantalla avisa de que no se escriban contraseñas ni datos de miembros.
- **Novedades.** La plataforma publica una entrada con versión, título y texto y puede retirarla. Cada iglesia las ve en «Novedades»; el menú muestra cuántas se publicaron desde la última vez que esa persona las miró, y verlas apaga el aviso.
- **Avisos.** Tipo (actualización, mantenimiento o alerta), título y texto, para todas las iglesias activas, en prueba o en alta, o solo para las de ciertos planes o estados. Las demostraciones solo reciben el aviso si se marca. Si se eligen planes y estados a la vez, la iglesia debe cumplir los dos. El aviso sale como franja descartable bajo la cabecera de la iglesia y queda registrado, por iglesia, cuándo se entregó, se leyó y se descartó; la plataforma ve las cifras («4 entregados, 1 leído, 0 descartados») y puede retirarlo. Las iglesias en receso o suspendidas solo lo reciben si se filtra por esos estados. Una iglesia dada de baja nunca lo recibe.

**Correo masivo: apagado.** Al crear un aviso se puede pedir que además vaya por correo, pero eso solo se anota (`correo_estado`: `no_pedido`, `apagado` o `pendiente`) y la pantalla lo dice: «correo pedido, no enviado». No se envía nada mientras el interruptor general `ADN_ENVIO_ACTIVO` siga apagado, y cuando se encienda haría falta además el reparto con los topes aprobados (`docs/COSTE-ENVIO.md`). Hoy es solo la pista de lo que se pidió.

**Despliegue seguro.** La web puede desplegarse antes que la migración: la iglesia comprueba una vez por carga si existen las tablas y, si no, no ofrece menú, avisos ni novedades; la plataforma muestra «Sin conectar» en vez de ceros inventados. Los ceros de verdad solo aparecen cuando la base ya tiene las tablas. Las tablas de soporte se exportan con el resto de datos de la iglesia, salvo las entregas de avisos (se reconstruyen al repartir un aviso nuevo).

### 3.4 Reportes

Salen de la misma lista `visibles` que todo el panel, así que el interruptor «Incluir demostraciones» los mueve a la vez [E, `scripts/probar-reportes.mts`, `scripts/probar-panel-maestro-ui.mjs`]. Lógica pura en `src/views/plataforma/reportes.ts`; no hay acción nueva en la función ni migración: se calculan con lo que ya devuelve `listar`. Solo conteos, nunca datos de personas.

- **Crecimiento.** Doce meses en UTC con altas (fecha de creación), bajas (fecha de borrado) e iglesias vivas a fin de mes. Una iglesia suspendida o en receso sigue viva: no tiene fecha propia y no se cuenta como baja.
- **Distribución** por plan y etapa de las iglesias vivas; las dadas de baja no entran. Un plan que ya no está en el catálogo se conserva.
- **Personas.** Total de personas y de cuentas de acceso y promedio por iglesia (sin promedio si no hay iglesias; no se inventa).
- **Módulos.** Cuántas iglesias con servicio (alta, prueba o activa) tienen cada módulo, por su plan o por un complemento activo. Es **acceso, no uso**.
- **Sin conectar:** uso real de cada módulo (no hay registro de uso del que leer) y retención por cohorte (faltan fechas propias de suspensión y de receso).

## 4. Estructura reutilizable

```
src/panel-maestro/            piezas genéricas, sin nada propio de ningún producto
  tipos.ts                    contratos: Inquilino, Kpi, EventoActividad, EstadoServicio, GrupoMenu...
  filtros.ts                  filtrado y búsqueda de la tabla (puro, probado en Node)
  PanelShell.vue              layout: menú lateral por secciones, barra superior con ruta, buscador y fecha, cajón en móvil
  KpiTarjeta.vue              un indicador, o «sin conectar» si no hay valor
  TablaInquilinos.vue         tabla con buscador, filtros y acciones configurables; tarjetas en móvil
  PanelActividad.vue          lista de eventos con fecha
  PanelSalud.vue              servicios con situación (ok, alerta, apagado, sin conectar)
  TarjetaSinConectar.vue      el bloque honesto de lo que aún no tiene datos
src/views/plataforma/         lo específico de Vive ADN
  PlataformaLayout.vue        declara el menú y monta PanelShell
  adaptador.ts                traduce las respuestas de la función de borde a los tipos genéricos (puro)
  *View.vue                   una vista por ruta
src/stores/plataforma.ts      estado compartido y llamadas a la función de borde
```

**Regla de dependencia.** `src/panel-maestro` no importa nada de `views`, `stores` ni `supabase`. Recibe datos por propiedades y emite eventos. Solo usa `vue`, `vue-router` (los enlaces), `vue-i18n` y los iconos. Así otro producto copia la carpeta y escribe su propio adaptador y su menú [E: type-check y build limpios].

**Textos.** Las piezas genéricas usan solo claves `panelMaestro.*` (ya traducidas a es, en, fr y pt-BR). Lo propio de Vive ADN vive en `plataformaPanel.*`. Al copiar la carpeta a otro producto se copian las claves `panelMaestro.*` y se añaden las suyas.

### Contratos de las piezas

| Pieza | Propiedades | Eventos y huecos |
| --- | --- | --- |
| `PanelShell` | `producto`, `marca`, `etiqueta`, `grupos`, `usuario {nombre, rol}`, `buscador`, `seccion` | Eventos `salir` y `buscar(texto)`. Huecos: `pie` (selector de idioma, cambio de contexto) y el contenido |
| `KpiTarjeta` | `kpi {clave, etiqueta, valor, nota, tono, sinConectar}` | Con `valor` nulo muestra «sin conectar» y la línea `sinConectar` |
| `TablaInquilinos` | `titulo`, `inquilinos`, `acciones(inquilino)`, `busquedaInicial`, `filtroInicial`, `etiquetaNombre`, `vacio` | Evento `accion(clave, inquilino)`; una acción con `ruta` es un enlace. Hueco `cabecera` |
| `PanelActividad` | `titulo`, `eventos`, `vacio` | |
| `PanelSalud` | `titulo`, `servicios` | |
| `TarjetaSinConectar` | `titulo`, `falta` | |

### Contrato de datos (los cuatro tipos)

1. `Inquilino`: id, nombre, subtítulo, plan, estado y su etiqueta, detalle de estado (días de prueba, borrado programado), si es demostración, número de miembros y módulos con su estado. Nada de personas.
2. `Kpi`: clave, etiqueta, valor (o nulo), nota, tono y la línea de «sin conectar».
3. `EventoActividad`: id, fecha, texto, tono. El texto lo construye el adaptador con acción e inquilino, nunca con el detalle de la auditoría.
4. `EstadoServicio`: clave, etiqueta, situación, detalle y porcentaje opcional.

## 5. Qué debe aportar el backend de cada producto

1. Una lectura agregada de inquilinos con sus conteos en **una** consulta (no una por inquilino). En Vive ADN: `adn_plataforma_resumen()`.
2. Una lectura de actividad reciente sin detalle (`adn_plataforma_actividad`) y un historial por inquilino (`adn_plataforma_historial`).
3. El estado de sus procesos (purga, envío, copias) como cifras y estados (`estado_purga`, `sistema`).
4. Una barrera de privacidad en la respuesta (`salidaSegura`) y una prueba que falle si aparece una clave personal.
5. Permisos solo del servidor sobre esas lecturas: sin EXECUTE para `anon` ni `authenticated`; la función de borde comprueba antes que quien llama es administrador de plataforma [E, `supabase/tests/adn_plataforma_resumen.sql`].

## 6. Función de borde `plataforma`: acciones de lectura del panel

| Acción | Devuelve | Si falta la migración |
| --- | --- | --- |
| `listar` y `resumen` | Iglesias con sus conteos, planes, módulos y planes por módulo | Cuenta como antes, con 2 consultas por iglesia: sigue funcionando [H] |
| `actividad` | Últimas altas y acciones (tipo, acción, iglesia, fecha) | Responde 501 y la pantalla dice «no disponible» |
| `detalle` | Historial de acciones de una iglesia (acción y fecha) | Igual |
| `sistema` | Estado de la purga, libro de purgas y envío (activo o apagado, uso de hoy, tope) | Cada parte falla por separado; llega nula y el resto se muestra |

El estado del envío solo dice si está activo y cuánto se usó hoy. No se leen ni se devuelven valores de secretos.

## 7. Migración y despliegue

La migración `20261111290000_adn_plataforma_resumen` añade las tres funciones de lectura. Tiene reversión (`supabase/reversiones/20261111290000_adn_plataforma_resumen.down.sql`) probada con `supabase/tests/adn_reversion.sh`, y prueba SQL propia incluida en `supabase/tests/ejecutar.sh` [E]. Se entrega como incremental aparte (`supabase/paquete-pruebas/incremental/`) para un proyecto que ya tenía el paquete hasta `20261111280000` (esa migración ya está aplicada en viveadn-pruebas; el incremental vigente parte ahora de `20261111290000`, `docs/PUESTA-EN-MARCHA.md`). El paquete completo sigue valiendo para un proyecto vacío. Hay que volver a desplegar la función `plataforma`: ahora incluye el archivo `panel.ts` (el manifiesto `funciones.json` lo lista con su sha256).

## 8. Pruebas

| Orden | Qué prueba |
| --- | --- |
| `npm run test:panel-ui` | Navegador real con la red simulada: aterrizaje, menú sin iglesia, indicadores con valores exactos, búsqueda, filtros, acciones, Gestionar, diálogo accesible, cambio de contexto, móvil sin desborde, teclado y estados «sin conectar» |
| `npm run test:panel-adaptador` | Adaptador, filtros, alertas, indicadores, actividad y salud, con la prueba de que no se filtran datos personales |
| `npm run test:panel-funcion` | Barrera de privacidad y mapeos de la función de borde |
| `supabase/tests/adn_plataforma_resumen.sql` | Conteos, orden, límites, columnas de salida, detalle de la auditoría que no sale y privilegios |

## 9. Límites conocidos

1. [NV] Las lecturas contra una base de Supabase real y el comportamiento de la función desplegada solo se pueden confirmar en el entorno de pruebas.
2. [NV] Las capturas de la vista previa de la rama sobre el proyecto de pruebas necesitan la sesión del administrador de pruebas; las capturas locales usan la aplicación compilada con la red simulada.
3. La disponibilidad por servicio no tiene fuente (no hay monitor externo): la portada lo dice. Facturación, tickets y registro de cambios están sin conectar hasta que exista un origen de datos real.
4. El catálogo de planes y módulos es de solo lectura en el panel: hoy no hay una función para editarlo.
