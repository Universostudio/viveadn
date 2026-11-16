-- Agregados del Panel Maestro en SQL: dan lo mismo que contar las filas, respetan el interruptor de demostraciones y solo los ejecuta el servidor.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if exists (select 1 from public.iglesias where slug not like 'prueba-%') then raise exception 'Este script no se ejecuta en una base con iglesias reales'; end if;
end $$;
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
-- Iglesias: real activa, real en prueba, demo activa, y una real en borrado suave
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, etapa, activa, es_demo) values
  ('b6a10000-0000-0000-0000-000000000001', 'Agr Real', 'prueba-agr-real', 'ES', 'Sevilla', 'basico', 'activa', true, false),
  ('b6a10000-0000-0000-0000-000000000002', 'Agr Prueba', 'prueba-agr-prueba', 'ES', 'Sevilla', 'basico', 'prueba', true, false),
  ('b6a10000-0000-0000-0000-000000000003', 'Agr Demo', 'prueba-agr-demo', 'ES', 'Sevilla', 'basico', 'activa', true, true),
  ('b6a10000-0000-0000-0000-000000000004', 'Agr Borrada', 'prueba-agr-borrada', 'ES', 'Sevilla', 'basico', 'activa', true, false);
update public.iglesias set etapa = 'suspendida', activa = false, adn_borrada_en = now(), borrado_programado_en = now() + interval '20 days' where slug = 'prueba-agr-borrada';

-- Facturación: los grupos suman todas las iglesias y separan demo y borrada
select pg_temp.igual((select sum(n)::text from public.adn_plataforma_facturacion()), (select count(*)::text from public.iglesias), 'la facturación suma exactamente todas las iglesias');
select pg_temp.igual((select coalesce(sum(n), 0)::text from public.adn_plataforma_facturacion() where es_demo), '1', 'una demo');
select pg_temp.igual((select coalesce(sum(n), 0)::text from public.adn_plataforma_facturacion() where borrada), '1', 'una borrada');
select pg_temp.igual((select coalesce(sum(n), 0)::text from public.adn_plataforma_facturacion() where etapa = 'prueba' and not es_demo and not borrada), '1', 'una real en prueba');

-- Soporte: tickets de la iglesia real y de la demo
insert into auth.users (id) values ('b6a00000-0000-0000-0000-000000000001');
insert into public.adn_tickets (id, iglesia_id, asunto, prioridad, estado, creado_por, cerrado_en) values
  ('b6a20000-0000-0000-0000-000000000001', 'b6a10000-0000-0000-0000-000000000001', 'Real abierto', 'urgente', 'abierto', 'b6a00000-0000-0000-0000-000000000001', null),
  ('b6a20000-0000-0000-0000-000000000002', 'b6a10000-0000-0000-0000-000000000003', 'Demo abierto', 'urgente', 'abierto', 'b6a00000-0000-0000-0000-000000000001', null),
  ('b6a20000-0000-0000-0000-000000000003', 'b6a10000-0000-0000-0000-000000000001', 'Real cerrado', 'normal', 'cerrado', 'b6a00000-0000-0000-0000-000000000001', now());
select pg_temp.igual((select tickets_abiertos::text from public.adn_soporte_resumen(true)), '2', 'con demos: dos abiertos');
select pg_temp.igual((select tickets_abiertos::text from public.adn_soporte_resumen(false)), '1', 'sin demos: uno');
select pg_temp.igual((select tickets_urgentes::text from public.adn_soporte_resumen(false)), '1', 'sin demos: un urgente');
select pg_temp.igual((select tickets_cerrados::text from public.adn_soporte_resumen(true)), '1', 'un cerrado');
select pg_temp.igual((select tickets_abiertos::text from public.adn_soporte_resumen()), '2', 'por defecto cuentan todas');

-- Avisos: entregas a la iglesia real (leída) y a la demo (descartada)
insert into public.adn_avisos (id, tipo, titulo, texto, destino, desde) values ('b6a30000-0000-0000-0000-000000000001', 'alerta', 'Aviso', 'Texto', '{"todas": true}', now() - interval '1 hour');
insert into public.adn_avisos_entregas (aviso_id, iglesia_id, leido_en, descartado_en) values
  ('b6a30000-0000-0000-0000-000000000001', 'b6a10000-0000-0000-0000-000000000001', now(), null),
  ('b6a30000-0000-0000-0000-000000000001', 'b6a10000-0000-0000-0000-000000000003', null, now());
select pg_temp.igual((select avisos_vigentes::text from public.adn_soporte_resumen(true)), '1', 'un aviso vigente');
select pg_temp.igual((select entregas || '/' || leidos || '/' || descartados from public.adn_soporte_resumen(true)), '2/1/1', 'con demos: 2 entregas, 1 leída, 1 descartada');
select pg_temp.igual((select entregas || '/' || leidos || '/' || descartados from public.adn_soporte_resumen(false)), '1/1/0', 'sin demos: solo la entrega a la iglesia real');
select pg_temp.igual((select entregas || '/' || leidos || '/' || descartados from public.adn_avisos_estadisticas(array['b6a30000-0000-0000-0000-000000000001']::uuid[])), '2/1/1', 'estadísticas del aviso pedido');
select pg_temp.igual((select count(*)::text from public.adn_avisos_estadisticas(array[]::uuid[])), '0', 'sin avisos pedidos no hay filas');
select pg_temp.igual((select count(*)::text from public.adn_avisos_estadisticas(null)), '0', 'null tampoco');

-- Novedades
select pg_temp.igual((select novedades_total::text from public.adn_soporte_resumen()), (select count(*)::text from public.adn_novedades where retirada_en is null), 'novedades vigentes');

-- Solo el servidor: ni anónimos ni usuarios las ejecutan
select pg_temp.igual((has_function_privilege('anon', 'public.adn_plataforma_facturacion()', 'execute') or has_function_privilege('authenticated', 'public.adn_plataforma_facturacion()', 'execute'))::text, 'false', 'facturación: sin permiso para anon ni authenticated');
select pg_temp.igual((has_function_privilege('anon', 'public.adn_soporte_resumen(boolean)', 'execute') or has_function_privilege('authenticated', 'public.adn_soporte_resumen(boolean)', 'execute'))::text, 'false', 'soporte: sin permiso para anon ni authenticated');
select pg_temp.igual((has_function_privilege('anon', 'public.adn_avisos_estadisticas(uuid[])', 'execute') or has_function_privilege('authenticated', 'public.adn_avisos_estadisticas(uuid[])', 'execute'))::text, 'false', 'avisos: sin permiso para anon ni authenticated');
select pg_temp.igual((has_function_privilege('service_role', 'public.adn_soporte_resumen(boolean)', 'execute'))::text, 'true', 'el servidor sí las ejecuta');
rollback;
