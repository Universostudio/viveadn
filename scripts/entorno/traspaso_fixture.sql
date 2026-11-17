-- Datos sintéticos para probar el traspaso en LOCAL sobre el estado base del real: dos iglesias (una real y una demo) con propietario, personas, zona, casa, eventos,
-- asistencias y consolidaciones. Así las migraciones que actúan sobre filas existentes (sembrar métodos, consentimientos, roles nuevos...) se ejercitan de verdad.
-- Ids fijos para que dos bases con el mismo fixture se puedan comparar fila a fila.
\set ON_ERROR_STOP on
insert into auth.users (id) values ('f1000000-0000-0000-0000-000000000001'), ('f1000000-0000-0000-0000-000000000002');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, es_demo, etapa) values
  ('f2000000-0000-0000-0000-000000000001', 'Fixture Real', 'fixture-real', 'ES', 'Sevilla', 'premium', false, 'activa'),
  ('f2000000-0000-0000-0000-000000000002', 'Fixture Demo', 'fixture-demo', 'ES', 'Madrid', 'basico', true, 'activa');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'Pro', 'Pietario', 'prop@fixture.test', 'propietario', true),
  ('f1000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000002', 'Dem', 'Pietario', 'demo@fixture.test', 'propietario', true);
insert into public.zonas (id, iglesia_id, codigo, nombre) values ('f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'ZN-F00001', 'Zona F');
insert into public.casas_oracion (id, iglesia_id, zona_id, codigo_zona, nombre, pais, ciudad, direccion) values
  ('f4000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'ZN-F00001', 'Casa F', 'ES', 'Sevilla', 'Calle F 1');
insert into public.miembros (id, iglesia_id, nombre, apellido, email, telefono, casa_oracion_id, tipo, nivel_compromiso, fecha_conversion) values
  ('f5000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'Ana', 'Uno', 'ana@fixture.test', '+34600111222', 'f4000000-0000-0000-0000-000000000001', 'miembro', 'activo', now() - interval '40 days'),
  ('f5000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000001', 'Beto', 'Dos', 'beto@fixture.test', null, 'f4000000-0000-0000-0000-000000000001', 'nuevo_creyente', 'nuevo', now() - interval '3 days'),
  ('f5000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000002', 'Cata', 'Tres', 'cata@fixture.test', '+34600333444', null, 'miembro', 'activo', null);
insert into public.consolidaciones (id, iglesia_id, miembro_id, casa_oracion_id, fecha_conversion) values
  ('f6000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000002', 'f4000000-0000-0000-0000-000000000001', now() - interval '3 days');
insert into public.asistencias (id, iglesia_id, casa_oracion_id, miembro_id, fecha, presente) values
  ('f7000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001', current_date - 7, true);
insert into public.eventos (id, iglesia_id, titulo, inicia_en) values ('f8000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'Culto F', now() + interval '2 days');

-- Situaciones que tiene el real hoy: una iglesia en modo alias enlazada a una madre (como casa-reino) y una demo en receso con personas y un usuario (como prueba-borrado-ficticia)
insert into auth.users (id) values ('f1000000-0000-0000-0000-000000000003'), ('f1000000-0000-0000-0000-000000000004');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, es_demo, etapa, modo_alias, iglesia_madre_id, red_acceso) values
  ('f2000000-0000-0000-0000-000000000003', 'Fixture Alias', 'fixture-alias', 'ES', 'Cadiz', 'premium', false, 'activa', true, 'f2000000-0000-0000-0000-000000000001', 'resumen');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, es_demo, etapa) values
  ('f2000000-0000-0000-0000-000000000004', 'Fixture Receso', 'fixture-receso', 'ES', 'Leon', 'premium', true, 'receso');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('f1000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000003', 'Ali', 'As', 'alias@fixture.test', 'propietario', true),
  ('f1000000-0000-0000-0000-000000000004', 'f2000000-0000-0000-0000-000000000004', 'Rec', 'Eso', 'receso@fixture.test', 'propietario', true);
insert into public.miembros (id, iglesia_id, nombre, apellido, email, telefono, tipo, nivel_compromiso) values
  ('f5000000-0000-0000-0000-000000000004', 'f2000000-0000-0000-0000-000000000003', 'Alias1', '', null, '+34600555666', 'miembro', 'activo'),
  ('f5000000-0000-0000-0000-000000000005', 'f2000000-0000-0000-0000-000000000004', 'Reco', 'Uno', 'reco@fixture.test', null, 'miembro', 'activo'),
  ('f5000000-0000-0000-0000-000000000006', 'f2000000-0000-0000-0000-000000000004', 'Reco', 'Dos', 'reco2@fixture.test', '+34600777888', 'miembro', 'activo');

-- Como casa-reino del real: iglesia REAL (no demostración) con la dirección que la siembra usaba por defecto
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, es_demo, etapa) values ('f2000000-0000-0000-0000-000000000005', 'Casa Reino fixture', 'casa-reino', 'ES', 'Sevilla', 'premium', false, 'activa');
