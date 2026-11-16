-- Prueba vencida: el núcleo queda en solo lectura. Lo de pago se corta, escribir se corta, y una prueba vigente o un receso no cambian.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if exists (select 1 from public.iglesias where slug not like 'prueba-%') then raise exception 'Este script no se ejecuta en una base con iglesias reales'; end if;
end $$;
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text) to authenticated;
insert into auth.users (id) values ('b3a00000-0000-0000-0000-000000000001');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, etapa) values ('b3a10000-0000-0000-0000-00000000000a', 'Prueba Lectura', 'prueba-lectura', 'ES', 'Sevilla', 'basico', 'prueba');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values ('b3a00000-0000-0000-0000-000000000001', 'b3a10000-0000-0000-0000-00000000000a', 'P', 'L', 'p@lectura.test', 'propietario', true);
insert into public.miembros (id, iglesia_id, nombre, apellido) values ('b3a30000-0000-0000-0000-000000000001', 'b3a10000-0000-0000-0000-00000000000a', 'M', 'Uno');

create or replace function pg_temp.permisos() returns text language sql as $$
  select concat_ws(',', (private.tiene_permiso('miembros.ver'))::text, (private.tiene_permiso('miembros.crear'))::text, (private.tiene_permiso('miembros.exportar'))::text,
                   (private.tiene_permiso('iglesia.configurar'))::text, (private.tiene_permiso('reportes.ver'))::text, (private.tiene_permiso('zonas.ver'))::text, (private.tiene_permiso('zonas.gestionar'))::text)
$$;
grant execute on function pg_temp.permisos() to authenticated;
-- Prueba vigente: todo lo del plan
select set_config('request.jwt.claim.sub', 'b3a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual(pg_temp.permisos(), 'true,true,true,true,true,true,true', 'prueba vigente: todo el plan');
reset role;
select set_config('request.jwt.claim.sub', '', true);
-- Prueba vencida: solo lectura del núcleo
update public.iglesias set prueba_hasta = now() - interval '1 day' where slug = 'prueba-lectura';
select set_config('request.jwt.claim.sub', 'b3a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual(pg_temp.permisos(), 'true,false,true,false,false,true,false', 'prueba vencida: ver y exportar del núcleo sí; crear, configurar, lo incluido y gestionar no');
select pg_temp.igual((select count(*)::text from public.miembros), '1', 'prueba vencida: se siguen leyendo las personas');
do $$ begin
  begin insert into public.miembros (iglesia_id, nombre, apellido) values ('b3a10000-0000-0000-0000-00000000000a', 'No', 'Debe'); exception when others then raise notice 'OK: prueba vencida: no se puede crear una persona (%)', sqlstate; return; end;
  raise exception 'FALLO: con la prueba vencida se pudo crear una persona';
end $$;
select pg_temp.igual((select private.tiene_modulo('miembros')::text), 'false', 'tiene_modulo sigue cortando con la prueba vencida (no cambia)');
reset role;
select set_config('request.jwt.claim.sub', '', true);
-- Un rol sin permiso de lectura sigue sin él
update public.iglesias set prueba_hasta = now() + interval '3 days' where slug = 'prueba-lectura';
-- En receso no hay nada
update public.iglesias set etapa = 'receso' where slug = 'prueba-lectura';
select set_config('request.jwt.claim.sub', 'b3a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual(pg_temp.permisos(), 'false,false,false,false,false,false,false', 'receso: nada');
reset role;
select set_config('request.jwt.claim.sub', '', true);
-- Una iglesia activa de pago no se ve afectada
update public.iglesias set etapa = 'activa' where slug = 'prueba-lectura';
select set_config('request.jwt.claim.sub', 'b3a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual(pg_temp.permisos(), 'true,true,true,true,true,true,true', 'activa: todo el plan');
reset role;
select set_config('request.jwt.claim.sub', '', true);
rollback;
