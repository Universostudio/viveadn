-- =====================================================================
-- Vive ADN: datos de catalogo (modulos, planes, permisos)
-- Extraidos de produccion el 24 de octubre de 2026.
-- Se ejecutan despues de esquema_completo.sql. No contienen datos de
-- personas ni de iglesias. Los roles de cada iglesia los crea el trigger
-- iglesias_sembrar_roles al insertar la iglesia.
-- =====================================================================

insert into public.modulos (clave, nombre, descripcion, tipo, orden) values
('app_marca', 'App con marca propia', 'App instalable con el nombre y colores de la iglesia', 'especial', 230),
('asistencia', 'Asistencia', 'Registro de asistencia por casa', 'nucleo', 40),
('biblioteca', 'Biblioteca de recursos', 'Materiales y recursos descargables', 'incluido', 150),
('casas', 'Casas de Oración', 'Casas de oración, líderes y reuniones', 'nucleo', 20),
('comunicacion', 'Comunicación por correo', 'Mensajes y plantillas por correo', 'incluido', 130),
('consolidacion_etapas', 'Consolidación por etapas', 'Etapas con Gatekeeper hasta el bautismo', 'especial', 210),
('consolidacion', 'Consolidación 72 horas', 'Módulo 0 y seguimiento del nuevo convertido con alertas', 'nucleo', 50),
('credenciales', 'Credenciales con foto y QR', 'Tarjetas de identificación imprimibles', 'especial', 220),
('formacion', 'Formación', 'Visualización del progreso de formación', 'incluido', 110),
('gamificacion', 'Gamificación', 'Puntos, rachas y logros', 'incluido', 140),
('iglesia', 'Identidad de la iglesia', 'Nombre, marca y configuración', 'nucleo', 80),
('miembros', 'Miembros', 'Base de datos de personas y perfiles', 'nucleo', 10),
('reportes', 'Reportes', 'Reportes de la iglesia', 'incluido', 120),
('roles', 'Roles y permisos', 'Roles editables y permisos por módulo', 'nucleo', 70),
('usuarios', 'Usuarios', 'Equipo con acceso al sistema', 'nucleo', 60),
('whatsapp', 'WhatsApp Business', 'Mensajes por WhatsApp con la API oficial', 'incluido', 160),
('zonas', 'Zonas', 'Zonas geográficas y códigos ZONA-CÓDIGO', 'nucleo', 30);

insert into public.planes (clave, nombre, descripcion, max_miembros, max_usuarios, orden, activo) values
('semilla', 'Semilla', 'Para empezar: núcleo del sistema con límite pequeño', 50, 3, 1, true),
('basico', 'Básico', 'Núcleo más formación, reportes y comunicación por correo', 300, 10, 2, true),
('premium', 'Premium', 'Todo lo disponible, hasta 5.000 personas. Más de eso, plan a medida.', 5000, null, 3, true);

insert into public.plan_modulos (plan, modulo) values
('semilla', 'asistencia'), ('semilla', 'casas'), ('semilla', 'consolidacion'), ('semilla', 'iglesia'),
('semilla', 'miembros'), ('semilla', 'roles'), ('semilla', 'usuarios'), ('semilla', 'zonas'),
('basico', 'asistencia'), ('basico', 'casas'), ('basico', 'comunicacion'), ('basico', 'consolidacion'),
('basico', 'formacion'), ('basico', 'iglesia'), ('basico', 'miembros'), ('basico', 'reportes'),
('basico', 'roles'), ('basico', 'usuarios'), ('basico', 'zonas'),
('premium', 'asistencia'), ('premium', 'biblioteca'), ('premium', 'casas'), ('premium', 'comunicacion'),
('premium', 'consolidacion_etapas'), ('premium', 'consolidacion'), ('premium', 'credenciales'),
('premium', 'formacion'), ('premium', 'gamificacion'), ('premium', 'iglesia'), ('premium', 'miembros'),
('premium', 'reportes'), ('premium', 'roles'), ('premium', 'usuarios'), ('premium', 'whatsapp'),
('premium', 'zonas');

insert into public.permisos (clave, modulo, descripcion, sensible) values
('asistencia.registrar_propia', 'asistencia', 'Registrar y ver asistencia de la casa que lidera', false),
('asistencia.registrar', 'asistencia', 'Registrar asistencia de cualquier casa', false),
('asistencia.ver', 'asistencia', 'Ver toda la asistencia', false),
('casas.crear', 'casas', 'Crear casas de oracion', false),
('casas.editar', 'casas', 'Editar casas de oracion', false),
('casas.eliminar', 'casas', 'Eliminar casas de oracion', true),
('casas.ver_propia', 'casas', 'Ver solo la casa de oracion que lidera', false),
('casas.ver', 'casas', 'Ver todas las casas de oracion', false),
('consolidacion.crear', 'consolidacion', 'Abrir procesos de consolidacion', false),
('consolidacion.editar', 'consolidacion', 'Editar cualquier proceso de consolidacion', false),
('consolidacion.eliminar', 'consolidacion', 'Eliminar procesos de consolidacion', true),
('consolidacion.reasignar', 'consolidacion', 'Cambiar el consolidador asignado', false),
('consolidacion.registrar_contacto', 'consolidacion', 'Registrar contactos en los procesos asignados a el', false),
('consolidacion.ver_asignados', 'consolidacion', 'Ver solo los nuevos convertidos asignados a el', false),
('consolidacion.ver_casa', 'consolidacion', 'Ver la consolidacion de los miembros de su casa de oracion', false),
('consolidacion.ver', 'consolidacion', 'Ver todos los procesos de consolidacion', false),
('formacion.actualizar', 'formacion', 'Actualizar el progreso de formacion', false),
('formacion.ver', 'formacion', 'Ver el progreso de formacion', false),
('gamificacion.gestionar', 'gamificacion', 'Otorgar y editar logros', false),
('gamificacion.ver', 'gamificacion', 'Ver logros y puntos', false),
('iglesia.configurar', 'iglesia', 'Cambiar nombre, marca y configuracion de la iglesia', true),
('miembros.crear', 'miembros', 'Registrar miembros', false),
('miembros.editar', 'miembros', 'Editar miembros', false),
('miembros.eliminar', 'miembros', 'Eliminar miembros', true),
('miembros.exportar', 'miembros', 'Exportar datos de miembros', true),
('miembros.importar', 'miembros', 'Importar miembros', true),
('miembros.ver_asignados', 'miembros', 'Ver solo los miembros que le corresponden (su casa o sus nuevos convertidos)', false),
('miembros.ver', 'miembros', 'Ver todos los miembros de la iglesia', false),
('reportes.ver', 'reportes', 'Ver reportes', false),
('roles.gestionar', 'roles', 'Crear y editar roles y sus permisos', true),
('usuarios.gestionar', 'usuarios', 'Invitar usuarios, cambiar sus roles y activarlos o desactivarlos', true),
('usuarios.ver', 'usuarios', 'Ver el equipo con acceso al sistema', false),
('zonas.gestionar', 'zonas', 'Crear, editar y eliminar zonas', false),
('zonas.ver', 'zonas', 'Ver zonas', false);

-- El administrador de plataforma se anade a mano tras crear su usuario:
-- insert into public.plataforma_admins (user_id) values ('<uuid del usuario>');
