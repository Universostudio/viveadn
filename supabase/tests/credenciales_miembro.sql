-- Credenciales QR de miembros: se emiten solo por funcion, el token no es legible sin permiso y el escaneo marca asistencia con las mismas reglas que marcar a mano.
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
create or replace function pg_temp.codigo(q text) returns text language plpgsql as $$
begin execute q; return 'ok'; exception when others then return sqlstate; end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.codigo(text) to authenticated, anon;

insert into auth.users (id) values
  ('0d000000-0000-0000-0000-000000000001'), ('0d000000-0000-0000-0000-000000000002'), ('0d000000-0000-0000-0000-000000000003'), ('0d000000-0000-0000-0000-000000000004'), ('0d000000-0000-0000-0000-000000000005');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('0d100000-0000-0000-0000-00000000000a', 'Iglesia Prueba A', 'prueba-cred-a', 'ES', 'Sevilla', 'premium'),
  ('0d100000-0000-0000-0000-00000000000b', 'Iglesia Prueba B', 'prueba-cred-b', 'ES', 'Sevilla', 'premium'),
  ('0d100000-0000-0000-0000-00000000000c', 'Iglesia Basico', 'prueba-cred-c', 'ES', 'Sevilla', 'basico');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('0d000000-0000-0000-0000-000000000001', '0d100000-0000-0000-0000-00000000000a', 'Pro', 'A', 'p@da.test', 'propietario', true),
  ('0d000000-0000-0000-0000-000000000002', '0d100000-0000-0000-0000-00000000000a', 'Lid', 'A', 'l@da.test', 'lider_casa', true),
  ('0d000000-0000-0000-0000-000000000003', '0d100000-0000-0000-0000-00000000000a', 'Mie', 'A', 'm@da.test', 'miembro', true),
  ('0d000000-0000-0000-0000-000000000004', '0d100000-0000-0000-0000-00000000000b', 'Pro', 'B', 'p@db.test', 'propietario', true),
  ('0d000000-0000-0000-0000-000000000005', '0d100000-0000-0000-0000-00000000000c', 'Pro', 'C', 'p@dc.test', 'propietario', true);
insert into public.casas_oracion (id, iglesia_id, codigo_zona, nombre, lider_id, pais, ciudad, direccion) values
  ('2d000000-0000-0000-0000-00000000000a', '0d100000-0000-0000-0000-00000000000a', 'ZN', 'Casa propia', '0d000000-0000-0000-0000-000000000002', 'ES', 'Sevilla', 'C1'),
  ('2d000000-0000-0000-0000-0000000000a2', '0d100000-0000-0000-0000-00000000000a', 'ZS', 'Casa ajena', null, 'ES', 'Sevilla', 'C2');
insert into public.miembros (id, iglesia_id, nombre, apellido, casa_oracion_id) values
  ('3d000000-0000-0000-0000-0000000000a1', '0d100000-0000-0000-0000-00000000000a', 'Ana', 'Gil', '2d000000-0000-0000-0000-00000000000a'),
  ('3d000000-0000-0000-0000-0000000000a2', '0d100000-0000-0000-0000-00000000000a', 'Luis', 'Perez', '2d000000-0000-0000-0000-0000000000a2'),
  ('3d000000-0000-0000-0000-0000000000a3', '0d100000-0000-0000-0000-00000000000a', 'Sin', 'Casa', null),
  ('3d000000-0000-0000-0000-0000000000b1', '0d100000-0000-0000-0000-00000000000b', 'DeB', 'B', null),
  ('3d000000-0000-0000-0000-0000000000c1', '0d100000-0000-0000-0000-00000000000c', 'DeC', 'C', null);
update public.miembros set activo = true where iglesia_id in ('0d100000-0000-0000-0000-00000000000a', '0d100000-0000-0000-0000-00000000000b');
insert into public.miembros (id, iglesia_id, nombre, apellido, activo) values
  ('3d000000-0000-0000-0000-0000000000a4', '0d100000-0000-0000-0000-00000000000a', 'Baja', 'Inactiva', false);
insert into public.eventos (id, iglesia_id, titulo, tipo, inicia_en, casa_oracion_id, cancelado) values
  ('4d000000-0000-0000-0000-000000000001', '0d100000-0000-0000-0000-00000000000a', 'Culto general', 'culto', now(), null, false),
  ('4d000000-0000-0000-0000-000000000002', '0d100000-0000-0000-0000-00000000000a', 'Casa propia', 'casa_oracion', now(), '2d000000-0000-0000-0000-00000000000a', false),
  ('4d000000-0000-0000-0000-000000000003', '0d100000-0000-0000-0000-00000000000a', 'Cancelado', 'culto', now(), null, true),
  ('4d000000-0000-0000-0000-00000000000b', '0d100000-0000-0000-0000-00000000000b', 'Culto de B', 'culto', now(), null, false),
  ('4d000000-0000-0000-0000-00000000000c', '0d100000-0000-0000-0000-00000000000c', 'Culto de C', 'culto', now(), null, false);

select pg_temp.igual((select string_agg(r.clave, ',' order by r.clave) from public.roles r join public.rol_permisos rp on rp.rol_id = r.id
  where r.iglesia_id = '0d100000-0000-0000-0000-00000000000a' and rp.permiso = 'credenciales.gestionar'), 'administrador,coadministrador', 'los roles de sistema reciben el permiso de credencial');

-- Una iglesia sin el modulo de credenciales (plan basico) no emite ni escanea; con el complemento si
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select pg_temp.igual(pg_temp.codigo($q$ select public.emitir_credencial('3d000000-0000-0000-0000-0000000000c1') $q$), '42501', 'sin el modulo de credenciales no se emite');
select pg_temp.igual(pg_temp.codigo($q$ select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-00000000000c', repeat('0', 32)) $q$), '42501', 'ni se escanea, aunque se tenga permiso de asistencia');
reset role;
insert into public.iglesia_modulos (iglesia_id, modulo) values ('0d100000-0000-0000-0000-00000000000c', 'credenciales');
set local role authenticated;
select pg_temp.igual(pg_temp.codigo($q$ select public.emitir_credencial('3d000000-0000-0000-0000-0000000000c1') $q$), 'ok', 'con el complemento contratado ya se emite');
reset role;
delete from public.iglesia_modulos where iglesia_id = '0d100000-0000-0000-0000-00000000000c' and modulo = 'credenciales';
set local role authenticated;
select pg_temp.igual(pg_temp.codigo($q$ select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-00000000000c', repeat('0', 32)) $q$), '42501', 'al quitar el complemento deja de escanear');
reset role;

-- Credencial de B (la usara A mas tarde para comprobar que no vale fuera de su iglesia)
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000004', true);
set local role authenticated;
create temp table cred_b as select public.emitir_credencial('3d000000-0000-0000-0000-0000000000b1') id;
grant select on cred_b to authenticated;
reset role;
create temp table tok_b as select token from public.credenciales_miembro where miembro_id = '3d000000-0000-0000-0000-0000000000b1';
grant select on tok_b to authenticated;

-- Quien no tiene permiso: ni emite ni lee
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual(pg_temp.codigo($q$ select public.emitir_credencial('3d000000-0000-0000-0000-0000000000a1') $q$), '42501', 'sin permiso no se emite la credencial');
select pg_temp.igual((select count(*)::text from public.credenciales_miembro), '0', 'sin permiso no se leen credenciales');
select pg_temp.igual(pg_temp.codigo($q$ select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', (select token from tok_b)) $q$), '42501', 'sin permiso no se escanea');
reset role;

-- Propietario de A emite
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual(pg_temp.codigo($q$ select public.emitir_credencial('3d000000-0000-0000-0000-0000000000b1') $q$), 'P0002', 'no se emite para un miembro de otra iglesia');
select pg_temp.igual(pg_temp.codigo($q$ select public.emitir_credencial('3d000000-0000-0000-0000-0000000000a4') $q$), 'P0002', 'ni para un miembro inactivo');
create temp table cred_a as select public.emitir_credencial('3d000000-0000-0000-0000-0000000000a1') id;
grant select on cred_a to authenticated;
select pg_temp.igual((select (public.emitir_credencial('3d000000-0000-0000-0000-0000000000a1') = (select id from cred_a))::text), 'true', 'emitir dos veces devuelve la misma credencial');
select pg_temp.igual((select (token ~ '^[0-9a-f]{32}$')::text from public.credenciales_miembro where id = (select id from cred_a)), 'true', 'el token son 32 caracteres hexadecimales');
select pg_temp.igual((select count(*)::text from public.credenciales_miembro), '1', 'solo ve las credenciales de su iglesia');
select pg_temp.igual(pg_temp.codigo($q$ insert into public.credenciales_miembro (miembro_id) values ('3d000000-0000-0000-0000-0000000000a2') $q$), '42501', 'no se inserta a mano');
select pg_temp.igual(pg_temp.codigo($q$ update public.credenciales_miembro set token = repeat('a', 32) $q$), '42501', 'no se edita a mano');
select pg_temp.igual(pg_temp.codigo($q$ delete from public.credenciales_miembro $q$), '42501', 'no se borra a mano');
create temp table otras as select public.emitir_credencial('3d000000-0000-0000-0000-0000000000a2') id, public.emitir_credencial('3d000000-0000-0000-0000-0000000000a3') id2;
reset role;
create temp table tok_a as select token from public.credenciales_miembro where miembro_id = '3d000000-0000-0000-0000-0000000000a1';
create temp table tok_a2 as select token from public.credenciales_miembro where miembro_id = '3d000000-0000-0000-0000-0000000000a2';
grant select on tok_a, tok_a2 to authenticated;

-- Escaneo por el propietario
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', (select token from tok_a)) ->> 'estado'), 'registrado', 'escanear marca la asistencia');
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', (select token from tok_a)) ->> 'nombre'), 'Ana Gil', 'responde con el nombre para confirmarlo');
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', (select token from tok_a)) ->> 'estado'), 'ya_registrado', 'escanear otra vez no duplica');
select pg_temp.igual((select count(*)::text from public.asistencia_evento where evento_id = '4d000000-0000-0000-0000-000000000001'), '1', 'queda una sola fila de asistencia');
update public.asistencia_evento set presente = false where evento_id = '4d000000-0000-0000-0000-000000000001';
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', (select token from tok_a)) ->> 'estado'), 'registrado', 'escanear tras desmarcar vuelve a marcar');
select pg_temp.igual((select presente::text from public.asistencia_evento where evento_id = '4d000000-0000-0000-0000-000000000001'), 'true', 'y queda presente');
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', repeat('0', 32)) ->> 'estado'), 'desconocida', 'un token que no existe es desconocido');
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', 'no-es-un-token') ->> 'estado'), 'desconocida', 'un texto que no es un token es desconocido');
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', (select token from tok_b)) ->> 'estado'), 'desconocida', 'la credencial de otra iglesia no vale');
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000003', (select token from tok_a)) ->> 'estado'), 'cancelado', 'un evento cancelado no registra');
select pg_temp.igual(pg_temp.codigo($q$ select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-00000000000b', (select token from tok_a)) $q$), 'P0002', 'no se escanea en un evento de otra iglesia');
reset role;

-- Quien lidera una casa: solo en su casa y solo con miembros de su casa
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000002', (select token from tok_a)) ->> 'estado'), 'registrado', 'el lider de casa escanea a un miembro de su casa');
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000002', (select token from tok_a2)) ->> 'estado'), 'fuera_de_casa', 'pero no a uno de otra casa');
select pg_temp.igual((select (public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000002', (select token from tok_a2))) ? 'nombre')::text, 'false', 'sin revelar su nombre');
select pg_temp.igual(pg_temp.codigo($q$ select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', (select token from tok_a)) $q$), '42501', 'ni en un evento que no es de su casa');
select pg_temp.igual((select count(*)::text from public.credenciales_miembro), '0', 'el lider de casa no lee los tokens');
reset role;

-- Renovar y retirar
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select (public.emitir_credencial('3d000000-0000-0000-0000-0000000000a1', true) = (select id from cred_a))::text), 'true', 'renovar conserva la fila');
reset role;
select pg_temp.igual((select (token <> (select token from tok_a))::text from public.credenciales_miembro where miembro_id = '3d000000-0000-0000-0000-0000000000a1'), 'true', 'pero cambia el token');
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', (select token from tok_a)) ->> 'estado'), 'desconocida', 'el token anterior deja de valer');
select public.retirar_credencial('3d000000-0000-0000-0000-0000000000a2');
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', (select token from tok_a2)) ->> 'estado'), 'desconocida', 'una credencial retirada deja de valer');
reset role;
-- Un miembro que pasa a inactivo ya no registra
update public.miembros set activo = false where id = '3d000000-0000-0000-0000-0000000000a3';
select set_config('request.jwt.claim.sub', '0d000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select public.registrar_asistencia_credencial('4d000000-0000-0000-0000-000000000001', (select token from public.credenciales_miembro where miembro_id = '3d000000-0000-0000-0000-0000000000a3')) ->> 'estado'), 'inactivo', 'un miembro inactivo no registra');
reset role;
select set_config('request.jwt.claim.sub', '', true);
-- La exportacion de la iglesia incluye la tabla pero nunca el token
select pg_temp.igual((public.exportar_iglesia('0d100000-0000-0000-0000-00000000000a')::text like '%credenciales_miembro%')::text, 'true', 'la exportacion incluye las credenciales');
select pg_temp.igual((public.exportar_iglesia('0d100000-0000-0000-0000-00000000000a')::text like '%' || (select token from public.credenciales_miembro where miembro_id = '3d000000-0000-0000-0000-0000000000a3') || '%')::text, 'false', 'pero no su token');
-- Permisos de las funciones y cascada
select pg_temp.igual((has_function_privilege('anon', 'public.emitir_credencial(uuid, boolean)', 'execute') or has_function_privilege('anon', 'public.retirar_credencial(uuid)', 'execute')
  or has_function_privilege('anon', 'public.registrar_asistencia_credencial(uuid, text)', 'execute'))::text, 'false', 'anon no ejecuta ninguna');
delete from public.miembros where id = '3d000000-0000-0000-0000-0000000000a1';
select pg_temp.igual((select count(*)::text from public.credenciales_miembro where miembro_id = '3d000000-0000-0000-0000-0000000000a1'), '0', 'borrar al miembro borra su credencial');
rollback;
