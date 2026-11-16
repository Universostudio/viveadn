-- Catalogo de precios: global, de solo lectura para las iglesias, completo y con la decision de moneda aun sin tomar.
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

select pg_temp.igual((select count(*)::text from public.planes where clave not in (select plan from public.precios_plan)), '0', 'todos los planes tienen precio');
-- Todo modulo que no viene en los tres planes se puede contratar, asi que debe tener precio
select pg_temp.igual((select count(*)::text from public.modulos m
  where m.tipo <> 'nucleo'
    and exists (select 1 from public.planes p where not exists (select 1 from public.plan_modulos pm where pm.plan = p.clave and pm.modulo = m.clave))
    and not exists (select 1 from public.precios_modulo pr where pr.modulo = m.clave)), '0', 'todo modulo contratable tiene precio');
select pg_temp.igual((select string_agg(plan || ':' || importe_centimos, ',' order by importe_centimos) from public.precios_plan), 'semilla:900,basico:2900,premium:7900', 'la propuesta de planes es la de docs/PLANES.md');
select pg_temp.igual((select count(*)::text from public.precios_ajustes), '1', 'hay una unica fila de ajustes');
select pg_temp.igual((select (moneda is null and impuestos_incluidos is null and propuesta)::text from public.precios_ajustes), 'true', 'moneda e impuestos sin decidir y todo marcado como propuesta');
select pg_temp.igual(pg_temp.codigo($q$ insert into public.precios_ajustes (id) values (false) $q$), '23514', 'no puede haber una segunda fila de ajustes');
select pg_temp.igual(pg_temp.codigo($q$ update public.precios_ajustes set moneda = 'euro' $q$), '23514', 'la moneda es un codigo de tres letras');
select pg_temp.igual(pg_temp.codigo($q$ update public.precios_plan set importe_centimos = -1 where plan = 'basico' $q$), '23514', 'un importe negativo se rechaza');

-- Las iglesias leen el catalogo pero no lo cambian; un visitante anonimo no lo ve
insert into auth.users (id) values ('0e000000-0000-0000-0000-000000000001');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('0e100000-0000-0000-0000-00000000000a', 'Iglesia Prueba', 'prueba-precios', 'ES', 'Sevilla', 'basico');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('0e000000-0000-0000-0000-000000000001', '0e100000-0000-0000-0000-00000000000a', 'Pro', 'A', 'p@pr.test', 'propietario', true);
select set_config('request.jwt.claim.sub', '0e000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.precios_plan), '3', 'una iglesia lee los precios de los planes');
select pg_temp.igual((select (count(*) > 0)::text from public.precios_modulo), 'true', 'y los de los modulos');
select pg_temp.igual(pg_temp.codigo($q$ update public.precios_plan set importe_centimos = 1 $q$), '42501', 'pero no los cambia, ni siendo propietaria');
select pg_temp.igual(pg_temp.codigo($q$ insert into public.precios_modulo (modulo, importe_centimos) values ('miembros', 1) $q$), '42501', 'ni crea precios');
select pg_temp.igual(pg_temp.codigo($q$ delete from public.precios_modulo $q$), '42501', 'ni los borra');
select pg_temp.igual(pg_temp.codigo($q$ update public.precios_ajustes set moneda = 'EUR' $q$), '42501', 'ni decide la moneda');
reset role;
set local role anon;
select pg_temp.igual(pg_temp.codigo($q$ select * from public.precios_plan $q$), '42501', 'un visitante anonimo no lee el catalogo');
reset role;
-- Borrar un modulo se lleva su precio
delete from public.modulos where clave = 'app_marca';
select pg_temp.igual((select count(*)::text from public.precios_modulo where modulo = 'app_marca'), '0', 'borrar un modulo borra su precio');
rollback;
