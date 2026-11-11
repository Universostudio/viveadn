-- Origen de la prueba de exportacion: una iglesia sintetica con filas en todas las tablas y datos incomodos
-- para el CSV, mas una segunda iglesia que no debe aparecer en nada. Escribe el paquete exportado en :salida
-- y deshace todo al final. Uso: psql -v salida=/ruta/paquete.json -f origen.sql
\set ON_ERROR_STOP on
begin;
do $$ begin
  if exists (select 1 from public.iglesias where slug not like 'prueba-%') then
    raise exception 'Este script no se ejecuta en una base con iglesias reales';
  end if;
end $$;

insert into auth.users (id) values ('ea000000-0000-0000-0000-000000000001'), ('ea000000-0000-0000-0000-000000000002'), ('ea000000-0000-0000-0000-000000000003');
-- Con los disparadores normales: siembran los roles de cada iglesia
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ea100000-0000-0000-0000-00000000000a', 'Iglesia "Exportación", S.L.', 'prueba-exp', 'España', 'Sevilla', 'premium'),
  ('ea100000-0000-0000-0000-00000000000b', 'OTRA-IGLESIA-SECRETO', 'prueba-exp-otra', 'ES', 'Madrid', 'premium');

-- El resto se inserta sin disparadores (como en una restauracion), con datos validos por construccion
set local session_replication_role = replica;
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('ea000000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-00000000000a', 'María José', 'García "Mari" López', 'maria@prueba.test', 'propietario', true),
  ('ea000000-0000-0000-0000-000000000002', 'ea100000-0000-0000-0000-00000000000a', 'Adm', 'Prueba', 'adm@prueba.test', 'administrador', true),
  ('ea000000-0000-0000-0000-000000000003', 'ea100000-0000-0000-0000-00000000000b', 'Otra', 'Iglesia', 'otra-secreto@prueba.test', 'propietario', true);
insert into public.zonas (id, iglesia_id, codigo, nombre, descripcion) values
  ('ea200000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-00000000000a', 'Z1', 'Zona Norte, "centro"', E'Línea 1\r\nLínea 2'),
  ('ea200000-0000-0000-0000-000000000002', 'ea100000-0000-0000-0000-00000000000b', 'Z1', 'OTRA-IGLESIA-SECRETO', null);
insert into public.casas_oracion (id, iglesia_id, zona_id, codigo_zona, nombre, pais, ciudad, direccion, coordenadas_lat, coordenadas_lng, dia_reunion, hora_reunion, capacidad, activa) values
  ('ea300000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-00000000000a', 'ea200000-0000-0000-0000-000000000001', 'ZN-100001', 'Casa de Oración 1', 'España', 'Sevilla', 'Calle Falsa 123, 2º B', 37.38860000, -5.99530000, 'miercoles', '19:30', 12, true),
  ('ea300000-0000-0000-0000-000000000002', 'ea100000-0000-0000-0000-00000000000b', 'ea200000-0000-0000-0000-000000000002', 'ZN-100002', 'OTRA-IGLESIA-SECRETO', 'ES', 'Madrid', 'x', null, null, null, null, null, true);
insert into public.miembros (id, iglesia_id, crm_id, nombre, apellido, email, telefono, fecha_nacimiento, casa_oracion_id, notas, nivel_compromiso, activo) values
  ('ea400000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-00000000000a', 'M-1', 'Zoë', 'O''Brien, Jr.', 'zoe@prueba.test', '+34 600 111 222', '1990-02-28', 'ea300000-0000-0000-0000-000000000001', E'Primera línea\r\nSegunda línea con "comillas" y, comas', 'nuevo', true),
  ('ea400000-0000-0000-0000-000000000002', 'ea100000-0000-0000-0000-00000000000a', 'M-2', '  Espacios  ', '日本語 🙏', null, null, null, null, '', 'lider', true),
  ('ea400000-0000-0000-0000-000000000003', 'ea100000-0000-0000-0000-00000000000a', 'M-3', 'NULL', E'\\N', 'a@b.test', '', null, null, E'tab\there; punto y coma', 'maduro', false),
  ('ea400000-0000-0000-0000-000000000004', 'ea100000-0000-0000-0000-00000000000a', 'M-4', '=SUMA(1+1)', '@cmd', null, null, null, null, null, 'nuevo', true),
  ('ea400000-0000-0000-0000-000000000009', 'ea100000-0000-0000-0000-00000000000b', 'M-9', 'OTRA-IGLESIA-SECRETO', 'Otra', 'otra-secreto@prueba.test', null, null, null, null, 'nuevo', true);
insert into public.adn_miembro_contactos (iglesia_id, miembro_id, tipo, etiqueta, valor, orden) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea400000-0000-0000-0000-000000000001', 'correo', null, 'zoe.otro@prueba.test', 1),
  ('ea100000-0000-0000-0000-00000000000a', 'ea400000-0000-0000-0000-000000000001', 'direccion', 'Casa', E'Calle Falsa 123,\nSevilla', 2);
insert into public.adn_mensajes (id, iglesia_id, clave, canal, segmento, asunto, texto, total, enviados, omitidos) values
  ('ea800000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-00000000000a', 'ea810000-0000-0000-0000-000000000001', 'email', 'todos', 'Hola, "amigos"', E'Hola {{nombre}},\nbienvenido', 2, 1, 1);
insert into public.adn_mensaje_destinatarios (iglesia_id, mensaje_id, miembro_id, destino, texto_final, estado, motivo, referencia, enviado_en) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea800000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001', 'zoe@prueba.test', E'Hola Zoë,\nbienvenido', 'enviado', null, 'sumidero:1', now()),
  ('ea100000-0000-0000-0000-00000000000a', 'ea800000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000002', null, null, 'omitido', 'sin_destino', null, null);
insert into public.adn_comunicacion_bajas (iglesia_id, miembro_id, canal) values ('ea100000-0000-0000-0000-00000000000a', 'ea400000-0000-0000-0000-000000000002', 'email');
insert into public.adn_consentimientos (iglesia_id, miembro_id, canal, estado, origen) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea400000-0000-0000-0000-000000000001', 'email', 'suscrito', 'wix'),
  ('ea100000-0000-0000-0000-00000000000a', 'ea400000-0000-0000-0000-000000000002', 'sms', 'nunca', 'wix'),
  ('ea100000-0000-0000-0000-00000000000b', 'ea400000-0000-0000-0000-000000000009', 'email', 'suscrito', 'prueba');
insert into public.consolidaciones (id, iglesia_id, miembro_id, consolidador_id, casa_oracion_id, fecha_conversion, primer_contacto_notas, completado) values
  ('ea500000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-00000000000a', 'ea400000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001', 'ea300000-0000-0000-0000-000000000001', '2026-11-01 10:00:00+00', 'Llamado; "dijo que sí"', false);
insert into public.asistencias (iglesia_id, casa_oracion_id, miembro_id, fecha, presente, notas) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea300000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001', '2026-11-04', true, 'ok');
insert into public.progreso_formacion (iglesia_id, miembro_id, nivel, nombre_nivel, porcentaje, fecha_inicio) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea400000-0000-0000-0000-000000000001', 1, 'Fundamentos', 40, '2026-10-01');
insert into public.logros (iglesia_id, miembro_id, tipo, nombre, puntos_otorgados) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea400000-0000-0000-0000-000000000001', 'asistencia', 'Primera semana', 10);
insert into public.eventos (id, iglesia_id, titulo, descripcion, tipo, inicia_en, termina_en, lugar) values
  ('ea600000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-00000000000a', 'Culto, domingo', 'Descripción con ñ y "comillas"', 'culto', '2026-11-08 10:00:00+00', '2026-11-08 12:00:00+00', 'Templo');
insert into public.asistencia_evento (iglesia_id, evento_id, miembro_id, presente) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea600000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001', true);
insert into public.evento_checkin (iglesia_id, evento_id, token) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea600000-0000-0000-0000-000000000001', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
insert into public.checkin_registros (iglesia_id, evento_id, miembro_id, ip_hash, creado) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea600000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', true);
insert into public.programas_formacion (id, iglesia_id, nombre) values ('ea700000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-00000000000a', 'Discipulado');
insert into public.programa_lecciones (id, iglesia_id, programa_id, orden, titulo) values
  ('ea710000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-00000000000a', 'ea700000-0000-0000-0000-000000000001', 1, 'Lección 1');
insert into public.inscripciones_formacion (id, iglesia_id, programa_id, miembro_id, estado, completado_en) values
  ('ea720000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-00000000000a', 'ea700000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001', 'completado', '2026-11-05 09:00:00+00');
insert into public.avance_formacion (iglesia_id, programa_id, inscripcion_id, leccion_id) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea700000-0000-0000-0000-000000000001', 'ea720000-0000-0000-0000-000000000001', 'ea710000-0000-0000-0000-000000000001');
insert into public.certificados (iglesia_id, programa_id, inscripcion_id, miembro_id, titular, programa_nombre) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea700000-0000-0000-0000-000000000001', 'ea720000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001', 'Zoë O.', 'Discipulado');
insert into public.enlaces_dar (iglesia_id, tipo, url, nombre) values
  ('ea100000-0000-0000-0000-00000000000a', 'paypal', 'https://example.test/dar?x=1&y=2', 'Ofrenda, general');
insert into public.iglesia_modulos (iglesia_id, modulo, origen) values ('ea100000-0000-0000-0000-00000000000a', 'eventos', 'addon');
insert into public.dar_config (iglesia_id, titulo, moneda) values ('ea100000-0000-0000-0000-00000000000a', 'Dar', 'EUR');
insert into public.invitaciones (iglesia_id, email, nombre, apellido, rol, token_hash) values
  ('ea100000-0000-0000-0000-00000000000a', 'invitado@prueba.test', 'Inv', 'Itado', 'colaborador', 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc');
insert into public.adn_informe_descargas (iglesia_id, usuario_id, informe, filas) values
  ('ea100000-0000-0000-0000-00000000000a', 'ea000000-0000-0000-0000-000000000001', 'miembros', 4);
insert into public.plataforma_auditoria (actor, accion, iglesia_id, detalle) values
  (null, 'crear_iglesia', 'ea100000-0000-0000-0000-00000000000a', '{"propietario": "maria@prueba.test", "ip_hash": "dddddddddddddddddddddddddddddddd", "nota": "con, coma y \"comillas\""}');
reset session_replication_role;

-- Gancho opcional: otras pruebas reutilizan estas dos iglesias (psql -v despues=ruta/del/script.sql)
\if :{?despues}
  \i :despues
\endif

\o :salida
select public.adn_exportar_paquete('ea100000-0000-0000-0000-00000000000a');
\o
-- Con -v conservar=1 los datos quedan en la base (los usa tests/aislamiento_api.sh, que luego los borra)
\if :{?conservar}
  commit;
\else
  rollback;
\endif
