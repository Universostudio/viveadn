-- Precios por moneda: una lista por moneda, sin huecos, solo monedas conocidas, y la moneda de cada iglesia sale de lo que declaro al registrarse.
\set ON_ERROR_STOP on
begin;
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
create or replace function pg_temp.codigo(q text) returns text language plpgsql as $$
begin execute q; return 'ok'; exception when others then return sqlstate; end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.codigo(text) to authenticated, anon;

select pg_temp.igual((select string_agg(codigo, ',' order by orden) from public.monedas), 'USD,EUR', 'hay dos monedas: USD y EUR');
-- Cada moneda tiene la lista completa: mismos planes y mismos modulos
select pg_temp.igual((select count(*)::text from (select plan from public.precios_plan group by plan having count(*) <> (select count(*) from public.monedas)) x), '0', 'cada plan tiene un precio en cada moneda');
select pg_temp.igual((select count(*)::text from (select modulo from public.precios_modulo group by modulo having count(*) <> (select count(*) from public.monedas)) x), '0', 'cada modulo tiene un precio en cada moneda');
-- Una moneda desconocida no puede tener precios ni ser la de una iglesia
select pg_temp.igual(pg_temp.codigo($q$ insert into public.precios_plan (plan, moneda, importe_centimos) values ('basico', 'MXN', 1) $q$), '23503', 'no hay precios en una moneda que no existe');
select pg_temp.igual(pg_temp.codigo($q$ insert into public.precios_plan (plan, moneda, importe_centimos) values ('basico', 'USD', 1) $q$), '23505', 'un plan no tiene dos precios en la misma moneda');
select pg_temp.igual(pg_temp.codigo($q$ update public.monedas set codigo = 'euro' where codigo = 'EUR' $q$), '23514', 'el codigo de moneda son tres letras');
select pg_temp.igual(pg_temp.codigo($q$ update public.precios_ajustes set moneda = 'MXN' $q$), '23503', 'la moneda base debe ser una moneda conocida');

-- Lo declarado al registrarse
insert into auth.users (id) values ('10000000-0000-0000-0000-000000000001');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('10100000-0000-0000-0000-00000000000a', 'Iglesia Moneda', 'prueba-moneda', 'ES', 'Sevilla', 'basico');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('10000000-0000-0000-0000-000000000001', '10100000-0000-0000-0000-00000000000a', 'Pro', 'M', 'p@mo.test', 'propietario', true);
insert into public.altas_iglesia (iglesia_id, pais_iso, moneda) values ('10100000-0000-0000-0000-00000000000a', 'ES', 'EUR');
select pg_temp.igual((select moneda from public.altas_iglesia where iglesia_id = '10100000-0000-0000-0000-00000000000a'), 'EUR', 'la iglesia guarda su moneda');
select pg_temp.igual(pg_temp.codigo($q$ update public.altas_iglesia set pais_iso = 'es' $q$), '23514', 'el pais es un codigo ISO en mayusculas de dos letras');
select pg_temp.igual(pg_temp.codigo($q$ update public.altas_iglesia set moneda = 'MXN' $q$), '23503', 'la moneda de la iglesia debe existir');

-- Una iglesia lee las monedas pero no las cambia; anonimo no las ve
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.monedas), '2', 'una iglesia lee las monedas');
select pg_temp.igual(pg_temp.codigo($q$ insert into public.monedas (codigo, nombre) values ('MXN', 'Peso') $q$), '42501', 'pero no crea monedas');
select pg_temp.igual(pg_temp.codigo($q$ update public.monedas set activa = false $q$), '42501', 'ni las desactiva');
select pg_temp.igual(pg_temp.codigo($q$ update public.altas_iglesia set moneda = 'USD' $q$), '42501', 'ni cambia lo que declaro al registrarse');
reset role;
set local role anon;
select pg_temp.igual(pg_temp.codigo($q$ select * from public.monedas $q$), '42501', 'un visitante anonimo no lee las monedas');
reset role;
rollback;
