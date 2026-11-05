-- Ninguna referencia puede apuntar a una persona de otra iglesia: zonas.lider_id e invitaciones.creada_por.
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
create or replace function pg_temp.debe_fallar(q text, msg text) returns void language plpgsql as $$
begin
  begin execute q; exception when foreign_key_violation then raise notice 'OK: %', msg; return; end;
  raise exception 'FALLO: debia rechazarse por la clave foranea: %', msg;
end $$;

insert into auth.users (id) values ('6a000000-0000-0000-0000-000000000001'), ('6a000000-0000-0000-0000-000000000002');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('6b000000-0000-0000-0000-00000000000a', 'Prueba Ref A', 'prueba-rfa', 'ES', 'Sevilla', 'premium'),
  ('6b000000-0000-0000-0000-00000000000b', 'Prueba Ref B', 'prueba-rfb', 'ES', 'Cadiz', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('6a000000-0000-0000-0000-000000000001', '6b000000-0000-0000-0000-00000000000a', 'A', 'Uno', 'a@rf.test', 'miembro', true),
  ('6a000000-0000-0000-0000-000000000002', '6b000000-0000-0000-0000-00000000000b', 'B', 'Uno', 'b@rf.test', 'miembro', true);

-- zonas.lider_id
insert into public.zonas (id, iglesia_id, codigo, nombre, lider_id) values
  ('6c000000-0000-0000-0000-00000000000a', '6b000000-0000-0000-0000-00000000000a', 'ZN-A', 'Zona A', '6a000000-0000-0000-0000-000000000001');
select pg_temp.igual((select lider_id::text from public.zonas where codigo = 'ZN-A'), '6a000000-0000-0000-0000-000000000001', 'una zona acepta como lider a una persona de su iglesia');
select pg_temp.debe_fallar($q$ insert into public.zonas (iglesia_id, codigo, nombre, lider_id) values ('6b000000-0000-0000-0000-00000000000a', 'ZN-X', 'Zona X', '6a000000-0000-0000-0000-000000000002') $q$, 'una zona rechaza como lider a una persona de otra iglesia');
select pg_temp.debe_fallar($q$ update public.zonas set lider_id = '6a000000-0000-0000-0000-000000000002' where codigo = 'ZN-A' $q$, 'cambiar el lider a una persona de otra iglesia tambien se rechaza');
insert into public.zonas (iglesia_id, codigo, nombre) values ('6b000000-0000-0000-0000-00000000000a', 'ZN-S', 'Zona sin lider');
select pg_temp.igual((select count(*)::text from public.zonas where codigo = 'ZN-S' and lider_id is null), '1', 'una zona puede no tener lider');

-- invitaciones.creada_por
insert into public.invitaciones (iglesia_id, email, nombre, apellido, rol, token_hash, creada_por) values
  ('6b000000-0000-0000-0000-00000000000a', 'i1@rf.test', 'I', '1', 'miembro', repeat('1', 64), '6a000000-0000-0000-0000-000000000001');
select pg_temp.debe_fallar($q$ insert into public.invitaciones (iglesia_id, email, nombre, apellido, rol, token_hash, creada_por) values ('6b000000-0000-0000-0000-00000000000a', 'i2@rf.test', 'I', '2', 'miembro', repeat('2', 64), '6a000000-0000-0000-0000-000000000002') $q$, 'una invitacion rechaza como creador a una persona de otra iglesia');

-- Borrar a la persona anula solo la columna de la persona, nunca iglesia_id
delete from public.perfiles where id = '6a000000-0000-0000-0000-000000000001';
select pg_temp.igual((select (lider_id is null)::text || '/' || (iglesia_id is not null)::text from public.zonas where codigo = 'ZN-A'), 'true/true', 'al borrar al lider, la zona queda sin lider y sigue en su iglesia');
select pg_temp.igual((select (creada_por is null)::text || '/' || (iglesia_id is not null)::text from public.invitaciones where email = 'i1@rf.test'), 'true/true', 'al borrar al creador, la invitacion conserva su iglesia');

rollback;
