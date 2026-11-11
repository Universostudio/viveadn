# Monitorización mínima y sin coste

Estado a 11 de noviembre de 2026. Etiquetas de evidencia: **[E]** informado por Desarrollo con una prueba repetible, **[H]** deducido, **[NV]** no verificable desde aquí. Es una propuesta mínima: dos piezas ya escritas en el repositorio, un vigilante externo que hay que elegir y activar, y una lista de lo que queda fuera. Nada de esto está desplegado ni activo en producción.

## 1. Qué se quiere saber

Tres cosas, por orden de importancia: si la web no abre, si el servicio de cuentas (Auth) no contesta, y si una función pública de borde ha dejado de responder. Sin esto, hoy el primer aviso de una caída es que alguien llame.

## 2. Lo que ya está escrito

### Ruta de salud, `GET /api/salud` (`api/salud.ts`)

Responde `{"ok":true}` con 200 si la función de la web está viva y el servicio de Auth contesta en menos de 3 segundos, y `{"ok":false}` con 503 en cualquier otro caso. Es mínima a propósito, porque es pública:

- Un solo campo. No devuelve versiones, tiempos, nombres de servicios ni mensajes de error, y la clave pública que usa para preguntar a Auth no sale en la respuesta **[E, `npm run test:salud`]**.
- Solo admite GET y HEAD; el resto recibe 405 **[E]**.
- Sin dirección o clave configuradas no se da por sana: responde 503 **[E]**. Una dirección que no sea `https://` a un host sencillo no se consulta **[E]**.
- La plataforma la guarda 30 segundos (`s-maxage=30`), de modo que un vigilante, o alguien que la llame sin parar, no llega al servicio de Auth más de una vez cada 30 segundos **[E]** (cabecera comprobada; el comportamiento de la caché en Vercel es **[NV]**).
- Las pruebas simulan el servicio de Auth y detectan cuatro cambios malintencionados del código (siempre ok, siempre 200, sin 405, sin comprobar la clave) **[E]**.

Lo que **no** comprueba: la base de datos directamente (Auth la usa, pero no es lo mismo **[H]**), las funciones de borde ni el almacenamiento. Si más adelante se quiere una comprobación de la base, lo más pequeño es una función `adn_salud()` que devuelva un valor fijo y se pueda llamar sin sesión; necesitaría su migración y su reversión, y no está escrita.

### Pantalla de error propia (`src/views/ErrorView.vue`, `src/lib/errorApp.ts`)

Cuando algo impide mostrar la pantalla normal, la persona ve un título, una frase y dos botones («Recargar la página» e «Ir al inicio») en los cuatro idiomas, en lugar de una página en blanco. Tres casos:

| Caso | Qué lo provoca | Qué se ve |
| --- | --- | --- |
| `carga` | Se publicó una versión nueva mientras la página estaba abierta y pide un archivo que ya no existe (el error lo dice cada navegador a su manera: Chrome, Firefox y Safari están cubiertos) | «La aplicación se ha actualizado mientras la tenías abierta. Recarga la página para continuar.» |
| `inicio` | La sesión no se puede iniciar al arrancar. Antes, ese fallo dejaba la página sin montar | «No hemos podido conectar con el servicio para abrir tu sesión. Suele resolverse en unos minutos.» |
| `inesperado` | Reservado para fallos que se decida capturar; hoy no lo dispara nada | «Ha ocurrido un error inesperado. Recarga la página para intentarlo de nuevo.» |

Comprobado **[E]**: la lógica con `npm run test:error`, que incluye los mensajes de los tres navegadores y que el primer error no lo tapa uno posterior; y en un Chromium real, con la web compilada: bloqueando un archivo de la web aparece la pantalla de carga (en español e inglés, a 390 píxeles de ancho), forzando un fallo del almacenamiento del navegador aparece la de inicio, y en el camino normal no aparece ni hay errores en la consola. Que otros navegadores muestren lo mismo es **[NV]**.

Decisión de diseño: un fallo al pintar un componente concreto se anota en la consola y **no** sustituye toda la pantalla, porque seguir usándola suele ser posible. Si se prefiere lo contrario, es un cambio de una línea.

## 3. Quién vigila

Una ruta de salud no avisa de nada por sí sola: hace falta algo que la llame cada pocos minutos y avise si falla. Dos opciones sin coste. En pruebas basta con cualquiera de las dos; quién recibe los avisos en producción es «le diré» (puerta B).

**Opción A. GitHub Actions programado.** El repositorio es público, y los minutos de Actions en repositorios públicos son gratuitos **[H: confirmar las condiciones vigentes]**. Un flujo programado llama a la web y a `/api/salud`; si falla, GitHub avisa por correo a quien lo mantiene. Ventajas: no hay cuenta nueva ni datos que compartir con un tercero. Inconvenientes: el intervalo mínimo es de 5 minutos y GitHub puede retrasarlo; un flujo programado solo corre desde la rama principal; y GitHub desactiva los flujos programados de un repositorio público sin actividad durante 60 días **[H]**, lo que dejaría la vigilancia apagada sin avisar. Para no depender de ello, conviene que alguien confirme de vez en cuando que sigue activo.

Ejemplo (no está en `.github/workflows` a propósito, para que no se active por accidente; se copiaría allí cuando se apruebe):

```yaml
name: Vigilancia
on:
  schedule:
    - cron: '*/10 * * * *'
  workflow_dispatch:
permissions: {}
jobs:
  salud:
    runs-on: ubuntu-24.04
    timeout-minutes: 3
    steps:
      - name: La web abre
        run: curl --fail --silent --show-error --max-time 20 --retry 2 --retry-delay 10 --output /dev/null https://viveadn.com/
      - name: El servicio de cuentas contesta
        run: |
          codigo=$(curl --silent --max-time 20 --retry 2 --retry-delay 10 --write-out '%{http_code}' --output /tmp/salud.json https://viveadn.com/api/salud)
          [ "$codigo" = "200" ] && grep -q '"ok":true' /tmp/salud.json
```

**Opción B. Un servicio externo de comprobación con plan gratuito** (hay varios que llaman a una dirección cada pocos minutos y avisan por correo o mensaje). Ventajas: intervalos más cortos y avisos más variados. Inconvenientes: una cuenta más que custodiar y condiciones de plan que cambian **[NV: no se han consultado los límites actuales de ninguno]**. Gerencia cita la monitorización de Vivepase como modelo (ruta de salud y pantalla de error propia); este repositorio no contiene nada de ese proyecto y por eso no sé qué vigilante usa ni cómo lo configura.

Con cualquiera de las dos hay que decidir **a quién se avisa**: el correo de soporte y el legal son «le diré» (`docs/PENDIENTES-PRODUCCION.md`). Hasta entonces, el aviso iría a quien activó la vigilancia.

## 4. Funciones públicas de borde

Las funciones públicas son `dar-publico`, `checkin-evento`, `baja` y `verificar-certificado`. Propuesta, **sin implementar**: que el vigilante les envíe una petición `OPTIONS` con un origen permitido, que cada una responde con 200 sin tocar la base de datos **[E: el código de las cuatro lo hace antes de cualquier otra cosa (`grep OPTIONS`); no se ha ejecutado contra las funciones desplegadas]**. Solo demuestra que la función está viva, no que funcione de extremo a extremo. Una comprobación más fuerte exige datos de prueba en producción, y eso no se propone.

## 5. Errores que hoy no se ven

- Las funciones solo escriben con `console.error` en el registro de la plataforma **[E]**. Nadie lo mira. Propuesta mínima: que alguien lo revise de forma periódica (por ejemplo, una vez por semana) y que se anote cuándo. Cuánto tiempo conserva la plataforma ese registro depende del plan **[NV]**.
- Los errores que ocurren en el navegador de una persona se quedan en su consola. Recogerlos exige una herramienta o una ruta propia que reciba datos de los visitantes, con lo que eso implica para la privacidad. **No se propone ahora**; si hace falta, se decide aparte.
- La purga de iglesias sigue siendo manual. Cuando se programe, se vigila con `estado_purga` (tarjeta del panel de superadministración; la acción admite la clave de la tarea para que un vigilante la consulte) y falla si `atrasada` es verdadero (`docs/PURGA.md`, apartado 5).

## 6. Puesta en marcha

1. Aprobación para desplegar a producción: «le diré» (puerta B). En el entorno de pruebas se despliega sin ella (`docs/PUESTA-EN-MARCHA.md`); en producción **no hay nada activo**.
2. `vercel.json` reenviaba todas las rutas a `index.html`; se ha cambiado esa regla para que no alcance a `/api/`, porque una regla que lo captura todo puede tapar la función. Que la ruta responde en Vercel como se espera es **[NV]**.
3. Tras desplegar, confirmar que `https://<web>/api/salud` responde 200 con `{"ok":true}`. Es **[NV]**: no se ha probado en Vercel que la función vea las variables `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` en tiempo de ejecución ni cómo trata la caché; si no las ve, responderá 503 y habrá que ajustar el nombre de las variables.
4. Elegir la opción A o la B y a quién se avisa.
5. Probar el aviso con un fallo provocado, por ejemplo apuntando temporalmente el vigilante a una dirección que no existe, no rompiendo nada en producción.
6. Anotar en `docs/CONTEXTO.md` quién recibe los avisos y quién confirma cada cierto tiempo que la vigilancia sigue en marcha.
