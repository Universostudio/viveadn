-- Registro de descargas del informe de miembros: una fila por descarga, sin contenido, solo altas, aislado por iglesia.
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
create or replace function pg_temp.falla(sentencia text, codigos text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if position(sqlstate in codigos) = 0 and sqlerrm not like '%' || codigos || '%' then raise exception 'FALLO: % (error inesperado % %)', msg, sqlstate, sqlerrm; end if;
    raise notice 'OK: % (%)', msg, sqlstate; return;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.falla(text, text, text) to authenticated, anon, service_role;

insert into auth.users (id) values ('ad000000-0000-0000-0000-000000000001'), ('ad000000-0000-0000-0000-000000000002'),
  ('ad000000-0000-0000-0000-000000000003'), ('ad000000-0000-0000-0000-000000000004');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ad100000-0000-0000-0000-00000000000a', 'Prueba Desc A', 'prueba-desc-a', 'ES', 'Sevilla', 'premium'),
  ('ad100000-0000-0000-0000-00000000000b', 'Prueba Desc B', 'prueba-desc-b', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('ad000000-0000-0000-0000-000000000001', 'ad100000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@prueba.test', 'propietario', true),
  ('ad000000-0000-0000-0000-000000000002', 'ad100000-0000-0000-0000-00000000000a', 'Co', 'A', 'co@prueba.test', 'coadministrador', true),
  ('ad000000-0000-0000-0000-000000000003', 'ad100000-0000-0000-0000-00000000000a', 'Col', 'A', 'col@prueba.test', 'colaborador', true),
  ('ad000000-0000-0000-0000-000000000004', 'ad100000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@prueba.test', 'propietario', true);
insert into public.miembros (iglesia_id, nombre, apellido) values
  ('ad100000-0000-0000-0000-00000000000a', 'M1', 'A'), ('ad100000-0000-0000-0000-00000000000a', 'M2', 'A'), ('ad100000-0000-0000-0000-00000000000a', 'M3', 'A'),
  ('ad100000-0000-0000-0000-00000000000b', 'M1', 'B');

-- El propietario de A descarga el informe: la funcion se ejecuta una vez por pagina y deja una sola fila
select set_config('request.jwt.claim.sub', 'ad000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select count(*) from public.adn_informe_miembros();
select count(*) from public.adn_informe_miembros();
select pg_temp.igual((select count(*)::text from public.adn_informe_descargas), '1', 'varias paginas de una descarga dejan una sola fila');
select pg_temp.igual((select filas::text from public.adn_informe_descargas), '3', 'la fila guarda cuantas filas tenia el informe');
select pg_temp.igual((select informe from public.adn_informe_descargas), 'miembros', 'la fila guarda que informe fue');
select pg_temp.igual((select (usuario_id = 'ad000000-0000-0000-0000-000000000001')::text from public.adn_informe_descargas), 'true', 'la fila guarda quien lo descargo');
-- Solo altas: ninguna persona autenticada escribe en la tabla
select pg_temp.falla($$insert into public.adn_informe_descargas (iglesia_id, usuario_id, informe, filas) values ('ad100000-0000-0000-0000-00000000000a', 'ad000000-0000-0000-0000-000000000001', 'miembros', 1)$$, '42501', 'una persona no inserta registros a mano');
select pg_temp.falla($$update public.adn_informe_descargas set filas = 0$$, '42501', 'una persona no modifica registros');
select pg_temp.falla($$delete from public.adn_informe_descargas$$, '42501', 'una persona no borra registros');
reset role;
-- Ni el propio servicio puede modificar un registro (inmutable); si borrarlo, para la purga de la iglesia
select pg_temp.falla($$update public.adn_informe_descargas set filas = 0$$, 'ADN_REGISTRO_INMUTABLE', 'ni el servicio modifica un registro');

-- Pasados dos minutos, otra descarga es otra fila (se retrasa la fila con los disparadores apagados, como haria una restauracion)
set local session_replication_role = replica;
update public.adn_informe_descargas set created_at = now() - interval '3 minutes';
reset session_replication_role;
select set_config('request.jwt.claim.sub', 'ad000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select count(*) from public.adn_informe_miembros();
select pg_temp.igual((select count(*)::text from public.adn_informe_descargas), '2', 'pasados dos minutos, otra descarga es otra fila');
reset role;

-- El coadministrador descarga el informe (tiene miembros.exportar) pero no puede leer el registro (no gestiona usuarios)
select set_config('request.jwt.claim.sub', 'ad000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select count(*) from public.adn_informe_miembros();
select pg_temp.igual((select count(*)::text from public.adn_informe_descargas), '0', 'quien no gestiona usuarios no lee el registro');
reset role;
select pg_temp.igual((select count(*)::text from public.adn_informe_descargas where usuario_id = 'ad000000-0000-0000-0000-000000000002'), '1', 'la descarga del coadministrador quedo registrada');

-- El colaborador no puede descargar el informe y no deja registro
select set_config('request.jwt.claim.sub', 'ad000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.falla($$select count(*) from public.adn_informe_miembros()$$, 'ADN_SIN_PERMISO', 'el colaborador no descarga el informe');
reset role;
select pg_temp.igual((select count(*)::text from public.adn_informe_descargas where usuario_id = 'ad000000-0000-0000-0000-000000000003'), '0', 'un intento rechazado no deja registro');

-- Aislamiento: B descarga su informe; A no ve la fila de B ni B las de A
select set_config('request.jwt.claim.sub', 'ad000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select count(*) from public.adn_informe_miembros();
select pg_temp.igual((select count(*)::text from public.adn_informe_descargas), '1', 'B solo ve sus propias descargas');
select pg_temp.igual((select filas::text from public.adn_informe_descargas), '1', 'la fila de B cuenta las filas de B');
reset role;
select set_config('request.jwt.claim.sub', 'ad000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_informe_descargas where iglesia_id <> 'ad100000-0000-0000-0000-00000000000a'), '0', 'A no ve las descargas de B');
reset role;
-- Sin contenido: la tabla no tiene ninguna columna que pueda guardar datos de miembros
select pg_temp.igual((select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'adn_informe_descargas'),
  'id,iglesia_id,usuario_id,informe,filas,created_at', 'el registro no tiene columnas de contenido');
-- Al borrar la iglesia desaparecen sus registros
delete from public.iglesias where id = 'ad100000-0000-0000-0000-00000000000b';
select pg_temp.igual((select count(*)::text from public.adn_informe_descargas where iglesia_id = 'ad100000-0000-0000-0000-00000000000b'), '0', 'al borrar la iglesia se borran sus registros');
rollback;
