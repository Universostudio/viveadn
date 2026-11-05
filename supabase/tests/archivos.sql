-- Pruebas del almacenamiento de archivos: aislamiento por iglesia y permisos.
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
grant execute on function pg_temp.igual(text, text, text) to authenticated, anon;
create or replace function pg_temp.sube(p_cubo text, p_ruta text) returns boolean language plpgsql as $$
begin
  insert into storage.objects (bucket_id, name) values (p_cubo, p_ruta);
  return true;
exception when others then return false;
end $$;
grant execute on function pg_temp.sube(text, text) to authenticated;

insert into auth.users (id) values
  ('ff000000-0000-0000-0000-000000000001'), ('ff000000-0000-0000-0000-000000000002'), ('ff000000-0000-0000-0000-000000000003');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ff100000-0000-0000-0000-00000000000a', 'Prueba A', 'prueba-a', 'ES', 'Sevilla', 'premium'),
  ('ff100000-0000-0000-0000-00000000000b', 'Prueba B', 'prueba-b', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('ff000000-0000-0000-0000-000000000001', 'ff100000-0000-0000-0000-00000000000a', 'PA', 'X', 'pa@prueba.test', 'propietario', true),
  ('ff000000-0000-0000-0000-000000000002', 'ff100000-0000-0000-0000-00000000000a', 'CA', 'X', 'ca@prueba.test', 'colaborador', true),
  ('ff000000-0000-0000-0000-000000000003', 'ff100000-0000-0000-0000-00000000000b', 'PB', 'X', 'pb@prueba.test', 'propietario', true);
-- Un archivo ya existente de cada iglesia, puesto por el servidor
insert into storage.objects (bucket_id, name) values
  ('iglesia-archivos', 'ff100000-0000-0000-0000-00000000000a/docs/a.pdf'),
  ('iglesia-archivos', 'ff100000-0000-0000-0000-00000000000b/docs/b.pdf'),
  ('iglesia-marca', 'ff100000-0000-0000-0000-00000000000b/logo.png');

-- Cubos: privado el de documentos, sin SVG en el publico
select pg_temp.igual((select public::text from storage.buckets where id = 'iglesia-archivos'), 'false', 'el cubo de documentos es privado');
select pg_temp.igual((select (not 'image/svg+xml' = any (allowed_mime_types))::text from storage.buckets where id = 'iglesia-marca'), 'true', 'el cubo publico no admite SVG');

-- Propietario de A
select set_config('request.jwt.claim.sub', 'ff000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual(pg_temp.sube('iglesia-marca', 'ff100000-0000-0000-0000-00000000000a/logo.png')::text, 'true', 'el propietario sube el logo de su iglesia');
select pg_temp.igual(pg_temp.sube('iglesia-archivos', 'ff100000-0000-0000-0000-00000000000a/docs/nuevo.pdf')::text, 'true', 'el propietario sube un documento de su iglesia');
select pg_temp.igual(pg_temp.sube('iglesia-marca', 'ff100000-0000-0000-0000-00000000000b/logo2.png')::text, 'false', 'no sube a la carpeta de otra iglesia');
select pg_temp.igual(pg_temp.sube('iglesia-archivos', 'sin-carpeta.pdf')::text, 'false', 'no sube en la raiz del cubo');
select pg_temp.igual(pg_temp.sube('iglesia-archivos', 'ff100000-0000-0000-0000-00000000000b/docs/colado.pdf')::text, 'false', 'no sube documentos a otra iglesia');
select pg_temp.igual((select count(*)::text from storage.objects where bucket_id = 'iglesia-archivos'), '2', 'solo ve los documentos de su iglesia');
select pg_temp.igual((select count(*)::text from storage.objects where bucket_id = 'iglesia-marca' and name like 'ff100000-0000-0000-0000-00000000000b/%'), '0', 'no ve la marca de otra iglesia');
delete from storage.objects where name = 'ff100000-0000-0000-0000-00000000000b/docs/b.pdf';
do $$ begin
  begin update storage.objects set name = 'ff100000-0000-0000-0000-00000000000b/docs/robado.pdf' where name = 'ff100000-0000-0000-0000-00000000000a/docs/a.pdf'; exception when others then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select count(*)::text from storage.objects where name = 'ff100000-0000-0000-0000-00000000000b/docs/b.pdf'), '1', 'no borra archivos de otra iglesia');
select pg_temp.igual((select count(*)::text from storage.objects where name = 'ff100000-0000-0000-0000-00000000000b/docs/robado.pdf'), '0', 'no mueve un archivo a otra iglesia');

-- Colaborador de A: lee pero no escribe
select set_config('request.jwt.claim.sub', 'ff000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual(pg_temp.sube('iglesia-archivos', 'ff100000-0000-0000-0000-00000000000a/docs/colab.pdf')::text, 'false', 'el colaborador no sube archivos');
select pg_temp.igual((select count(*)::text from storage.objects where bucket_id = 'iglesia-archivos'), '2', 'el colaborador lee los documentos de su iglesia');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Anonimo: nada
set local role anon;
select pg_temp.igual((select count(*)::text from storage.objects) , '0', 'un anonimo no ve ningun objeto');
reset role;

-- Iglesia en receso: ya no lee ni escribe
update public.iglesias set etapa = 'receso' where slug = 'prueba-a';
select set_config('request.jwt.claim.sub', 'ff000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from storage.objects where bucket_id = 'iglesia-archivos'), '0', 'una iglesia en receso no lee sus documentos');
select pg_temp.igual(pg_temp.sube('iglesia-archivos', 'ff100000-0000-0000-0000-00000000000a/docs/receso.pdf')::text, 'false', 'una iglesia en receso no sube archivos');
reset role;
select set_config('request.jwt.claim.sub', '', true);
rollback;
