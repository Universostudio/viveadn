-- Red de iglesias: un solo nivel, sin ciclos, y solo la plataforma cambia la red.
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
  begin execute q; exception when others then raise notice 'OK: %', msg; return; end;
  raise exception 'FALLO: debia fallar: %', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.debe_fallar(text, text) to authenticated, service_role;

insert into auth.users (id) values ('e4000000-0000-0000-0000-000000000001');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('2c000000-0000-0000-0000-00000000000a', 'Prueba Madre', 'prueba-rm', 'ES', 'Sevilla', 'premium'),
  ('2c000000-0000-0000-0000-00000000000b', 'Prueba Sede 1', 'prueba-rs1', 'ES', 'Cadiz', 'premium'),
  ('2c000000-0000-0000-0000-00000000000c', 'Prueba Sede 2', 'prueba-rs2', 'ES', 'Huelva', 'premium'),
  ('2c000000-0000-0000-0000-00000000000d', 'Prueba Suelta', 'prueba-rx', 'ES', 'Malaga', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('e4000000-0000-0000-0000-000000000001', '2c000000-0000-0000-0000-00000000000b', 'Pro', 'Sede', 'p@rs1.test', 'propietario', true);

-- Valores por defecto
select pg_temp.igual((select red_acceso from public.iglesias where id = '2c000000-0000-0000-0000-00000000000b'), 'resumen', 'por defecto una sede comparte el resumen');
select pg_temp.igual((select iglesia_madre_id::text from public.iglesias where id = '2c000000-0000-0000-0000-00000000000b'), null, 'por defecto no hay madre');

-- La plataforma (service_role / sin usuario) puede vincular sedes
update public.iglesias set iglesia_madre_id = '2c000000-0000-0000-0000-00000000000a' where id in ('2c000000-0000-0000-0000-00000000000b', '2c000000-0000-0000-0000-00000000000c');
select pg_temp.igual((select count(*)::text from public.iglesias where iglesia_madre_id = '2c000000-0000-0000-0000-00000000000a'), '2', 'la madre tiene dos sedes');
update public.iglesias set red_acceso = 'ninguno' where id = '2c000000-0000-0000-0000-00000000000c';
select pg_temp.igual((select red_acceso from public.iglesias where id = '2c000000-0000-0000-0000-00000000000c'), 'ninguno', 'se puede quitar el acceso a una sede');

-- Reglas de forma
select pg_temp.debe_fallar($q$ update public.iglesias set red_acceso = 'total' where id = '2c000000-0000-0000-0000-00000000000b' $q$, 'nivel de acceso desconocido');
select pg_temp.debe_fallar($q$ update public.iglesias set iglesia_madre_id = id where id = '2c000000-0000-0000-0000-00000000000d' $q$, 'una iglesia no es madre de si misma');
select pg_temp.debe_fallar($q$ update public.iglesias set iglesia_madre_id = '2c000000-0000-0000-0000-00000000000b' where id = '2c000000-0000-0000-0000-00000000000d' $q$, 'una sede no puede ser madre');
select pg_temp.debe_fallar($q$ update public.iglesias set iglesia_madre_id = '2c000000-0000-0000-0000-00000000000d' where id = '2c000000-0000-0000-0000-00000000000a' $q$, 'una madre con sedes no puede ser sede');
select pg_temp.debe_fallar($q$ update public.iglesias set iglesia_madre_id = '2c000000-0000-0000-0000-00000000000a' where id = '2c000000-0000-0000-0000-00000000000a' $q$, 'no hay ciclos de un nodo');
select pg_temp.igual((select count(*)::text from public.iglesias where iglesia_madre_id is not null), '2', 'los intentos rechazados no dejaron rastro');

-- Borrar la madre no borra las sedes: quedan como iglesias independientes
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, iglesia_madre_id) values
  ('2c000000-0000-0000-0000-00000000000e', 'Prueba Madre Temporal', 'prueba-rt', 'ES', 'Sevilla', 'premium', null),
  ('2c000000-0000-0000-0000-00000000000f', 'Prueba Hija Temporal', 'prueba-rh', 'ES', 'Sevilla', 'premium', '2c000000-0000-0000-0000-00000000000e');
delete from public.iglesias where id = '2c000000-0000-0000-0000-00000000000e';
select pg_temp.igual((select iglesia_madre_id::text from public.iglesias where id = '2c000000-0000-0000-0000-00000000000f'), null, 'al borrar la madre, la sede queda independiente');

-- Una iglesia lee su red pero no la cambia
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e4000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select pg_temp.igual((select iglesia_madre_id::text from public.iglesias where id = '2c000000-0000-0000-0000-00000000000b'), '2c000000-0000-0000-0000-00000000000a', 'la sede lee quien es su madre');
select pg_temp.igual((select red_acceso from public.iglesias where id = '2c000000-0000-0000-0000-00000000000b'), 'resumen', 'la sede lee su nivel de acceso');
select pg_temp.debe_fallar($q$ update public.iglesias set iglesia_madre_id = null where id = '2c000000-0000-0000-0000-00000000000b' $q$, 'la sede no se desvincula sola');
select pg_temp.debe_fallar($q$ update public.iglesias set red_acceso = 'ninguno' where id = '2c000000-0000-0000-0000-00000000000b' $q$, 'la sede no cambia su nivel de acceso');
select pg_temp.igual((select count(*)::text from public.iglesias), '1', 'la sede solo ve su propia fila');
reset role;

rollback;
