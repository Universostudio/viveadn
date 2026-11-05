-- Motor de formacion: finalizacion calculada, nadie la fija a mano, aislamiento entre iglesias y permisos.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if exists (select 1 from public.iglesias where slug not like 'prueba-%') then
    raise exception 'Este script no se ejecuta en una base con iglesias reales';
  end if;
end $$;
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
-- Ejecuta una sentencia y dice si funciono (true) o se rechazo (false)
create or replace function pg_temp.funciona(q text) returns boolean language plpgsql as $$
begin execute q; return true; exception when others then return false; end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.funciona(text) to authenticated, anon;

insert into auth.users (id) values
  ('0f000000-0000-0000-0000-000000000001'), ('0f000000-0000-0000-0000-000000000002'), ('0f000000-0000-0000-0000-000000000003');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('0f100000-0000-0000-0000-00000000000a', 'Prueba Formacion A', 'prueba-formacion-a', 'ES', 'Sevilla', 'premium'),
  ('0f100000-0000-0000-0000-00000000000b', 'Prueba Formacion B', 'prueba-formacion-b', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('0f000000-0000-0000-0000-000000000001', '0f100000-0000-0000-0000-00000000000a', 'Pro', 'A', 'p@fa.test', 'propietario', true),
  ('0f000000-0000-0000-0000-000000000002', '0f100000-0000-0000-0000-00000000000a', 'Colab', 'A', 'c@fa.test', 'colaborador', true),
  ('0f000000-0000-0000-0000-000000000003', '0f100000-0000-0000-0000-00000000000b', 'Pro', 'B', 'p@fb.test', 'propietario', true);
insert into public.miembros (id, iglesia_id, nombre, apellido) values
  ('3f000000-0000-0000-0000-000000000001', '0f100000-0000-0000-0000-00000000000a', 'Alumno', 'Uno'),
  ('3f000000-0000-0000-0000-000000000002', '0f100000-0000-0000-0000-00000000000a', 'Alumno', 'Dos'),
  ('3f000000-0000-0000-0000-000000000009', '0f100000-0000-0000-0000-00000000000b', 'Ajeno', 'B');
insert into public.programas_formacion (id, iglesia_id, nombre) values
  ('5f000000-0000-0000-0000-000000000001', '0f100000-0000-0000-0000-00000000000a', 'Bases'),
  ('5f000000-0000-0000-0000-000000000002', '0f100000-0000-0000-0000-00000000000a', 'Otro programa'),
  ('5f000000-0000-0000-0000-000000000003', '0f100000-0000-0000-0000-00000000000a', 'Vacio'),
  ('5f000000-0000-0000-0000-000000000009', '0f100000-0000-0000-0000-00000000000b', 'Programa B');
insert into public.programa_lecciones (id, iglesia_id, programa_id, orden, titulo) values
  ('6f000000-0000-0000-0000-000000000001', '0f100000-0000-0000-0000-00000000000a', '5f000000-0000-0000-0000-000000000001', 1, 'L1'),
  ('6f000000-0000-0000-0000-000000000002', '0f100000-0000-0000-0000-00000000000a', '5f000000-0000-0000-0000-000000000001', 2, 'L2'),
  ('6f000000-0000-0000-0000-000000000003', '0f100000-0000-0000-0000-00000000000a', '5f000000-0000-0000-0000-000000000001', 3, 'L3'),
  ('6f000000-0000-0000-0000-000000000004', '0f100000-0000-0000-0000-00000000000a', '5f000000-0000-0000-0000-000000000002', 1, 'Leccion de otro programa'),
  ('6f000000-0000-0000-0000-000000000009', '0f100000-0000-0000-0000-00000000000b', '5f000000-0000-0000-0000-000000000009', 1, 'LB');

-- Los roles de sistema reciben el permiso nuevo
select pg_temp.igual((select string_agg(r.clave, ',' order by r.clave) from public.roles r join public.rol_permisos rp on rp.rol_id = r.id
  where r.iglesia_id = '0f100000-0000-0000-0000-00000000000a' and rp.permiso = 'formacion.programas'), 'administrador,coadministrador,lider_escuela', 'administrador, coadministrador y lider de escuela editan programas');

-- Propietario de A
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into public.inscripciones_formacion (id, programa_id, miembro_id) values ('7f000000-0000-0000-0000-000000000001', '5f000000-0000-0000-0000-000000000001', '3f000000-0000-0000-0000-000000000001');
select pg_temp.igual((select estado from public.inscripciones_formacion where id = '7f000000-0000-0000-0000-000000000001'), 'en_curso', 'una inscripcion nace en curso');
insert into public.avance_formacion (programa_id, inscripcion_id, leccion_id) values
  ('5f000000-0000-0000-0000-000000000001', '7f000000-0000-0000-0000-000000000001', '6f000000-0000-0000-0000-000000000001'),
  ('5f000000-0000-0000-0000-000000000001', '7f000000-0000-0000-0000-000000000001', '6f000000-0000-0000-0000-000000000002');
select pg_temp.igual((select estado from public.inscripciones_formacion where id = '7f000000-0000-0000-0000-000000000001'), 'en_curso', 'con dos de tres lecciones sigue en curso');
insert into public.avance_formacion (programa_id, inscripcion_id, leccion_id) values ('5f000000-0000-0000-0000-000000000001', '7f000000-0000-0000-0000-000000000001', '6f000000-0000-0000-0000-000000000003');
select pg_temp.igual((select estado || '|' || (completado_en is not null)::text from public.inscripciones_formacion where id = '7f000000-0000-0000-0000-000000000001'), 'completado|true', 'al terminar la ultima leccion se completa y queda la fecha');
-- Quitar un avance reabre
delete from public.avance_formacion where leccion_id = '6f000000-0000-0000-0000-000000000003';
select pg_temp.igual((select estado || '|' || (completado_en is null)::text from public.inscripciones_formacion where id = '7f000000-0000-0000-0000-000000000001'), 'en_curso|true', 'quitar un avance la reabre y limpia la fecha');
insert into public.avance_formacion (programa_id, inscripcion_id, leccion_id) values ('5f000000-0000-0000-0000-000000000001', '7f000000-0000-0000-0000-000000000001', '6f000000-0000-0000-0000-000000000003');
-- Añadir una leccion al programa reabre a quien ya habia terminado
insert into public.programa_lecciones (id, programa_id, orden, titulo) values ('6f000000-0000-0000-0000-000000000005', '5f000000-0000-0000-0000-000000000001', 4, 'L4');
select pg_temp.igual((select estado from public.inscripciones_formacion where id = '7f000000-0000-0000-0000-000000000001'), 'en_curso', 'añadir una leccion reabre las inscripciones completadas');
delete from public.programa_lecciones where id = '6f000000-0000-0000-0000-000000000005';
select pg_temp.igual((select estado from public.inscripciones_formacion where id = '7f000000-0000-0000-0000-000000000001'), 'completado', 'quitarla vuelve a completarlas');

-- Nadie fija la finalizacion a mano
select pg_temp.igual(pg_temp.funciona($q$ insert into public.inscripciones_formacion (programa_id, miembro_id, estado, completado_en) values ('5f000000-0000-0000-0000-000000000002', '3f000000-0000-0000-0000-000000000002', 'completado', now()) $q$)::text, 'true', 'inscribir con estado completado no falla...');
select pg_temp.igual((select estado || '|' || (completado_en is null)::text from public.inscripciones_formacion where programa_id = '5f000000-0000-0000-0000-000000000002'), 'en_curso|true', '...pero queda en curso y sin fecha');
select pg_temp.igual(pg_temp.funciona($q$ update public.inscripciones_formacion set estado = 'completado' where programa_id = '5f000000-0000-0000-0000-000000000002' $q$)::text, 'false', 'no se puede marcar completado a mano');
select pg_temp.igual(pg_temp.funciona($q$ update public.inscripciones_formacion set completado_en = now() where programa_id = '5f000000-0000-0000-0000-000000000002' $q$)::text, 'false', 'no se puede poner una fecha de finalizacion a mano');
select pg_temp.igual(pg_temp.funciona($q$ update public.inscripciones_formacion set completado_en = null where id = '7f000000-0000-0000-0000-000000000001' $q$)::text, 'false', 'no se puede borrar la fecha de una finalizacion real');
select pg_temp.igual(pg_temp.funciona($q$ update public.inscripciones_formacion set estado = 'en_curso' where id = '7f000000-0000-0000-0000-000000000001' $q$)::text, 'false', 'no se puede descompletar a mano');
select pg_temp.igual(pg_temp.funciona($q$ update public.inscripciones_formacion set estado = 'abandonado' where programa_id = '5f000000-0000-0000-0000-000000000002' $q$)::text, 'true', 'abandonar si se puede');

-- Coherencia: el avance solo vale para lecciones del mismo programa y de la misma iglesia
select pg_temp.igual(pg_temp.funciona($q$ insert into public.avance_formacion (programa_id, inscripcion_id, leccion_id) values ('5f000000-0000-0000-0000-000000000001', '7f000000-0000-0000-0000-000000000001', '6f000000-0000-0000-0000-000000000004') $q$)::text, 'false', 'no se avanza con una leccion de otro programa');
select pg_temp.igual(pg_temp.funciona($q$ insert into public.inscripciones_formacion (programa_id, miembro_id) values ('5f000000-0000-0000-0000-000000000001', '3f000000-0000-0000-0000-000000000009') $q$)::text, 'false', 'no se inscribe a un miembro de otra iglesia');
select pg_temp.igual(pg_temp.funciona($q$ insert into public.programa_lecciones (programa_id, orden, titulo) values ('5f000000-0000-0000-0000-000000000009', 1, 'Colada') $q$)::text, 'false', 'no se añaden lecciones a un programa de otra iglesia');
select pg_temp.igual((select count(*)::text from public.programas_formacion), '3', 'solo ve los programas de su iglesia');
-- Un programa sin lecciones nunca se completa
insert into public.inscripciones_formacion (id, programa_id, miembro_id) values ('7f000000-0000-0000-0000-000000000003', '5f000000-0000-0000-0000-000000000003', '3f000000-0000-0000-0000-000000000001');
select pg_temp.igual((select estado from public.inscripciones_formacion where id = '7f000000-0000-0000-0000-000000000003'), 'en_curso', 'un programa sin lecciones no se completa');
-- Borrar un programa se lleva sus lecciones, inscripciones y avances
delete from public.programas_formacion where id = '5f000000-0000-0000-0000-000000000001';
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select (select count(*) from public.programa_lecciones where programa_id = '5f000000-0000-0000-0000-000000000001')
  + (select count(*) from public.inscripciones_formacion where programa_id = '5f000000-0000-0000-0000-000000000001')
  + (select count(*) from public.avance_formacion where programa_id = '5f000000-0000-0000-0000-000000000001'))::text, '0', 'borrar un programa borra lecciones, inscripciones y avances');

-- Colaborador: sin permisos de formacion
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.programas_formacion), '0', 'un colaborador sin formacion.ver no ve programas');
select pg_temp.igual(pg_temp.funciona($q$ insert into public.programas_formacion (nombre) values ('No') $q$)::text, 'false', 'ni crea programas');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Propietario de B: no ve nada de A
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.programas_formacion), '1', 'otra iglesia solo ve su programa');
select pg_temp.igual((select count(*)::text from public.inscripciones_formacion), '0', 'ni las inscripciones de A');
select pg_temp.igual(pg_temp.funciona($q$ insert into public.inscripciones_formacion (programa_id, miembro_id) values ('5f000000-0000-0000-0000-000000000002', '3f000000-0000-0000-0000-000000000009') $q$)::text, 'false', 'ni inscribe en un programa de A');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Anonimo: nada
set local role anon;
select pg_temp.igual(pg_temp.funciona('select 1 from public.programas_formacion limit 1')::text, 'false', 'un anonimo no lee programas');
reset role;
rollback;
