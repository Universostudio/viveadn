-- Autoservicio del propietario: descarga limitada y auditada, baja como borrado suave con plazo, cancelación solo de la baja propia.
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
create or replace function pg_temp.falla(sentencia text, texto text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if sqlerrm like '%' || texto || '%' then raise notice 'OK: %', msg; return; end if;
    raise exception 'FALLO: % (error inesperado: %)', msg, sqlerrm;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
grant execute on function pg_temp.falla(text, text, text) to authenticated, anon, service_role;

insert into auth.users (id) values
  ('a9100000-0000-0000-0000-000000000001'), ('a9100000-0000-0000-0000-000000000002'), ('a9100000-0000-0000-0000-000000000003'),
  ('a9100000-0000-0000-0000-000000000004'), ('a9100000-0000-0000-0000-000000000005'), ('a9100000-0000-0000-0000-0000000000f1');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('a9200000-0000-0000-0000-00000000000a', 'Prueba Auto A', 'prueba-auto-a', 'ES', 'Sevilla', 'premium'),
  ('a9200000-0000-0000-0000-00000000000b', 'Prueba Auto B', 'prueba-auto-b', 'ES', 'Sevilla', 'premium');
set local session_replication_role = replica;
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('a9100000-0000-0000-0000-000000000001', 'a9200000-0000-0000-0000-00000000000a', 'Pro', 'Pietario', 'p@auto-a.test', 'propietario', true),
  ('a9100000-0000-0000-0000-000000000002', 'a9200000-0000-0000-0000-00000000000a', 'Adm', 'Inistra', 'a@auto-a.test', 'administrador', true),
  ('a9100000-0000-0000-0000-000000000003', 'a9200000-0000-0000-0000-00000000000b', 'Pro', 'Otra', 'p@auto-b.test', 'propietario', true),
  ('a9100000-0000-0000-0000-000000000004', 'a9200000-0000-0000-0000-00000000000a', 'Pro', 'Inactivo', 'i@auto-a.test', 'propietario', false);
reset session_replication_role;

-- 1. Quién cuenta como propietario: activo, con el rol propietario y de esa iglesia
select pg_temp.igual(public.adn_es_propietario('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001')::text, 'true', 'el propietario activo lo es');
select pg_temp.igual(public.adn_es_propietario('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000002')::text, 'false', 'un administrador no lo es');
select pg_temp.igual(public.adn_es_propietario('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000003')::text, 'false', 'el propietario de otra iglesia no lo es de esta');
select pg_temp.igual(public.adn_es_propietario('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000004')::text, 'false', 'un propietario desactivado no lo es');
select pg_temp.igual(public.adn_es_propietario('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000005')::text, 'false', 'quien no tiene perfil no lo es');
select pg_temp.igual(public.adn_es_propietario('a9200000-0000-0000-0000-00000000000a', null)::text, 'false', 'un actor nulo no lo es');

-- 2. Estado
select pg_temp.igual((public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001') ->> 'slug'), 'prueba-auto-a', 'el propietario ve el estado de su iglesia');
select pg_temp.igual((public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001') -> 'baja')::text, 'null', 'sin baja, el estado no la muestra');
select pg_temp.igual((public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001') ->> 'descargas_restantes'), '6', 'seis descargas por hora');
select pg_temp.falla($$select public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000002')$$, 'ADN_NO_PROPIETARIO', 'un administrador no ve el estado de baja');
select pg_temp.falla($$select public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000003')$$, 'ADN_NO_PROPIETARIO', 'ni el propietario de otra iglesia');

-- 3. Descargas: auditadas y limitadas a 6 por hora y por iglesia
select pg_temp.falla($$select public.adn_autoservicio_exportar('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000002')$$, 'ADN_NO_PROPIETARIO', 'un administrador no descarga todo');
select pg_temp.igual((select count(*)::text from public.adn_datos_auditoria where iglesia_ref = 'a9200000-0000-0000-0000-00000000000a'), '0', 'lo rechazado no deja rastro de descarga');
select public.adn_autoservicio_exportar('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001') from generate_series(1, 6);
select pg_temp.igual((select count(*)::text from public.adn_datos_auditoria where iglesia_ref = 'a9200000-0000-0000-0000-00000000000a' and accion = 'exportacion' and actor = 'a9100000-0000-0000-0000-000000000001'), '6', 'seis descargas, seis anotaciones con su autor');
select pg_temp.falla($$select public.adn_autoservicio_exportar('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001')$$, 'ADN_LIMITE_DESCARGAS', 'la séptima en la hora se rechaza');
select pg_temp.igual((public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001') ->> 'descargas_restantes'), '0', 'el estado dice que no quedan');
select public.adn_autoservicio_exportar('a9200000-0000-0000-0000-00000000000b', 'a9100000-0000-0000-0000-000000000003');
select pg_temp.igual((select count(*)::text from public.adn_datos_auditoria where iglesia_ref = 'a9200000-0000-0000-0000-00000000000b'), '1', 'el límite es por iglesia: otra descarga normal en la otra');
update public.adn_datos_auditoria set ocurrido_en = now() - interval '61 minutes' where iglesia_ref = 'a9200000-0000-0000-0000-00000000000a';
select public.adn_autoservicio_exportar('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001');
select pg_temp.igual((select count(*)::text from public.adn_datos_auditoria where iglesia_ref = 'a9200000-0000-0000-0000-00000000000a' and ocurrido_en > now() - interval '1 hour'), '1', 'pasada la hora, vuelve a poder descargar');
select pg_temp.igual((select detalle::text from public.adn_datos_auditoria where iglesia_ref = 'a9200000-0000-0000-0000-00000000000b'), '{"paginado": true}', 'la anotación no lleva datos de personas');

-- 4. Baja: no borra nada, suspende y fija la purga a 30 días
select pg_temp.falla($$select public.adn_autoservicio_baja('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000002', 'quiero irme')$$, 'ADN_NO_PROPIETARIO', 'un administrador no pide la baja');
select pg_temp.falla($$select public.adn_autoservicio_baja('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000003', 'quiero irme')$$, 'ADN_NO_PROPIETARIO', 'ni el propietario de otra iglesia');
select pg_temp.igual((select adn_borrada_en is null from public.iglesias where id = 'a9200000-0000-0000-0000-00000000000a')::text, 'true', 'lo rechazado no toca la iglesia');
create temp table baja1 as select public.adn_autoservicio_baja('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001', 'cerramos la sede') as purga;
select pg_temp.igual((select (purga between now() + interval '29 days 23 hours' and now() + interval '30 days 1 hour')::text from baja1), 'true', 'la purga queda a 30 días, nunca inmediata');
select pg_temp.igual((select etapa || ',' || (adn_borrada_por = 'a9100000-0000-0000-0000-000000000001')::text from public.iglesias where id = 'a9200000-0000-0000-0000-00000000000a'), 'suspendida,true', 'la iglesia queda suspendida y con su propietario como autor');
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = 'a9200000-0000-0000-0000-00000000000a') || (select count(*)::text from public.perfiles where iglesia_id = 'a9200000-0000-0000-0000-00000000000a'), '03', 'no se borró ningún dato: siguen los perfiles');
select pg_temp.igual((select count(*)::text from public.adn_ciclo_auditoria where iglesia_ref = 'a9200000-0000-0000-0000-00000000000a' and accion = 'borrado_suave' and motivo = 'autoservicio: cerramos la sede'), '1', 'el borrado suave queda en la auditoría del ciclo con su motivo');
select pg_temp.igual((select count(*)::text from public.adn_datos_auditoria where iglesia_ref = 'a9200000-0000-0000-0000-00000000000a' and accion = 'baja_solicitada'), '1', 'y la baja en la auditoría de autoservicio');
select pg_temp.falla($$select public.adn_autoservicio_baja('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001', 'otra vez')$$, 'ADN_YA_BORRADA', 'no se puede pedir dos veces');
select pg_temp.igual((public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001') -> 'baja' ->> 'por_la_iglesia'), 'true', 'el estado dice que la baja la pidió la iglesia');
select pg_temp.igual((public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001') -> 'baja' ->> 'cancelable'), 'true', 'y que se puede cancelar');
-- Una iglesia suspendida por su baja sigue pudiendo descargar sus datos dentro del plazo
update public.adn_datos_auditoria set ocurrido_en = now() - interval '2 hours' where iglesia_ref = 'a9200000-0000-0000-0000-00000000000a' and accion = 'exportacion';
select public.adn_autoservicio_exportar('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001');
select pg_temp.igual(((public.adn_exportar_plan('a9200000-0000-0000-0000-00000000000a') ->> 'formato') is not null)::text, 'true', 'con la baja pedida el plan de exportación sigue disponible');

-- 5. Cancelación
select pg_temp.falla($$select public.adn_autoservicio_cancelar_baja('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000002')$$, 'ADN_NO_PROPIETARIO', 'un administrador no cancela la baja');
select pg_temp.falla($$select public.adn_autoservicio_cancelar_baja('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000003')$$, 'ADN_NO_PROPIETARIO', 'ni el propietario de otra iglesia');
select pg_temp.igual(public.adn_autoservicio_cancelar_baja('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001', 'nos quedamos'), 'activa', 'el propietario cancela y la iglesia vuelve a su etapa anterior');
select pg_temp.igual((select (adn_borrada_en is null and borrado_programado_en is null)::text from public.iglesias where id = 'a9200000-0000-0000-0000-00000000000a'), 'true', 'sin marcas de borrado');
select pg_temp.igual((select count(*)::text from public.adn_datos_auditoria where iglesia_ref = 'a9200000-0000-0000-0000-00000000000a' and accion = 'baja_cancelada'), '1', 'la cancelación queda anotada');
select pg_temp.falla($$select public.adn_autoservicio_cancelar_baja('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001')$$, 'ADN_NO_BORRADA', 'cancelar sin baja se rechaza');
-- Se puede volver a pedir y volver a cancelar
select public.adn_autoservicio_baja('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001', 'segunda vez');
select pg_temp.igual((public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001') -> 'baja' ->> 'cancelable'), 'true', 'una segunda baja también se puede cancelar');
-- Plazo vencido: ya no se cancela
update public.iglesias set borrado_programado_en = now() - interval '1 minute' where id = 'a9200000-0000-0000-0000-00000000000a';
select pg_temp.falla($$select public.adn_autoservicio_cancelar_baja('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001')$$, 'ADN_PLAZO_VENCIDO', 'con el plazo vencido no se cancela');
select pg_temp.igual((public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001') -> 'baja' ->> 'cancelable'), 'false', 'y el estado ya no lo ofrece');

-- 6. Una baja abierta por la plataforma no la cancela la iglesia, aunque su propietario lo intente
select public.adn_borrar_suave('a9200000-0000-0000-0000-00000000000b', 'a9100000-0000-0000-0000-0000000000f1', 'decisión de la plataforma');
select pg_temp.falla($$select public.adn_autoservicio_cancelar_baja('a9200000-0000-0000-0000-00000000000b', 'a9100000-0000-0000-0000-000000000003')$$, 'ADN_BAJA_DE_PLATAFORMA', 'la iglesia no cancela una baja de la plataforma');
select pg_temp.igual((public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000b', 'a9100000-0000-0000-0000-000000000003') -> 'baja' ->> 'por_la_iglesia'), 'false', 'el estado la marca como de la plataforma');
select pg_temp.igual((public.adn_autoservicio_estado('a9200000-0000-0000-0000-00000000000b', 'a9100000-0000-0000-0000-000000000003') -> 'baja' ->> 'cancelable'), 'false', 'y no cancelable');
select pg_temp.igual((select (adn_borrada_en is not null)::text from public.iglesias where id = 'a9200000-0000-0000-0000-00000000000b'), 'true', 'la baja de la plataforma sigue en pie');

-- 7. La auditoría solo se agrega y solo la lee el servidor
select pg_temp.falla($$set local role authenticated; select count(*) from public.adn_datos_auditoria$$, 'permission denied', 'una cuenta de iglesia no lee la auditoría de autoservicio');
reset role;
select pg_temp.falla($$set local role anon; select public.adn_autoservicio_baja('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001')$$, 'permission denied', 'sin sesión no se ejecuta la baja');
reset role;
select pg_temp.falla($$set local role authenticated; select public.adn_autoservicio_exportar('a9200000-0000-0000-0000-00000000000a', 'a9100000-0000-0000-0000-000000000001')$$, 'permission denied', 'ni con sesión desde el navegador: solo la función de borde');
reset role;
select pg_temp.falla($$set local role service_role; update public.adn_datos_auditoria set actor = actor$$, 'permission denied', 'ni el servidor edita la auditoría');
reset role;
select pg_temp.falla($$set local role service_role; delete from public.adn_datos_auditoria$$, 'permission denied', 'ni la borra');
reset role;
select pg_temp.falla($$insert into public.adn_datos_auditoria (iglesia_ref, accion, actor) values (gen_random_uuid(), 'otra', gen_random_uuid())$$, 'check', 'una acción desconocida no entra');
rollback;
