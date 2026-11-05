# Infraestructura multi-iglesia de ViveADN

Estado verificado en producción el 5 de noviembre de 2026 (proyecto `viveadn-saas`, región eu-west-1). Este documento es la referencia única: si algo de aquí cambia, se cambia aquí en el mismo PR.

## 1. Modelo

- **Inquilino (tenant):** una iglesia (`iglesias`). Todos los datos de negocio llevan `iglesia_id`.
- **Una sola base de datos compartida, con aislamiento por filas** (RLS de PostgreSQL). No usamos un esquema ni una base por iglesia. Es el modelo adecuado para muchas iglesias pequeñas y medianas, con el menor coste y la menor operación. Para un cliente muy grande que exija aislamiento total queda la salida de un proyecto Supabase propio con el mismo código.
- **Un usuario pertenece a una sola iglesia** (`perfiles.id = auth.uid()`, con `iglesia_id`). La iglesia activa se resuelve en la base con `private.get_iglesia_id()`.
- **Red de iglesias:** una iglesia madre puede tener sedes (un solo nivel). Cada sede sigue siendo un inquilino independiente. La madre solo recibe cifras agregadas, y solo de las sedes que la plataforma autoriza (`red_acceso`).
- **Planes y módulos:** cada iglesia tiene un plan y puede tener módulos extra. Todo permiso exige que el módulo esté activo y que la iglesia esté activa (`private.tiene_modulo`), de modo que suspender una iglesia bloquea en la propia base el acceso a sus datos de negocio. Siguen siendo legibles, a propósito, la fila de la propia iglesia, el propio perfil y la configuración mínima (roles, módulos, enlaces de dar y apariencia), porque la web los necesita para iniciar sesión y mostrar el aviso de suspensión.

## 2. Garantías verificadas

| Garantía | Cómo se cumple | Verificado |
| --- | --- | --- |
| Todas las tablas con RLS | 27 de 27 tablas de `public` | Producción |
| Cada fila pertenece a una iglesia | 18 tablas con `iglesia_id`, por defecto `private.get_iglesia_id()` | Producción |
| Sin referencias entre iglesias | Claves foráneas compuestas `(iglesia_id, id)`; una comprobación de `permisos.sql` rechaza cualquier clave simple entre dos tablas de iglesia | Producción y CI |
| Políticas eficientes | `(select private.get_iglesia_id())` se evalúa una vez por consulta | Producción |
| Permisos por rol, por iglesia y por plan | `private.tiene_permiso` + `private.tiene_modulo` | Producción |
| Suspender una iglesia corta el acceso a sus datos de negocio | `tiene_modulo` exige `iglesias.activa`; solo quedan legibles su fila de iglesia, su propio perfil y la configuración mínima | Producción |
| Ningún visitante anónimo toca tablas ni funciones | `permisos.sql` en cada PR | CI |
| Ninguna función SECURITY DEFINER expuesta en `public` | `permisos.sql` | CI |
| Tablas de uso solo del servidor | `plataforma_auditoria`, `plataforma_ajustes`, `registro_codigos`, `registro_intentos` | CI |
| Una iglesia no cambia su plan, estado, dirección ni red | Disparador `private.guardar_iglesia` | CI |
| Aislamiento entre iglesias | `aislamiento.sql` | CI |

## 3. Únicas vías entre iglesias

Todo lo que cruza iglesias pasa por una función de borde con `service_role`, que valida quién llama y devuelve solo lo necesario.

| Función | Quién la usa | Qué devuelve |
| --- | --- | --- |
| `plataforma` | Administrador de la plataforma | Gestión de iglesias, planes, red y códigos |
| `red-resumen` | Superadministrador de una iglesia madre | Solo conteos agregados de sus sedes |
| `dar-publico` | Visitante | Fondos y apariencia de una iglesia, sin datos de personas |
| `checkin-evento` | Visitante con el QR de un evento | Registro de asistencia, con respuesta idéntica para nuevo y existente |
| `registro-iglesia` | Visitante con código de beta | Alta de una iglesia y su superadministrador |
| `invitaciones` | Persona invitada | Aceptar una invitación (pública por diseño) |

## 4. Brechas, por prioridad

**P1. Hay que cerrarlas antes de abrir a terceros.**

1. **Límites del plan: resuelto.** Disparadores `SECURITY DEFINER` rechazan altas por encima de `max_miembros` y `max_usuarios` con `PLAN_LIMITE`, serializadas por iglesia con un cerrojo; las invitaciones vigentes reservan plaza y el registro por QR responde "cerrado" sin plazas. Pruebas en `limites_plan.sql` y `limites_concurrencia.sh`.
2. **Archivos.** No existe almacenamiento todavía. Antes de subir el primer logo, certificado o documento hay que diseñar un cubo con políticas por prefijo de iglesia y una prueba de aislamiento.
3. **Ciclo de vida de la iglesia: etapas resueltas, exportación y borrado pendientes.** `iglesias.etapa` (onboarding, prueba, activa, receso, suspendida) gobierna `activa` mediante un disparador, de modo que políticas y funciones de borde no cambian. Receso y suspendida cierran el acceso y conservan los datos; una prueba vencida corta los módulos. Falta la exportación y el borrado completo de los datos de una iglesia (RGPD), incluidos usuarios de acceso, archivos y registros de auditoría.

**P2. Para escalar con orden.**

4. **Índices: resuelto.** Nueve índices que empiezan por `iglesia_id` cubren las claves compuestas de `asistencia_evento`, `checkin_registros`, `evento_checkin`, `eventos`, `invitaciones` y `zonas`.
5. **Un usuario, una iglesia.** Consultores, pastores regionales y agentes de soporte no caben en ese modelo. Decisión: no cambiamos el modelo. El soporte entra por una función de borde con acceso de solo lectura, con permiso de la iglesia, por tiempo limitado y registrado.
6. **Registro de cambios por iglesia.** Hoy solo se audita la plataforma. Los datos pastorales necesitan un historial de quién cambió qué.
7. **Subdominio por iglesia y dominio propio.** Existe `slug`, pero el enrutado por subdominio no está.

**P3. Mejoras.**

8. Vecino ruidoso: la base permite 60 conexiones y Auth usa 10 fijas. Faltan límites de tasa por iglesia.
9. `rol_permisos` no lleva `iglesia_id`; su aislamiento depende de la política de `roles`. Conviene denormalizarlo.
10. La huella de IP usa la clave de servicio como secreto: rotarla invalida las huellas.
11. Verificación en dos pasos obligatoria para administradores.

## 5. Reglas para toda tabla nueva

1. `iglesia_id uuid not null default private.get_iglesia_id()` con clave foránea a `iglesias` y `on delete cascade`.
2. RLS activada y políticas de lectura, alta, edición y borrado que filtren por `(select private.get_iglesia_id())` y exijan el permiso del módulo con `(select private.tiene_permiso('...'))`.
3. Referencias a otras tablas de la iglesia con clave foránea compuesta `(iglesia_id, id)`.
4. Índice que empiece por `iglesia_id`.
5. `grant` explícito a `authenticated` y `service_role`; nada para `anon`.
6. Si solo la usa el servidor: política que lo niega todo, sin permisos, y añadirla a `solo_servidor` en `supabase/tests/permisos.sql`.
7. Prueba en `supabase/tests/aislamiento.sql` o en su propio archivo, incluida en `ejecutar.sh`.
8. Cualquier función privilegiada va en `private` con `search_path` fijo, o es una función de borde con `service_role` que valida a quien llama.

## 6. Orden de trabajo

1. Hecho: corte duro de los límites del plan e índices de las tablas que crecen.
2. Ciclo de vida de la iglesia: etapas hechas; falta la exportación y el borrado de una iglesia.
3. Almacenamiento de archivos con aislamiento por iglesia.
4. OP72 v2 con el modo de alias.
5. Motor de formación, QR en sus tres partes, alianzas e integraciones.
