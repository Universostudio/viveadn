# Puesta en marcha del entorno de pruebas

Estado a 11 de noviembre de 2026. Etiquetas de evidencia: **[E]** informado por Desarrollo con una prueba repetible, **[H]** deducido, **[NV]** no verificable desde aquí, **[V]** solo Gerencia. Este documento deja un entorno de pruebas completo y operativo de punta a punta, con la misma forma que producción y con datos sintéticos. Lo que depende de Harold no bloquea nada aquí: consta como «le diré» en `docs/PENDIENTES-PRODUCCION.md`.

**Reglas fijas del entorno de pruebas.** Es una rama o un proyecto de Supabase creado para esto, nunca el de producción. No envía correo, SMS ni WhatsApp reales a nadie: solo a buzones controlados. No lleva ningún dato real de iglesias ni de personas. Las claves y secretos viven en los paneles de Supabase y de Vercel, nunca en un archivo del repositorio, y este documento solo los nombra. Los identificadores del proyecto se escriben como `<REF_PRUEBAS>` y las direcciones como `<WEB_PRUEBAS>`: no se escriben aquí.

## 1. Resumen de piezas

| Pieza | Qué es | Quién la habilita |
| --- | --- | --- |
| Base de datos y Auth | Rama o proyecto de Supabase de pruebas | Gerencia |
| Funciones de borde | Diez funciones desplegadas desde `supabase/functions` | Gerencia o quien tenga el acceso |
| Web | Despliegue de la rama en Vercel, con sus variables | Gerencia |
| Secreto de la tarea de purga | Lo genera Gerencia y vive solo en las bóvedas de secretos | Gerencia [V] |

## 2. Variables y secretos

### 2.1 En la web (Vercel, entorno de pruebas)

Las variables `VITE_` entran en la compilación: tras cambiar una, hay que volver a desplegar.

| Variable | Qué lleva | Valor en pruebas |
| --- | --- | --- |
| `VITE_SUPABASE_URL` | Dirección del proyecto de Supabase de pruebas | La de `<REF_PRUEBAS>`, en el panel de Supabase, Settings, API |
| `VITE_SUPABASE_ANON_KEY` | Clave pública (anon) | La del mismo sitio. Es pública, pero no se escribe en archivos |
| `VITE_REGION_DATOS` | Región donde se alojan los datos | `eu-west-1` [V] |
| `VITE_LEGAL_TITULAR` | Titular de los textos legales | `Visualiza Studio`, ya es el valor por defecto |
| `VITE_LEGAL_NIF`, `VITE_LEGAL_DOMICILIO`, `VITE_EMAIL_LEGAL`, `VITE_EMAIL_SOPORTE`, `VITE_LEGAL_REGISTRO` | Datos del titular | En pruebas se dejan **vacíos**: los textos muestran un marcador visible en lugar de un dato inventado [E]. Pendiente: «le diré» |

La ruta `/api/salud` lee `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` en tiempo de ejecución y responde 503 si no las ve **[NV]**. `vercel.json` ya añade `noindex` a todas las respuestas, de modo que el entorno de pruebas no se indexa [E].

### 2.2 En las funciones de borde (Supabase, Edge Functions, Secrets)

`SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` las inyecta la plataforma. El resto:

| Secreto | Obligatorio | Qué hace | Valor en pruebas |
| --- | --- | --- | --- |
| `ADN_ORIGENES_EXTRA` | **Sí** en pruebas | Añade la web de pruebas a los orígenes que las funciones aceptan. Sin él, el navegador bloquea las llamadas (CORS) | `<WEB_PRUEBAS>`: dirección `https` exacta, sin ruta ni barra final; se admiten hasta 10, separadas por comas [E] |
| `ADN_CRON_SECRET` | Para la purga programada | Abre la vía de la tarea programada (cabecera `x-adn-cron`). Al menos 32 caracteres | Lo genera Gerencia [V]. Sin él, la vía está cerrada |
| `ADN_WEB_URL` | Solo con la doble confirmación | Dirección de la web que va en los enlaces de los correos de confirmación. Por defecto es la de producción | `<WEB_PRUEBAS>` |
| `ADN_EMAIL_SOPORTE` | No | Dirección de respuesta de los correos | Sin definir: usa la de reserva del código. Pendiente: «le diré» |
| `BIRD_API_KEY` | No | Envío de correos de invitación y de confirmación | **Sin definir** en pruebas. Sin ella, las invitaciones no se envían y el enlace se copia a mano [E]. Para ensayar el envío, solo con una clave de pruebas y buzones controlados (apartado 8) |
| `ADN_CONFIRMACION_ACTIVA` | No | Interruptor de la doble confirmación | **Sin definir**: apagada |

Nada de esto lleva claves de producción. Si una variable de producción coincide con una de pruebas, no se reutiliza el valor.

### 2.3 En Supabase Auth (Authentication, URL Configuration)

- **Site URL**: `<WEB_PRUEBAS>`.
- **Redirect URLs**: `<WEB_PRUEBAS>/**`. Las invitaciones y el restablecimiento de contraseña redirigen a `/aceptar` y `/reset-password`; si la dirección no figura aquí, Auth redirige al Site URL **[NV]**.
- Los correos de Auth (restablecer contraseña) los envía Supabase con su servicio por defecto: en pruebas se usan solo cuentas con buzón controlado.

## 3. Pasos, en orden

**Paso 1. Crear la base de pruebas.** Dos caminos:

- *A. Rama de Supabase.* Crear la rama desde el panel o con la CLI. Aplica las migraciones de `supabase/migrations`. **[NV]** que el historial de migraciones aplicadas a mano en producción permita una rama que se construya sola: si no, se usa el camino B.
- *B. Proyecto o rama vacíos con el script.* Con la cadena de conexión de la base vacía en la variable `DATABASE_URL`, tomada de Settings, Database, y sin escribirla en ningún archivo:

```bash
DATABASE_URL='<cadena de conexión>' scripts/entorno/montar-rama.sh --rama-de-pruebas
```

El script aplica el esquema, el catálogo y las 45 migraciones en el orden de la batería, se niega a tocar una base que ya tenga el esquema y no imprime la cadena de conexión [E]. Probado en local contra una base sin Supabase (con `--con-stub`): el esquema resultante es idéntico, línea a línea, al de la batería de pruebas [E]. Contra una base de Supabase real **no se ha ejecutado [NV]**.

**Paso 2. Comprobar las cuentas de acceso.** Después de crear cualquier cuenta por SQL, ejecutar `supabase/tests/auth_usuarios_sin_nulos.sql` contra la rama: un NULL en columnas de texto de `auth.users` rompe el inicio de sesión. Las cuentas creadas desde el panel de Auth o con la API de administración no tienen el problema.

**Paso 3. Poner los secretos de las funciones** (apartado 2.2): como mínimo `ADN_ORIGENES_EXTRA`. Con la CLI: `supabase secrets set ADN_ORIGENES_EXTRA=<WEB_PRUEBAS> --project-ref <REF_PRUEBAS>`.

**Paso 4. Desplegar las diez funciones** desde `supabase/functions` (`supabase functions deploy <nombre> --project-ref <REF_PRUEBAS>`):

| Función | Verificación de JWT | Motivo |
| --- | --- | --- |
| `baja`, `confirmar-suscripcion` | **Desactivada** (`--no-verify-jwt`) | Las abre cualquiera con el enlace del correo |
| `enviar-confirmaciones` | **Desactivada** (`--no-verify-jwt`) | La llama la tarea programada con `x-adn-cron`; ella misma lo exige |
| `plataforma` | Activada, y la tarea de purga debe enviar la clave pública (apartado 5) | Valida ella misma a quien llama |
| `dar-publico`, `checkin-evento`, `verificar-certificado`, `registro-iglesia`, `invitaciones`, `red-resumen` | Activada | La web envía la clave pública o la sesión |

La configuración real de producción no se puede leer desde el repositorio **[NV]**: esta tabla es el diseño. `npm run check:entorno` comprueba que las funciones sin JWT responden sin él y que `dar-publico` lo exige (paso 8).

**Paso 5. Crear el administrador de la plataforma.** Crear un usuario desde Authentication, Users, con confirmación automática y un buzón controlado. Después, en el editor SQL **de la rama de pruebas**:

```sql
insert into public.plataforma_admins (user_id) values ('<uuid del usuario>');
```

**Paso 6. Desplegar la web** de la rama en Vercel con las variables del apartado 2.1 y la dirección estable de la rama como `<WEB_PRUEBAS>` **[NV]**: confirmar que ese dominio es el mismo que se puso en `ADN_ORIGENES_EXTRA` y en Auth.

**Paso 7. Cargar datos sintéticos.** Iglesia de demostración con 300 personas, 6 zonas, 18 casas, 24 recientes y 2 en rojo, sin datos reales:

```bash
psql "$DATABASE_URL" -v slug=iglesia-demo -v zonas=6 -v casas=18 -v personas=300 -v recientes=24 -v rojos=2 -f supabase/seeds/datos_demo_sinteticos.sql
```

El script marca la iglesia como demostración y se niega a tocar una que no lo sea [E]. Después, entrar en `<WEB_PRUEBAS>/plataforma` con el administrador y vincular o invitar a un superadministrador de la iglesia demo con un buzón controlado.

**Paso 8. Verificar el entorno desplegado.** Solo lee y hace peticiones inocuas; no crea ni borra nada ni envía correos:

```bash
ADN_WEB_URL=<WEB_PRUEBAS> VITE_SUPABASE_URL=<URL de la rama> \
  VITE_SUPABASE_ANON_KEY=<clave pública> ADN_CRON_SECRET=<secreto de la tarea> npm run check:entorno
```

Las dos últimas son opcionales, pero van juntas: la tarea real envía las dos, y sin ellas se omiten las comprobaciones de la purga. Comprueba la web y `/api/salud`, que no se indexe, las cuatro rutas legales, el CORS de cada función con el origen de la web, que `baja` y `confirmar-suscripcion` respondan sin JWT, que `dar-publico` lo exija, que la vía de la tarea esté cerrada a una clave falsa y, con el secreto, el estado de la purga y el libro. Cada fallo dice qué hacer. El script y su prueba, con un entorno simulado sano, otro sin secretos y nueve fallos provocados que se detectan uno a uno, están en `scripts/verificar-entorno.mts` y `scripts/probar-verificar-entorno.mts` (`npm run test:entorno`) [E]. **Contra un entorno real no se ha ejecutado [NV]**.

## 4. Ensayo de extremo a extremo

Con el entorno verificado, este recorrido ejercita todo el producto. Cada punto se hace con la iglesia demo y buzones controlados:

1. Registrar una iglesia nueva en `/registro` con un código de acceso creado en el panel de plataforma, y completar la invitación por `/aceptar`.
2. Crear miembros, una casa de oración y un evento; abrir el QR del evento y registrar asistencia en `/checkin/<enlace>`, en los cuatro idiomas.
3. Importar un archivo de contactos (`docs/IMPORTACION.md`), exportar la iglesia (`docs/EXPORTACION.md`) y descargar los tres informes (`docs/INFORMES.md`).
4. Gestionar consentimientos, dar de baja un canal y abrir un enlace de baja en `/baja/<secreto>` (`docs/COMUNICACION.md`).
5. Borrar una iglesia de prueba con borrado suave, recuperarla dentro del plazo, y borrar otra dejando vencer el plazo para ver la purga (apartado 5).
6. Consultar el panel de plataforma: la tarjeta «Purga programada» debe quedar al día.
7. Ensayar la restauración de `docs/RESTAURACION.md` sobre otra rama.

## 5. Purga programada en pruebas

Es la opción A aprobada (`docs/PURGA.md`). Requisitos: el secreto del apartado 2.2 y `pg_cron`, `pg_net` y la bóveda de secretos activos en la rama **[NV]**. Gerencia genera el secreto y lo guarda dos veces: como secreto de la función (`ADN_CRON_SECRET`) y en la bóveda de la base con el nombre `adn_cron_secret`. La clave pública de la rama se guarda también en la bóveda como `adn_anon_key`, porque la pasarela de funciones exige un JWT válido a `plataforma` aunque la función valide por su cuenta. La tarea, con los marcadores sustituidos en la rama de pruebas y nunca en el repositorio:

```sql
select cron.schedule('adn-purga-vencidas', '0 */6 * * *', $$
  select net.http_post(
    url := '<URL de la rama>/functions/v1/plataforma',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'adn_anon_key'),
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'adn_anon_key'),
      'x-adn-cron', (select decrypted_secret from vault.decrypted_secrets where name = 'adn_cron_secret')),
    body := '{"accion":"purgar_vencidas"}'::jsonb);
$$);
```

Para ensayarla sin esperar 30 días, sobre una iglesia ficticia que se borró con borrado suave: adelantar su `borrado_programado_en` en la rama de pruebas, esperar a la siguiente pasada y comprobar que desaparece y que `estado_purga` vuelve a cero. Esa prueba es una escritura en la base de pruebas, no en una real.

## 6. Qué no está activo en pruebas, a propósito

- El envío real de mensajes a personas: no hay clave de proveedor de producción y no se pone.
- La doble confirmación: apagada por defecto con tres cerrojos (`docs/COMUNICACION.md`).
- Cobros: no existen (`docs/COBRO.md`).
- Los textos legales con los datos del titular: llevan marcadores visibles hasta que se rellenen en la puerta B.

## 7. Cómo se cambia una variable

Se cambia en el panel de Supabase o de Vercel, se vuelve a desplegar lo afectado (la web si es `VITE_`, la función si es un secreto) y se repite `npm run check:entorno`. Si cambia la dirección de la web de pruebas, se cambian a la vez `ADN_ORIGENES_EXTRA`, `ADN_WEB_URL` y las direcciones de Auth.

## 8. Ensayo del envío de correo con un buzón controlado

Solo cuando Gerencia lo decida y con una clave de pruebas del proveedor, nunca de producción. Según la documentación oficial del proveedor (`https://bird.com/docs/guides/email/sending-email`, consultada el 11 de noviembre de 2026), `delivered@messagebird.dev` es una dirección de pruebas que siempre acepta correo, y antes de verificar un dominio solo se puede enviar desde su dominio de incorporación a miembros verificados del propio espacio y a esas direcciones de pruebas **[E, documentación; no probado]**. El remitente de las funciones es una dirección del dominio de la plataforma, que debe estar verificado para enviar: ese paso depende de la cuenta del proveedor **[NV]**. Para el ensayo de la doble confirmación: definir `BIRD_API_KEY`, `ADN_CONFIRMACION_ACTIVA=1` y `ADN_WEB_URL`, poner el ajuste `adn_doble_confirmacion` en `true` en la rama de pruebas, programar la llamada a `enviar-confirmaciones` y registrar una persona nueva por QR con un buzón controlado. Al terminar, quitar los tres secretos y apagar el ajuste.
