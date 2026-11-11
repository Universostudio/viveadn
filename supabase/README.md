# Base de datos de Vive ADN

Proyecto de producción en Supabase: **viveadn-saas** (ref `xrjbvjqhpwjjtcfdlsbq`, región eu-west-1).
La cuenta tiene otros proyectos de Supabase: comprueba siempre esta referencia antes de ejecutar nada.

## Contenido

- `schema/esquema_completo.sql`: estado completo de la base a 24 de octubre de 2026 (tablas, funciones, triggers, seguridad por filas y permisos). Sirve para reconstruir la base en un proyecto **nuevo y vacío**. No se ejecuta contra producción.
- `schema/seed.sql`: datos de catálogo (módulos, planes, permisos). Sin datos de personas.
- `functions/plataforma/index.ts`: función del panel de plataforma, igual a la desplegada (versión 1).
- `functions/dar-publico/index.ts`: función pública de la página `/dar/<slug>`. Solo devuelve el nombre de la iglesia y sus enlaces de recaudo activos. Se despliega con verificación de JWT (la web envía la clave anónima).
- `functions/invitaciones/index.ts`: invitaciones de acceso por correo.
- `functions/checkin-evento/`: registro por QR de asistencia (`/checkin/<enlace>`). Pública, con verificación de JWT (la web envía la clave anónima). `validar.ts` valida lo recibido y se prueba con `npm run test:checkin`; la lógica de ventana, tope, límite por dispositivo y duplicados está en las funciones `info_checkin` y `registrar_checkin`, que solo ejecuta `service_role`.
- `migrations/`: a partir de ahora, cada cambio de base de datos es un archivo aquí.

## Reglas

1. Ningún cambio de base de datos se hace a mano en el editor SQL de producción.
2. Cada cambio es una migración nueva en `migrations/`, con nombre `AAAAMMDDHHMMSS_descripcion.sql`, revisada antes de aplicarse.
3. Al aplicar una migración en producción se registra con el mismo nombre en Supabase, para que el historial coincida.
4. Si se cambia la función `plataforma`, se actualiza aquí en el mismo commit que se despliega.
5. Nunca se suben claves: `.env` está excluido del repositorio.

## Historial ya registrado en producción

Estas cuatro migraciones ya están aplicadas y su contenido está incluido en `esquema_completo.sql`:

| Versión | Nombre |
|---|---|
| 20261024013525 | roles_y_permisos_por_iglesia |
| 20261024015036 | catalogo_modulos_y_planes |
| 20261024015537 | panel_plataforma_base |
| 20261024015554 | plataforma_auditoria |

Lo anterior a ellas (iglesias, miembros, casas, consolidación, endurecimiento de seguridad) se aplicó a mano y solo existe en `esquema_completo.sql`.

## Reconstruir en un proyecto nuevo

1. Crear un proyecto de Supabase vacío.
2. Ejecutar `schema/esquema_completo.sql` y después `schema/seed.sql`.
3. Desplegar `functions/plataforma`.
4. Crear el usuario administrador e insertarlo en `plataforma_admins`.
5. Aplicar en orden las migraciones de `migrations/` posteriores al 24 de octubre de 2026.

## Notas desde la migración del 25 de octubre de 2026

- Las funciones nuevas ya no reciben permiso de ejecución por defecto: cada migración que cree una función debe incluir su `grant execute` para los roles que la usen.
- Las pruebas de seguridad se ejecutan con `supabase/tests/ejecutar.sh` sobre un Postgres local. Antes de aplicar cualquier migración en producción deben pasar todas.
- Las migraciones se aplican en producción con la herramienta de migraciones de Supabase usando el mismo nombre del archivo; después se renombra el archivo con la versión que asigne Supabase para que el historial coincida.

## Prueba de las consultas de la web (añadida el 27 de octubre de 2026)

Las pruebas de `aislamiento.sql` verifican la base de datos, pero no las consultas que hace la web a través de la API. El 27-10 una migración convirtió claves foráneas en compuestas y las relaciones pedidas por nombre de columna (`lider_id(...)`) dejaron de resolverse. Desde entonces, antes de aplicar una migración:

1. Ejecutar `supabase/tests/ejecutar.sh` (deja la base `viveadn_pruebas` con el esquema y las migraciones).
2. Cargar datos de ejemplo y arrancar PostgREST 12 con `supabase/tests/postgrest.conf`.
3. Ejecutar `python3 supabase/tests/consultas_web.py <uuid-de-un-propietario>`: debe terminar con "TODAS LAS CONSULTAS DE LA WEB FUNCIONAN".

Regla para la web: las relaciones con claves compuestas se piden por el nombre de la restricción, por ejemplo `perfiles!casas_oracion_lider_fk(nombre)`.

## Permisos explícitos (desde el 27 de octubre de 2026)

Supabase deja de conceder permisos automáticos a las tablas nuevas de `public` el 30-10-2026. La migración `20261027090000_permisos_explicitos` adelantó ese comportamiento en producción y lo extendió a secuencias y funciones: **todo objeto nuevo nace sin permisos para la API**.

Toda migración que cree una tabla incluye en el mismo archivo las tres piezas:

```sql
create table public.ejemplo (...);
grant select, insert, update, delete on public.ejemplo to authenticated, service_role;  -- 1. permisos
alter table public.ejemplo enable row level security;                                  -- 2. seguridad por filas
create policy ejemplo_ver on public.ejemplo for select to authenticated
  using (iglesia_id = private.get_iglesia_id());                                       -- 3. políticas
```

Nunca se concede nada a `anon`. Toda función nueva lleva su `grant execute` solo a los roles que la usen.

`supabase/tests/permisos.sql` (incluido en `ejecutar.sh`) falla, con el nombre de la tabla, si falta cualquiera de las tres piezas, si `anon` tiene algún permiso, si queda un permiso por defecto que exponga objetos futuros, o si aparece una función `SECURITY DEFINER` en `public` o una vista sin `security_invoker`. Las pruebas se ejecutan solas en GitHub en cada solicitud de unión (`.github/workflows/pruebas.yml`).

## Reversiones (desde el 11 de noviembre de 2026)

`reversiones/` guarda, junto a cada migración nueva, el script que la deshace. No es una migración: el CLI no lo aplica y solo se ejecuta a mano por orden de Gerencia. Cada uno se prueba en `tests/`: aplica, revierte, compara el esquema con el anterior y comprueba que no se pierde ningún dato de negocio (`tests/adn_reversion.sh`). Los objetos nuevos llevan el prefijo `adn_`.

## Aislamiento entre iglesias con dos usuarios (añadido el 11 de noviembre de 2026)

`supabase/tests/adn_aislamiento_total.sql` ataca todas las tablas con `iglesia_id` desde dos usuarios de prueba y se ejecuta con `ejecutar.sh`. Para repetir los mismos ataques a través de la API, con PostgREST en marcha como en la sección anterior: `PGUSER=postgres supabase/tests/aislamiento_api.sh viveadn_pruebas`. Detalle, fugas inyectadas y límites en `docs/AISLAMIENTO.md`.

## Cuentas creadas por SQL y el inicio de sesión (añadido el 11 de noviembre de 2026)

Una cuenta insertada en `auth.users` por SQL con NULL en columnas de texto como `email_change`, `confirmation_token` o `phone_change` rompe el inicio de sesión del servicio de Supabase (GoTrue no convierte NULL a texto). Las cuentas creadas con la API de administración (`auth.admin.createUser`, que es lo que usan las funciones de borde) no tienen el problema. `supabase/tests/auth_usuarios_sin_nulos.sql` lo comprueba en una base con el esquema real, sin imprimir datos de usuarios, y se omite en la base local, que solo tiene la columna `id`; su autoprueba (`auth_usuarios_sin_nulos_autoprueba.sql`) simula las columnas y está en `ejecutar.sh`. En la rama de pruebas, ejecutarlo después de cualquier siembra por SQL. `aislamiento_api.sh` ya rellena con cadenas vacías las cuentas que siembra.
