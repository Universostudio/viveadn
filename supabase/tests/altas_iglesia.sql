-- Altas de iglesia: lo declarado en el asistente lo escribe solo el servidor, lo lee solo quien configura su iglesia y tiene limites duros.
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

insert into auth.users (id) values ('0f000000-0000-0000-0000-000000000001'), ('0f000000-0000-0000-0000-000000000002'), ('0f000000-0000-0000-0000-000000000003');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('0f100000-0000-0000-0000-00000000000a', 'Iglesia A', 'prueba-alta-a', 'ES', 'Sevilla', 'basico'),
  ('0f100000-0000-0000-0000-00000000000b', 'Iglesia B', 'prueba-alta-b', 'ES', 'Sevilla', 'basico');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('0f000000-0000-0000-0000-000000000001', '0f100000-0000-0000-0000-00000000000a', 'Pro', 'A', 'p@aa.test', 'propietario', true),
  ('0f000000-0000-0000-0000-000000000002', '0f100000-0000-0000-0000-00000000000a', 'Col', 'A', 'c@aa.test', 'colaborador', true),
  ('0f000000-0000-0000-0000-000000000003', '0f100000-0000-0000-0000-00000000000b', 'Pro', 'B', 'p@ab.test', 'propietario', true);
insert into public.altas_iglesia (iglesia_id, estructura, personas, sedes, modulos, administradores) values
  ('0f100000-0000-0000-0000-00000000000a', 'con_sedes', 250, 3, array['whatsapp', 'credenciales'], '[{"nombre":"Ana","apellido":"Gil","email":"ana@ejemplo.test"}]'),
  ('0f100000-0000-0000-0000-00000000000b', 'unica', 40, 0, '{}', '[]');

-- Limites duros de la propia tabla
select pg_temp.igual(pg_temp.codigo($q$ insert into public.altas_iglesia (iglesia_id, estructura) select id, 'otra' from public.iglesias where slug = 'prueba-alta-a' on conflict (iglesia_id) do update set estructura = 'otra' $q$), '23514', 'una estructura que no existe se rechaza');
select pg_temp.igual(pg_temp.codigo($q$ update public.altas_iglesia set sedes = 2 where iglesia_id = '0f100000-0000-0000-0000-00000000000b' $q$), '23514', 'una iglesia unica no tiene sedes');
select pg_temp.igual(pg_temp.codigo($q$ update public.altas_iglesia set personas = 0 where iglesia_id = '0f100000-0000-0000-0000-00000000000b' $q$), '23514', 'las personas son al menos una');
select pg_temp.igual(pg_temp.codigo($q$ update public.altas_iglesia set personas = 1000001 where iglesia_id = '0f100000-0000-0000-0000-00000000000b' $q$), '23514', 'y hay un tope');
select pg_temp.igual(pg_temp.codigo($q$ update public.altas_iglesia set administradores = '[1,2,3,4,5,6]'::jsonb where iglesia_id = '0f100000-0000-0000-0000-00000000000b' $q$), '23514', 'como mucho cinco administradores propuestos');
select pg_temp.igual(pg_temp.codigo($q$ update public.altas_iglesia set administradores = '{"a":1}'::jsonb where iglesia_id = '0f100000-0000-0000-0000-00000000000b' $q$), '23514', 'los administradores son una lista');
select pg_temp.igual(pg_temp.codigo($q$ update public.altas_iglesia set modulos = (select array_agg('m' || g) from generate_series(1, 31) g) where iglesia_id = '0f100000-0000-0000-0000-00000000000b' $q$), '23514', 'y como mucho 30 modulos');

-- Quien configura su iglesia la lee; nadie la escribe desde la web; otra iglesia no la ve
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.altas_iglesia), '1', 'el propietario lee solo el alta de su iglesia');
select pg_temp.igual((select estructura from public.altas_iglesia), 'con_sedes', 'con lo que declaro');
select pg_temp.igual(pg_temp.codigo($q$ update public.altas_iglesia set personas = 5 $q$), '42501', 'no la edita desde la web');
select pg_temp.igual(pg_temp.codigo($q$ insert into public.altas_iglesia (iglesia_id) values ('0f100000-0000-0000-0000-00000000000a') $q$), '42501', 'ni la crea');
select pg_temp.igual(pg_temp.codigo($q$ delete from public.altas_iglesia $q$), '42501', 'ni la borra');
reset role;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.altas_iglesia), '0', 'un colaborador sin permiso de configurar no ve los correos propuestos');
reset role;
select set_config('request.jwt.claim.sub', '0f000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select iglesia_id::text from public.altas_iglesia), '0f100000-0000-0000-0000-00000000000b', 'otra iglesia solo ve la suya');
reset role;
set local role anon;
select pg_temp.igual(pg_temp.codigo($q$ select * from public.altas_iglesia $q$), '42501', 'un visitante anonimo no la lee');
reset role;
-- Borrar la iglesia se lleva su alta
delete from public.iglesias where id = '0f100000-0000-0000-0000-00000000000a';
select pg_temp.igual((select count(*)::text from public.altas_iglesia where iglesia_id = '0f100000-0000-0000-0000-00000000000a'), '0', 'borrar la iglesia borra su alta');
rollback;
