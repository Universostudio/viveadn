-- Pruebas del ciclo de vida de la iglesia (etapa <-> activa, prueba vencida).
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
insert into auth.users (id) values ('cc000000-0000-0000-0000-000000000001');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, etapa) values
  ('cc100000-0000-0000-0000-00000000000a', 'Prueba V', 'prueba-v', 'ES', 'Sevilla', 'basico', 'onboarding');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('cc000000-0000-0000-0000-000000000001', 'cc100000-0000-0000-0000-00000000000a', 'P', 'V', 'p@prueba.test', 'propietario', true);

select pg_temp.igual((select activa::text from public.iglesias where slug = 'prueba-v'), 'true', 'onboarding esta operativa');
update public.iglesias set etapa = 'prueba' where slug = 'prueba-v';
select pg_temp.igual((select (prueba_hasta > now() + interval '29 days')::text from public.iglesias where slug = 'prueba-v'), 'true', 'la prueba nace con 30 dias');

select set_config('request.jwt.claim.sub', 'cc000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select private.tiene_modulo('miembros')::text), 'true', 'prueba vigente da modulos');
reset role;
select set_config('request.jwt.claim.sub', '', true);

update public.iglesias set prueba_hasta = now() - interval '1 day' where slug = 'prueba-v';
select set_config('request.jwt.claim.sub', 'cc000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select private.tiene_modulo('miembros')::text), 'false', 'prueba vencida corta los modulos');
reset role;
select set_config('request.jwt.claim.sub', '', true);

update public.iglesias set etapa = 'receso' where slug = 'prueba-v';
select pg_temp.igual((select activa::text from public.iglesias where slug = 'prueba-v'), 'false', 'receso desactiva');
select pg_temp.igual((select prueba_hasta::text from public.iglesias where slug = 'prueba-v'), null, 'fuera de prueba no hay fecha de prueba');
select pg_temp.igual((select count(*)::text from public.perfiles where iglesia_id = 'cc100000-0000-0000-0000-00000000000a'), '1', 'receso conserva los datos');

update public.iglesias set activa = true where slug = 'prueba-v';
select pg_temp.igual((select etapa from public.iglesias where slug = 'prueba-v'), 'activa', 'cambiar solo activa a true deja la etapa activa');
update public.iglesias set activa = false where slug = 'prueba-v';
select pg_temp.igual((select etapa from public.iglesias where slug = 'prueba-v'), 'suspendida', 'cambiar solo activa a false suspende');

do $$ begin
  begin update public.iglesias set etapa = 'otra' where slug = 'prueba-v'; exception when check_violation then return; end;
  raise exception 'FALLO: una etapa invalida debia rechazarse';
end $$;
rollback;
