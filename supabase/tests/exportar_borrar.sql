-- Pruebas de la exportacion y el borrado completo de una iglesia.
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
grant execute on function pg_temp.igual(text, text, text) to authenticated;

insert into auth.users (id) values
  ('ee000000-0000-0000-0000-000000000001'), ('ee000000-0000-0000-0000-000000000002'),
  ('ee000000-0000-0000-0000-000000000003'), ('ee000000-0000-0000-0000-000000000004');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ee100000-0000-0000-0000-00000000000a', 'Prueba Borrar', 'prueba-borrar', 'ES', 'Sevilla', 'premium'),
  ('ee100000-0000-0000-0000-00000000000b', 'Prueba Otra', 'prueba-otra', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('ee000000-0000-0000-0000-000000000001', 'ee100000-0000-0000-0000-00000000000a', 'P1', 'B', 'p1@prueba.test', 'propietario', true),
  ('ee000000-0000-0000-0000-000000000002', 'ee100000-0000-0000-0000-00000000000a', 'P2', 'B', 'p2@prueba.test', 'propietario', true),
  ('ee000000-0000-0000-0000-000000000003', 'ee100000-0000-0000-0000-00000000000a', 'Adm', 'B', 'adm@prueba.test', 'administrador', true),
  ('ee000000-0000-0000-0000-000000000004', 'ee100000-0000-0000-0000-00000000000b', 'Otra', 'B', 'otra@prueba.test', 'propietario', true);
-- El tercer usuario de la iglesia a borrar tambien es administrador de plataforma
insert into public.plataforma_admins (user_id) values ('ee000000-0000-0000-0000-000000000003');
insert into public.miembros (iglesia_id, nombre, apellido) values
  ('ee100000-0000-0000-0000-00000000000a', 'M', 'Borrar'), ('ee100000-0000-0000-0000-00000000000b', 'M', 'Otra');
insert into public.invitaciones (iglesia_id, email, nombre, apellido, rol, token_hash) values
  ('ee100000-0000-0000-0000-00000000000a', 'i@prueba.test', 'I', 'B', 'colaborador', 'abababababababababababababababababababababababababababababababab');
insert into public.plataforma_auditoria (actor, accion, iglesia_id, detalle) values
  (null, 'crear_iglesia', 'ee100000-0000-0000-0000-00000000000a', '{"propietario": "p1@prueba.test"}');

-- Exportacion
create temp table exp as select public.exportar_iglesia('ee100000-0000-0000-0000-00000000000a') j;
select pg_temp.igual((select j->>'formato' from exp), 'viveadn-exportacion-1', 'la exportacion declara su formato');
select pg_temp.igual((select jsonb_array_length(j->'tablas'->'miembros')::text from exp), '1', 'exporta solo los miembros de esa iglesia');
select pg_temp.igual((select jsonb_array_length(j->'tablas'->'perfiles')::text from exp), '3', 'exporta los perfiles de esa iglesia');
select pg_temp.igual(
  (select count(*)::text from exp, jsonb_array_elements(j->'tablas'->'invitaciones') i where i ? 'token_hash'), '0',
  'la exportacion no incluye el hash del token de invitacion');
select pg_temp.igual((select (j::text like '%abababababababababababababababababababababababababababababababab%')::text from exp), 'false', 'el secreto no aparece en ninguna parte');
select pg_temp.igual((select (j::text like '%otra@prueba.test%')::text from exp), 'false', 'no se cuela nada de otra iglesia');
-- Cubre todas las tablas con iglesia_id mas rol_permisos
select pg_temp.igual(
  (select string_agg(k, ',' order by k collate "C") from exp, jsonb_object_keys(j->'tablas') k),
  (select string_agg(relname, ',' order by relname collate "C") from (
     select c.relname from pg_class c
     where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
       and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and not a.attisdropped)
     union select 'rol_permisos') t),
  'la exportacion cubre todas las tablas de iglesia');

-- Programar el borrado
do $$ begin
  begin update public.iglesias set borrado_programado_en = now() + interval '30 days' where slug = 'prueba-borrar'; exception when check_violation then return; end;
  raise exception 'FALLO: se programo el borrado de una iglesia activa';
end $$;
update public.iglesias set etapa = 'receso', borrado_programado_en = now() + interval '30 days' where slug = 'prueba-borrar';
select pg_temp.igual((select (borrado_programado_en is not null)::text from public.iglesias where slug = 'prueba-borrar'), 'true', 'en receso se puede programar el borrado');
update public.iglesias set etapa = 'activa' where slug = 'prueba-borrar';
select pg_temp.igual((select (borrado_programado_en is null)::text from public.iglesias where slug = 'prueba-borrar'), 'true', 'volver a activa cancela el borrado programado');

-- Quien configura la iglesia no puede programar ni cancelar su borrado
update public.iglesias set etapa = 'receso', borrado_programado_en = now() + interval '30 days' where slug = 'prueba-borrar';
select set_config('request.jwt.claim.sub', 'ee000000-0000-0000-0000-000000000001', true);
set local role authenticated;
do $$ begin
  begin update public.iglesias set borrado_programado_en = null where slug = 'prueba-borrar'; exception when others then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select (borrado_programado_en is not null)::text from public.iglesias where slug = 'prueba-borrar'), 'true', 'el propietario no puede cancelar el borrado');

-- Los permisos: solo service_role
select pg_temp.igual((has_function_privilege('authenticated', 'public.borrar_iglesia(uuid)', 'execute')
  or has_function_privilege('anon', 'public.borrar_iglesia(uuid)', 'execute')
  or has_function_privilege('authenticated', 'public.exportar_iglesia(uuid)', 'execute')
  or has_function_privilege('anon', 'public.exportar_iglesia(uuid)', 'execute'))::text, 'false', 'anon y authenticated no pueden exportar ni borrar');
select pg_temp.igual((has_function_privilege('service_role', 'public.borrar_iglesia(uuid)', 'execute')
  and has_function_privilege('service_role', 'public.exportar_iglesia(uuid)', 'execute'))::text, 'true', 'service_role si puede');

-- Borrado: no antes de plazo
do $$ begin
  begin perform public.borrar_iglesia('ee100000-0000-0000-0000-00000000000a'); exception when check_violation then return; end;
  raise exception 'FALLO: se borro antes de que venciera el plazo';
end $$;
-- Vencido el plazo
update public.iglesias set borrado_programado_en = now() - interval '1 minute' where slug = 'prueba-borrar';
create temp table borrados as select unnest(public.borrar_iglesia('ee100000-0000-0000-0000-00000000000a')) u;
select pg_temp.igual((select count(*)::text from borrados), '2', 'devuelve los usuarios de acceso a borrar de Auth');
select pg_temp.igual((select count(*)::text from borrados where u = 'ee000000-0000-0000-0000-000000000003'), '0', 'respeta al administrador de plataforma');

do $$
declare r record; n int; total int := 0;
begin
  for r in
    select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
      and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and not a.attisdropped)
  loop
    execute format('select count(*) from public.%I where iglesia_id = $1', r.relname) into n using 'ee100000-0000-0000-0000-00000000000a'::uuid;
    if n > 0 and r.relname <> 'plataforma_auditoria' then raise exception 'FALLO: quedan % filas en %', n, r.relname; end if;
    total := total + n;
  end loop;
  if exists (select 1 from public.iglesias where id = 'ee100000-0000-0000-0000-00000000000a') then raise exception 'FALLO: la iglesia sigue existiendo'; end if;
  raise notice 'OK: no queda ninguna fila de la iglesia borrada';
end $$;
select pg_temp.igual((select count(*)::text from public.rol_permisos rp join public.roles r on r.id = rp.rol_id where r.iglesia_id = 'ee100000-0000-0000-0000-00000000000a'), '0', 'no quedan permisos de roles');
select pg_temp.igual((select count(*)::text from public.plataforma_auditoria where detalle::text like '%p1@prueba.test%'), '0', 'la auditoria no conserva el correo del propietario');
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = 'ee100000-0000-0000-0000-00000000000b'), '1', 'la otra iglesia queda intacta');
select pg_temp.igual((select count(*)::text from public.perfiles where iglesia_id = 'ee100000-0000-0000-0000-00000000000b'), '1', 'los perfiles de la otra iglesia siguen');
rollback;
