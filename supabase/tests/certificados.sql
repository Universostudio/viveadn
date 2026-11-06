-- Certificados de formacion: solo se emiten para inscripciones completadas, solo por funcion, y la verificacion publica muestra lo minimo.
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
-- Devuelve el codigo de error de una sentencia ('ok' si funciono)
create or replace function pg_temp.codigo(q text) returns text language plpgsql as $$
begin execute q; return 'ok'; exception when others then return sqlstate; end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.codigo(text) to authenticated, anon;

insert into auth.users (id) values
  ('0c000000-0000-0000-0000-000000000001'), ('0c000000-0000-0000-0000-000000000002'), ('0c000000-0000-0000-0000-000000000003'), ('0c000000-0000-0000-0000-000000000004');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, modo_alias) values
  ('0c100000-0000-0000-0000-00000000000a', 'Iglesia Prueba A', 'prueba-cert-a', 'ES', 'Sevilla', 'premium', false),
  ('0c100000-0000-0000-0000-00000000000b', 'Iglesia Prueba B', 'prueba-cert-b', 'ES', 'Sevilla', 'premium', false),
  ('0c100000-0000-0000-0000-00000000000c', 'Iglesia Alias', 'prueba-cert-c', 'ES', 'Sevilla', 'premium', true);
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('0c000000-0000-0000-0000-000000000001', '0c100000-0000-0000-0000-00000000000a', 'Pro', 'A', 'p@ca.test', 'propietario', true),
  ('0c000000-0000-0000-0000-000000000002', '0c100000-0000-0000-0000-00000000000a', 'Colab', 'A', 'c@ca.test', 'colaborador', true),
  ('0c000000-0000-0000-0000-000000000003', '0c100000-0000-0000-0000-00000000000b', 'Pro', 'B', 'p@cb.test', 'propietario', true),
  ('0c000000-0000-0000-0000-000000000004', '0c100000-0000-0000-0000-00000000000c', 'Pro', 'C', 'p@cc.test', 'propietario', true);
insert into public.miembros (id, iglesia_id, nombre, apellido) values
  ('3c000000-0000-0000-0000-000000000001', '0c100000-0000-0000-0000-00000000000a', 'María José', 'García López'),
  ('3c000000-0000-0000-0000-000000000002', '0c100000-0000-0000-0000-00000000000a', 'Luis', 'Pérez'),
  ('3c000000-0000-0000-0000-000000000003', '0c100000-0000-0000-0000-00000000000c', 'Roble-01', '');
insert into public.programas_formacion (id, iglesia_id, nombre) values
  ('5c000000-0000-0000-0000-000000000001', '0c100000-0000-0000-0000-00000000000a', 'Bases de la fe'),
  ('5c000000-0000-0000-0000-000000000003', '0c100000-0000-0000-0000-00000000000c', 'Programa alias');
insert into public.programa_lecciones (iglesia_id, programa_id, orden, titulo) values
  ('0c100000-0000-0000-0000-00000000000a', '5c000000-0000-0000-0000-000000000001', 1, 'L1'),
  ('0c100000-0000-0000-0000-00000000000c', '5c000000-0000-0000-0000-000000000003', 1, 'L1');
insert into public.inscripciones_formacion (id, iglesia_id, programa_id, miembro_id) values
  ('7c000000-0000-0000-0000-000000000001', '0c100000-0000-0000-0000-00000000000a', '5c000000-0000-0000-0000-000000000001', '3c000000-0000-0000-0000-000000000001'),
  ('7c000000-0000-0000-0000-000000000002', '0c100000-0000-0000-0000-00000000000a', '5c000000-0000-0000-0000-000000000001', '3c000000-0000-0000-0000-000000000002'),
  ('7c000000-0000-0000-0000-000000000003', '0c100000-0000-0000-0000-00000000000c', '5c000000-0000-0000-0000-000000000003', '3c000000-0000-0000-0000-000000000003');
-- Completan la primera y la tercera (todas sus lecciones); la segunda queda en curso
insert into public.avance_formacion (iglesia_id, programa_id, inscripcion_id, leccion_id)
  select l.iglesia_id, l.programa_id, i.id, l.id from public.programa_lecciones l
  join public.inscripciones_formacion i on i.programa_id = l.programa_id
  where i.id in ('7c000000-0000-0000-0000-000000000001', '7c000000-0000-0000-0000-000000000003');

select pg_temp.igual((select string_agg(r.clave, ',' order by r.clave) from public.roles r join public.rol_permisos rp on rp.rol_id = r.id
  where r.iglesia_id = '0c100000-0000-0000-0000-00000000000a' and rp.permiso = 'formacion.certificar'), 'administrador,coadministrador,lider_escuela', 'los roles de sistema reciben el permiso de certificar');

-- Propietario de A
select set_config('request.jwt.claim.sub', '0c000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual(pg_temp.codigo($q$ select public.emitir_certificado('7c000000-0000-0000-0000-000000000002') $q$), '23514', 'no se emite un certificado de una inscripcion en curso');
select pg_temp.igual(pg_temp.codigo($q$ select public.emitir_certificado('7c000000-0000-0000-0000-000000000003') $q$), 'P0002', 'ni de una inscripcion de otra iglesia');
create temp table emitido as select public.emitir_certificado('7c000000-0000-0000-0000-000000000001') id;
grant select on emitido to authenticated;
select pg_temp.igual((select (id is not null)::text from emitido), 'true', 'se emite el certificado de una inscripcion completada');
select pg_temp.igual((select public.emitir_certificado('7c000000-0000-0000-0000-000000000001') = id from emitido)::text, 'true', 'emitir dos veces devuelve el mismo certificado');
select pg_temp.igual((select count(*)::text from public.certificados), '1', 'y no crea otro');
select pg_temp.igual((select titular from public.certificados), 'María José G.', 'el titular es el nombre y la inicial del apellido');
select pg_temp.igual((select (codigo ~ '^[0-9a-f]{32}$')::text from public.certificados), 'true', 'el codigo tiene 32 caracteres hexadecimales');
-- Nada de escribir a mano
select pg_temp.igual(pg_temp.codigo($q$ insert into public.certificados (programa_id, inscripcion_id, miembro_id, titular, programa_nombre) values ('5c000000-0000-0000-0000-000000000001', '7c000000-0000-0000-0000-000000000002', '3c000000-0000-0000-0000-000000000002', 'Falso', 'Bases de la fe') $q$), '42501', 'no se inserta un certificado a mano');
select pg_temp.igual(pg_temp.codigo($q$ update public.certificados set titular = 'Otro' $q$), '42501', 'ni se edita');
select pg_temp.igual(pg_temp.codigo($q$ delete from public.certificados $q$), '42501', 'ni se borra');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Iglesia en modo alias: solo el alias
select set_config('request.jwt.claim.sub', '0c000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select public.emitir_certificado('7c000000-0000-0000-0000-000000000003');
select pg_temp.igual((select titular from public.certificados), 'Roble-01', 'en modo alias el titular es solo el alias');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Colaborador sin permiso, y otra iglesia sin acceso
select set_config('request.jwt.claim.sub', '0c000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual(pg_temp.codigo($q$ select public.emitir_certificado('7c000000-0000-0000-0000-000000000001') $q$), '42501', 'un colaborador sin permiso no emite');
select pg_temp.igual((select count(*)::text from public.certificados), '0', 'ni ve los certificados');
reset role;
select set_config('request.jwt.claim.sub', '0c000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.certificados), '0', 'otra iglesia no ve los certificados de A');
select pg_temp.igual(pg_temp.codigo($q$ select public.emitir_certificado('7c000000-0000-0000-0000-000000000001') $q$), 'P0002', 'ni emite para una inscripcion de A, aunque tenga permiso en la suya');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Verificacion publica (la ejecuta el servidor)
create temp table codigos as select id, codigo from public.certificados where iglesia_id = '0c100000-0000-0000-0000-00000000000a';
select pg_temp.igual((select public.info_certificado(codigo) ->> 'estado' from codigos), 'valido', 'la verificacion de un certificado vigente dice valido');
select pg_temp.igual((select (public.info_certificado(codigo) - 'emitido_en')::text from codigos), '{"estado": "valido", "iglesia": "Iglesia Prueba A", "titular": "María José G.", "programa": "Bases de la fe"}', 'y devuelve solo iglesia, programa, titular reducido y fecha');
select pg_temp.igual(coalesce(public.info_certificado(repeat('0', 32))::text, 'nulo'), 'nulo', 'un codigo desconocido no devuelve nada');
-- Revocar y restaurar
select set_config('request.jwt.claim.sub', '0c000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.revocar_certificado((select id from emitido));
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select public.info_certificado(codigo) ->> 'estado' from codigos), 'revocado', 'un certificado revocado se verifica como revocado');
select pg_temp.igual((select (public.info_certificado(codigo) ? 'titular')::text from codigos), 'false', 'y ya no muestra al titular');
select set_config('request.jwt.claim.sub', '0c000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.revocar_certificado((select id from emitido), false);
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select public.info_certificado(codigo) ->> 'estado' from codigos), 'valido', 'restaurarlo lo deja valido otra vez');
-- Permisos de las funciones
select pg_temp.igual((has_function_privilege('anon', 'public.info_certificado(text)', 'execute') or has_function_privilege('authenticated', 'public.info_certificado(text)', 'execute')
  or has_function_privilege('anon', 'public.emitir_certificado(uuid)', 'execute') or has_function_privilege('anon', 'public.revocar_certificado(uuid, boolean)', 'execute'))::text, 'false', 'anon no ejecuta ninguna y authenticated no verifica');
select pg_temp.igual((has_function_privilege('service_role', 'public.info_certificado(text)', 'execute'))::text, 'true', 'el servidor si verifica');
-- Borrar la inscripcion se lleva su certificado
delete from public.inscripciones_formacion where id = '7c000000-0000-0000-0000-000000000001';
select pg_temp.igual((select count(*)::text from public.certificados where iglesia_id = '0c100000-0000-0000-0000-00000000000a'), '0', 'borrar la inscripcion borra su certificado');
rollback;
