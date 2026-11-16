# Ciclo de vida de una iglesia: lo que hace el código hoy y una política mejorada

Estado a 16 de noviembre de 2026. Etiquetas de evidencia: **[E]** comprobado en el código o en una prueba repetible, **[H]** propuesta o deducción, **[NV]** no verificable desde aquí. La primera parte describe solo lo que existe; la segunda propone, y todo lo que dependa de una decisión comercial de Harold va como «PENDIENTE: le diré» con un valor por defecto. La purga programada, el libro externo de purgadas y los plazos de copias están detallados en `docs/PURGA.md`; aquí se resumen.

## 1. Lo que hace el código HOY

### 1.1 Estados

Una iglesia tiene una **etapa** (`iglesias.etapa`) y la columna `activa`, que es la única puerta que leen las políticas de seguridad: `activa` es verdadera en alta, prueba y activa, y falsa en receso y suspendida. La etapa manda y un disparador mantiene `activa` sincronizada [E, `20261105211929_ciclo_vida_iglesia.sql`, `tests/ciclo_vida.sql`].

| Etapa | `activa` | Qué ocurre con la iglesia | Cómo se sale |
| --- | --- | --- | --- |
| En alta (`onboarding`) | sí | Entra y usa los módulos de su plan | Se activa desde el panel |
| En prueba (`prueba`) | sí | Usa su plan durante 30 días desde que entra en prueba (`prueba_hasta`) | Se convierte en activa; si vence, la iglesia sigue en la etapa «en prueba» y pasa a **solo lectura del núcleo**: ve y exporta sus datos (permisos `.ver`, `.ver_asignados`, `.ver_casa`, `.ver_propia` y `.exportar` de los módulos del núcleo del plan), no puede escribir y se cierran los módulos incluidos y de pago hasta que elija un plan; el propietario descarga su copia desde «Datos y baja». La regla está en `private.adn_nucleo_en_lectura` y `private.tiene_permiso` (migración `20261111370000_adn_prueba_vencida_lectura`) y la interfaz muestra un aviso [E, `supabase/tests/adn_prueba_lectura.sql`, `scripts/probar-acceso-ui.mjs`]. `tiene_modulo` sigue dando falso con la prueba vencida (es el criterio de pago); lo que cambió es qué concede `tiene_permiso`. Falta, y queda fuera: los archivos del almacenamiento de la identidad de la iglesia siguen exigiendo `tiene_modulo('iglesia')`, así que con la prueba vencida el logotipo no se descarga desde la app |
| Activa | sí | Normal | Cualquier cambio de etapa |
| En receso | no | La base no deja ver los datos de negocio; todo se conserva intacto. El propietario aún entra a la pantalla de datos (aviso rojo) para descargar una copia o pedir la baja | La reactiva alguien de la plataforma, o se programa su borrado |
| Suspendida | no | Igual que el receso; es el estado en que queda una iglesia que se da de baja | Igual |

**No hay ningún plazo automático** que mueva una iglesia de un estado a otro, ni limite el tiempo en receso o suspendida: ninguna tarea cambia etapas [E]. Tampoco hay cobros en el sistema, así que ningún estado cobra ni deja de cobrar nada.

### 1.2 Baja y borrado

Hay dos caminos, ambos con un plazo antes de borrar:

- **Borrado suave («baja»).** La plataforma (`borrar_suave`) o el propietario desde su pantalla de datos (`solicitar_baja`) deja la iglesia **suspendida**, guarda la etapa y la prueba que tenía y fija la **purga a 30 días fijos**. Dentro del plazo se **recupera con un clic** (`recuperar`; el propietario también puede cancelar la baja) y vuelve al estado que tenía. Pasado el plazo, ya no se puede recuperar [E, `20261111120000_adn_ciclo_vida.sql`, `adn_ciclo_vida.sql`, `adn_autoservicio.sql`].
- **Borrado programado.** La plataforma (`programar_borrado`) fija una fecha que elige (en receso o suspendida); se puede cancelar. Al llegar la fecha **no se borra solo**: hay que lanzar «Borrar ahora» a mano [E].

### 1.3 Copia de seguridad

La copia de los datos de una iglesia es un **paquete ZIP con un CSV por tabla, un JSON y un manifiesto**, hecho por páginas para no tener límite de tamaño. Lo descarga la plataforma desde «Gestionar» (acción `exportar`, anotada en la auditoría) y el **propietario** desde su pantalla `/datos-iglesia`, también con la iglesia suspendida y durante todo el plazo [E, `docs/EXPORTACION.md`, `adn_autoservicio.sql`]. No se ofrece como paso previo obligatorio a la baja: la pantalla del propietario permite descargar y pedir la baja, pero no obliga a descargar antes.

### 1.4 Purga

La purga de una iglesia vencida borra **su base de datos (en cascada), sus archivos y sus cuentas de acceso**, y deja un registro sin datos de personas en la auditoría, que sobrevive a la purga [E]. Se lanza a mano desde el panel (`purgar_vencidas`, por lotes de hasta 20) o, cuando se active, con una tarea programada cada 6 horas; **hoy no hay ninguna tarea activa** y el secreto no existe [E, `docs/PURGA.md`]. Un libro externo de purgadas (identificador y fecha, sin datos de personas) permite no resucitar a una iglesia borrada si se restaura una copia anterior; falta alimentarlo desde fuera de la base [E, `adn_libro_purgas.sql`; NV en una base real].

Los textos legales prometen que los datos desaparecen de los sistemas activos a los 30 días y de las copias de seguridad en 14 días más. Esa frase solo es cierta si la purga corre sola y las copias rotan a 14 días: ninguna de las dos cosas está activa [H, `docs/LEGAL.md`]. Una pregunta para el abogado: si la rotación de copias basta como supresión (art. 28.3.g del RGPD).

### 1.5 Qué muestra el Panel Maestro hoy

Tarjetas de Suspendidas, En receso y En baja (con los días hasta la purga más cercana, o aviso si hay una vencida), filtros con los mismos números, y en cada ficha («Gestionar») un bloque que explica en lenguaje llano en qué estado está la iglesia y los botones de ese estado: reactivar, activar o convertir, recuperar, cancelar el borrado y descargar copia [E, `scripts/probar-panel-maestro-ui.mjs`]. Suspendidas, en receso y en baja no se solapan: una iglesia en baja cuenta solo como «en baja».

## 2. Política mejorada propuesta [H]

Objetivo: que nadie pierda sus datos por descuido, que una baja voluntaria deje siempre una copia en manos de la iglesia y que nada dependa de que alguien se acuerde de lanzar un proceso a mano.

1. **Copia ofrecida antes de confirmar la baja.** Al pedir la baja, la pantalla del propietario ofrece primero «Descargar copia de seguridad» (el ZIP que ya existe) y avisa de que quedará disponible durante los 30 días siguientes. No se impone como obligación: sin descargar se puede seguir, pero con un aviso claro. Es un cambio de pantalla, sin base de datos nueva.
2. **Copia siempre disponible durante los 30 días.** Ya ocurre hoy para el propietario y para la plataforma [E]; la política lo fija como compromiso y lo escribe en los textos legales y en el correo de confirmación de la baja (el correo sigue apagado hasta que Gerencia lo ordene).
3. **Receso con conservación de hasta 12 meses sin cobrar.** Una iglesia en receso conserva sus datos hasta 12 meses; pasado ese plazo, antes de pasar a baja, se avisa al propietario y se le da una copia. Requiere guardar la fecha de entrada en receso (ya existe: `etapa_desde`) y una alerta en el panel cuando faltan 30 días para cumplir los 12 meses. Ninguna acción automática borra una iglesia en receso: la baja siempre la pide el propietario o la decide una persona de la plataforma.
4. **Recuperación con un clic dentro del plazo.** Ya existe para la plataforma [E]; se propone que el propietario también pueda recuperar una baja desde su pantalla de datos (hoy puede cancelarla [E], que es equivalente en la práctica) y que el panel muestre siempre los días que quedan.
5. **Purga automática activada y vigilada.** Activar la tarea de 6 horas (`docs/PURGA.md`) y la alerta de purga atrasada. Mientras no corra sola, la promesa legal de 30 más 14 días no se cumple.
6. **Borrado programado, sin lanzamiento manual.** Unificar el borrado programado con el borrado suave: al llegar la fecha, entra en la misma purga automática, en lugar de exigir «Borrar ahora» a mano.

### Decisiones que son de Harold

PENDIENTE: le diré. Valores por defecto de Desarrollo entre paréntesis.

- Plazo de gracia de la baja (30 días, el que ya dicen los textos legales).
- Si el receso es gratis y cuánto dura (gratis y hasta 12 meses; sin cobros en el sistema hoy, así que no cuesta nada decidirlo más tarde).
- Si, tras 12 meses en receso, se pasa sola a baja o solo se avisa (solo avisar y pedir confirmación; no borrar nunca sin una persona).
- Si la copia previa a la baja es obligatoria (no obligatoria, con aviso).
- Qué se conserva tras la purga y cuánto tiempo: hoy solo un registro sin datos de personas (el mismo).
- Plazo de rotación de las copias de seguridad (14 días, dato de la propuesta aprobada, a confirmar con el abogado).

## 3. Qué falta construir para la política mejorada

Nada de esto está hecho; lo anterior describe el código de hoy. Pasos en orden de coste: (a) ofrecer la copia en el diálogo de baja del propietario (pantalla); (b) alerta de receso a 30 días de los 12 meses (consulta de panel sobre `etapa_desde`); (c) activar la tarea de purga en la rama de pruebas, según `docs/PURGA.md`; (d) unificar el borrado programado con el borrado suave (migración con reversión). Ninguno se aplica sin orden de Gerencia.
