-- Líderes: lo que hace la pantalla de zonas y casas (crear zona, nombrar líderes, asignar casa a cada persona) y lo que ve cada líder después.
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
grant execute on function pg_temp.igual(text, text, text) to authenticated, anon, service_role;
create or replace function pg_temp.falla(sentencia text, msg text) returns void language plpgsql as $$
declare filas bigint;
begin
  begin execute sentencia; get diagnostics filas = row_count;
  exception when others then raise notice 'OK: % (%)', msg, left(sqlerrm, 60); return; end;
  -- Una política de nivel de fila que no deja actuar no da error: no cambia ninguna fila
  if filas = 0 then raise notice 'OK: % (0 filas)', msg; return; end if;
  raise exception 'FALLO: % (se pudo)', msg;
end $$;
grant execute on function pg_temp.falla(text, text) to authenticated, anon, service_role;

insert into auth.users (id) values
  ('a9500000-0000-0000-0000-000000000001'), ('a9500000-0000-0000-0000-000000000002'), ('a9500000-0000-0000-0000-000000000003'),
  ('a9500000-0000-0000-0000-000000000004'), ('a9500000-0000-0000-0000-000000000005'), ('a9500000-0000-0000-0000-0000000000f1');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('a9600000-0000-0000-0000-00000000000a', 'Prueba Lideres A', 'prueba-lideres-a', 'ES', 'Sevilla', 'premium'),
  ('a9600000-0000-0000-0000-00000000000b', 'Prueba Lideres B', 'prueba-lideres-b', 'ES', 'Sevilla', 'premium');
set local session_replication_role = replica;
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('a9500000-0000-0000-0000-000000000001', 'a9600000-0000-0000-0000-00000000000a', 'Adm', 'A', 'adm@lideres-a.test', 'administrador', true),
  ('a9500000-0000-0000-0000-000000000002', 'a9600000-0000-0000-0000-00000000000a', 'Zona', 'A', 'lz@lideres-a.test', 'lider_zona', true),
  ('a9500000-0000-0000-0000-000000000003', 'a9600000-0000-0000-0000-00000000000a', 'Casa', 'Uno', 'lc1@lideres-a.test', 'lider_casa', true),
  ('a9500000-0000-0000-0000-000000000004', 'a9600000-0000-0000-0000-00000000000a', 'Casa', 'Dos', 'lc2@lideres-a.test', 'lider_casa', true),
  ('a9500000-0000-0000-0000-000000000005', 'a9600000-0000-0000-0000-00000000000a', 'Cola', 'Borador', 'col@lideres-a.test', 'colaborador', true),
  ('a9500000-0000-0000-0000-0000000000f1', 'a9600000-0000-0000-0000-00000000000b', 'Otra', 'Iglesia', 'otra@lideres-b.test', 'administrador', true);
reset session_replication_role;

-- 1. El administrador crea la zona, la casa y las personas, y nombra a los líderes
select set_config('request.jwt.claim.sub', 'a9500000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into public.zonas (id, codigo, nombre) values ('a9700000-0000-0000-0000-000000000001', 'NORTE', 'Zona Norte');
select pg_temp.igual((select count(*)::text from public.zonas), '1', 'el administrador crea una zona');
update public.zonas set lider_id = 'a9500000-0000-0000-0000-000000000002' where id = 'a9700000-0000-0000-0000-000000000001';
select pg_temp.igual((select lider_id::text from public.zonas), 'a9500000-0000-0000-0000-000000000002', 'nombra al líder de zona');
insert into public.casas_oracion (id, nombre, codigo_zona, pais, ciudad, direccion) values
  ('a9800000-0000-0000-0000-000000000001', 'Casa Uno', 'ZN', 'ES', 'Sevilla', 'Calle 1'),
  ('a9800000-0000-0000-0000-000000000002', 'Casa Dos', 'ZN', 'ES', 'Sevilla', 'Calle 2');
update public.casas_oracion set zona_id = 'a9700000-0000-0000-0000-000000000001', lider_id = 'a9500000-0000-0000-0000-000000000003' where id = 'a9800000-0000-0000-0000-000000000001';
update public.casas_oracion set lider_id = 'a9500000-0000-0000-0000-000000000004' where id = 'a9800000-0000-0000-0000-000000000002';
select pg_temp.igual((select count(*)::text from public.casas_oracion where zona_id is not null and lider_id is not null), '1', 'la casa 1 queda en la zona y con su líder; la 2 sin zona');
insert into public.miembros (id, nombre, apellido) values
  ('a9900000-0000-0000-0000-000000000001', 'Ana', 'Uno'), ('a9900000-0000-0000-0000-000000000002', 'Beto', 'Dos'), ('a9900000-0000-0000-0000-000000000003', 'Cleo', 'Tres');
update public.miembros set casa_oracion_id = 'a9800000-0000-0000-0000-000000000001' where id in ('a9900000-0000-0000-0000-000000000001', 'a9900000-0000-0000-0000-000000000002');
update public.miembros set casa_oracion_id = 'a9800000-0000-0000-0000-000000000002' where id = 'a9900000-0000-0000-0000-000000000003';
select pg_temp.igual((select count(*)::text from public.miembros where casa_oracion_id = 'a9800000-0000-0000-0000-000000000001'), '2', 'asigna dos personas a la casa 1');
-- Una persona sin casa se puede listar para asignarla
insert into public.miembros (id, nombre, apellido) values ('a9900000-0000-0000-0000-000000000004', 'Dani', 'Sincasa');
select pg_temp.igual((select count(*)::text from public.miembros where casa_oracion_id is null and activo), '1', 'se pueden listar las personas sin casa');
-- No se nombra líder a alguien de otra iglesia
select pg_temp.falla($q$ update public.casas_oracion set lider_id = 'a9500000-0000-0000-0000-0000000000f1' where id = 'a9800000-0000-0000-0000-000000000001' $q$, 'líder de casa de otra iglesia');
select pg_temp.falla($q$ update public.zonas set lider_id = 'a9500000-0000-0000-0000-0000000000f1' where id = 'a9700000-0000-0000-0000-000000000001' $q$, 'líder de zona de otra iglesia');
reset role;

-- 2. El líder de zona ve su zona y nada más, y no administra
select set_config('request.jwt.claim.sub', 'a9500000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select string_agg(nombre, ',') from public.casas_oracion), 'Casa Uno', 'el líder de zona ve solo la casa de su zona');
select pg_temp.igual((select count(*)::text from public.miembros), '2', 'y solo las dos personas de esa casa');
select pg_temp.falla($q$ insert into public.zonas (codigo, nombre) values ('X', 'Zona que no debe crear') $q$, 'el líder de zona crea una zona');
select pg_temp.falla($q$ update public.casas_oracion set lider_id = 'a9500000-0000-0000-0000-000000000004' where id = 'a9800000-0000-0000-0000-000000000001' $q$, 'el líder de zona cambia al líder de una casa');
select pg_temp.falla($q$ update public.miembros set casa_oracion_id = null where id = 'a9900000-0000-0000-0000-000000000001' $q$, 'el líder de zona saca a alguien de su casa');
reset role;

-- 3. Cada líder de casa ve solo su casa y su gente
select set_config('request.jwt.claim.sub', 'a9500000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select string_agg(nombre, ',') from public.casas_oracion), 'Casa Uno', 'el líder de la casa 1 ve su casa');
select pg_temp.igual((select count(*)::text from public.miembros), '2', 'y a sus dos personas');
select pg_temp.falla($q$ update public.casas_oracion set zona_id = null where id = 'a9800000-0000-0000-0000-000000000001' $q$, 'el líder de casa se cambia la zona');
reset role;
select set_config('request.jwt.claim.sub', 'a9500000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.igual((select string_agg(nombre, ',') from public.miembros), 'Cleo', 'el líder de la casa 2 ve solo a su persona');
reset role;

-- 4. Un colaborador no crea zonas ni nombra líderes
select set_config('request.jwt.claim.sub', 'a9500000-0000-0000-0000-000000000005', true);
set local role authenticated;
select pg_temp.falla($q$ insert into public.zonas (codigo, nombre) values ('Y', 'Otra') $q$, 'el colaborador crea una zona');
select pg_temp.falla($q$ update public.casas_oracion set lider_id = 'a9500000-0000-0000-0000-000000000005' where id = 'a9800000-0000-0000-0000-000000000001' $q$, 'el colaborador se nombra líder');
reset role;

-- 5. Reasignar: al mover a una persona, cambia lo que ve cada líder
select set_config('request.jwt.claim.sub', 'a9500000-0000-0000-0000-000000000001', true);
set local role authenticated;
update public.miembros set casa_oracion_id = null where id = 'a9900000-0000-0000-0000-000000000002';
reset role;
select set_config('request.jwt.claim.sub', 'a9500000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.miembros), '1', 'al sacar a una persona, su líder de casa deja de verla');
reset role;
select set_config('request.jwt.claim.sub', 'a9500000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.miembros), '1', 'y el líder de zona también');
reset role;
rollback;
