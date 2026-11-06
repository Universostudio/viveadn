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
2. **Archivos: resuelto.** Dos cubos: `iglesia-marca` (lectura pública, para logos; 2 MB; PNG, JPEG y WebP, sin SVG porque puede llevar scripts) e `iglesia-archivos` (privado, se lee con URL firmada; 10 MB; PDF e imágenes). Toda ruta empieza por `{iglesia_id}/`, y las políticas de `storage.objects` exigen que esa carpeta sea la iglesia de quien pregunta; escribir exige `iglesia.configurar` y leer el cubo privado exige que la iglesia esté operativa. La exportación lista los archivos y el borrado los elimina de Storage. Las pruebas están en `archivos.sql`.
3. **Ciclo de vida de la iglesia: resuelto.** `iglesias.etapa` (onboarding, prueba, activa, receso, suspendida) gobierna `activa` mediante un disparador, de modo que políticas y funciones de borde no cambian. Receso y suspendida cierran el acceso y conservan los datos; una prueba vencida corta los módulos. La exportación (`exportar_iglesia`) recorre todas las tablas con `iglesia_id` y excluye tokens y huellas. El borrado (`borrar_iglesia`) exige receso o suspendida, un plazo programado de 7 a 90 días y la dirección escrita; borra la iglesia en cascada, las cuentas de Auth y el detalle de su auditoría. CI rechaza una tabla nueva que no lleve `iglesia_id` ni esté clasificada como global.

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
8. Todo archivo nuevo va en uno de los dos cubos, bajo `{iglesia_id}/`; un cubo nuevo repite las políticas de prefijo y se añade a `CUBOS_IGLESIA` en la función `plataforma` para que la exportación y el borrado lo cubran.
9. Cualquier función privilegiada va en `private` con `search_path` fijo, o es una función de borde con `service_role` que valida a quien llama.

## Modo alias (OP72 v2)

`iglesias.modo_alias` hace que la iglesia registre a las personas con un alias o ID interno en lugar de su identidad civil. Si el dato no se guarda, no puede filtrarse ni hace falta enmascararlo. Con el modo activo, la base normaliza cada miembro nuevo (disparador `miembros_modo_alias`): el alias va en `nombre`, `apellido` queda vacío y no se guarda correo. El teléfono se conserva porque la llamada de las 72 horas lo necesita. Los miembros que ya existían no se tocan al activar el modo. Los formularios de alta, el registro público por QR y la importación se adaptan solos; ninguna lista cambia, porque ya muestran `nombre` y `apellido` juntos. No hay modo mixto: una iglesia que quiere nombres reales no activa el modo.

## OP72 gratuito y de pago

El módulo `consolidacion` está en todos los planes y es la parte gratuita: registro, asignación, tres contactos, resultado y las 72 horas con su color. El módulo `op72_avanzado` es la parte de pago: viene en Básico y Premium y se contrata como complemento en Semilla con la misma maquinaria de planes y complementos que ya existe, sin lógica nueva de licencias. Hoy incluye las métricas avanzadas (`metricas_op72`: tiempos de primer contacto, cumplimiento de las 72 horas y desglose por consolidador y casa), que respetan los permisos de quien las pide. Las alertas automáticas por correo o WhatsApp quedan para cuando exista el canal de envío. El color de alerta se calcula siempre desde `fecha_conversion`: la columna `estado_alerta` solo se actualiza al escribir, envejece sola y no se usa para mostrar ni para filtrar.

## Motor de formación

Cada iglesia crea sus propios programas de formación (`programas_formacion`), con lecciones ordenadas (`programa_lecciones`), inscribe a sus miembros (`inscripciones_formacion`) y registra el avance lección a lección (`avance_formacion`). Convive con `progreso_formacion`, el seguimiento fijo por niveles que ya existía. Las claves foráneas llevan `iglesia_id` y el avance lleva además `programa_id`, de modo que la propia base impide mezclar iglesias o apuntar a una lección de otro programa. La finalización se calcula siempre desde las lecciones y nadie puede fijarla a mano, ni siquiera quien edita los programas: un disparador rechaza cambiar `estado` a completado o tocar `completado_en`, y solo el recálculo interno lo hace. Quitar un avance o añadir una lección reabre a quien ya había terminado, y un programa sin lecciones nunca se completa. El recálculo bloquea la fila de la inscripción, de modo que dos avances simultáneos no pueden dejar una inscripción en curso con todas las lecciones hechas (lo cubre `formacion_concurrencia.sh`). Una inscripción no cambia de programa ni de miembro, y una lección no cambia de programa: se borran y se crean de nuevo, para que una finalización no se pueda traspasar. Esa garantía es la base de los certificados. Permisos: leer exige `formacion.ver`, inscribir y avanzar `formacion.actualizar`, y editar programas y lecciones `formacion.programas` (administrador, coadministrador y líder de escuela).

Certificados con QR (`certificados`). Solo se emite un certificado para una inscripción completada y únicamente mediante `emitir_certificado`, que exige `formacion.certificar` (administrador, coadministrador y líder de escuela) y es idempotente: nadie inserta, edita ni borra filas a mano, de modo que el titular y el programa que se verifican son los de la emisión. El titular se reduce al emitir: nombre e inicial del apellido ("Ana G."), o solo el alias en una iglesia en modo alias. `revocar_certificado` revoca o restaura. El código del QR son 32 caracteres hexadecimales aleatorios, imposibles de adivinar o enumerar. La verificación pública (`/verificar/:codigo`) pasa por la función de borde `verificar-certificado`, que solo llama a `info_certificado` (reservada a `service_role`) y devuelve estado, iglesia, programa, fecha y, si es válido, el titular reducido; un certificado revocado no muestra al titular y la verificación sigue funcionando aunque la iglesia esté en receso. La pantalla de verificación no se indexa y no envía el referente. La lógica privilegiada vive en `private` y las funciones públicas son envoltorios sin privilegios. Lo cubren `certificados.sql` y `npm run test:certificados`.

## 6. Orden de trabajo

1. Hecho: corte duro de los límites del plan e índices de las tablas que crecen.
2. Hecho: ciclo de vida de la iglesia, con exportación y borrado.
3. Hecho: almacenamiento de archivos con aislamiento por iglesia.
4. Hecho: OP72 v2, con modo alias y versión gratuita y de pago. Falta el canal de envío de las alertas automáticas.
5. Motor de formación: programas, lecciones, avance y certificados con QR hechos. Después, QR en sus tres partes, alianzas e integraciones.
