-- Purga programada: la tarea que purga lo vencido (simulada en SQL), el aviso de purga atrasada y que nada se purga antes de tiempo.
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
-- Ejecuta una sentencia y comprueba que falla con un texto concreto
create or replace function pg_temp.falla(sentencia text, texto text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if sqlerrm like '%' || texto || '%' then raise notice 'OK: %', msg; return; end if;
    raise exception 'FALLO: % (error inesperado: %)', msg, sqlerrm;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
grant execute on function pg_temp.falla(text, text, text) to authenticated, anon, service_role;


insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('a8100000-0000-0000-0000-00000000000a', 'Prueba Purga Viva', 'prueba-purga-viva', 'ES', 'Sevilla', 'premium'),
  ('a8100000-0000-0000-0000-00000000000b', 'Prueba Purga B', 'prueba-purga-b', 'ES', 'Sevilla', 'premium'),
  ('a8100000-0000-0000-0000-00000000000c', 'Prueba Purga C', 'prueba-purga-c', 'ES', 'Sevilla', 'premium'),
  ('a8100000-0000-0000-0000-00000000000d', 'Prueba Purga D', 'prueba-purga-d', 'ES', 'Sevilla', 'premium'),
  ('a8100000-0000-0000-0000-00000000000e', 'Prueba Purga E', 'prueba-purga-e', 'ES', 'Sevilla', 'premium'),
  ('a8100000-0000-0000-0000-00000000000f', 'Prueba Purga F', 'prueba-purga-f', 'ES', 'Sevilla', 'premium');
insert into public.miembros (iglesia_id, nombre, apellido, email) select id, 'M' || right(slug, 1), 'P', 'm@' || slug || '.test' from public.iglesias where slug like 'prueba-purga-%';

-- Todas se borran con el plazo fijo; despues se adelanta el reloj de unas pocas
select public.adn_borrar_suave(id, null, 'prueba') from public.iglesias where slug in ('prueba-purga-b', 'prueba-purga-c', 'prueba-purga-d', 'prueba-purga-e', 'prueba-purga-f');
select pg_temp.igual((select count(*)::text from public.iglesias where slug like 'prueba-purga-%' and borrado_programado_en between now() + interval '29 days 23 hours' and now() + interval '30 days 1 hour'), '5', 'el plazo del borrado suave es de 30 dias');
update public.iglesias set borrado_programado_en = now() - interval '1 hour' where slug = 'prueba-purga-b';
update public.iglesias set borrado_programado_en = now() - interval '3 days' where slug = 'prueba-purga-c';
update public.iglesias set borrado_programado_en = now() - interval '10 days' where slug = 'prueba-purga-d';

-- 1. Estado de la purga
select pg_temp.igual((public.adn_purga_estado() ->> 'en_borrado'), '5', 'cinco iglesias en borrado suave');
select pg_temp.igual((public.adn_purga_estado() ->> 'vencidas'), '3', 'tres con el plazo vencido');
select pg_temp.igual((public.adn_purga_estado() ->> 'horas_mas_atrasada'), '240', 'la mas atrasada lleva 240 horas esperando');
select pg_temp.igual((public.adn_purga_estado() ->> 'atrasada'), 'true', 'con el umbral de 48 horas se avisa de purga atrasada');
select pg_temp.igual((public.adn_purga_estado(500) ->> 'atrasada'), 'false', 'con un umbral de 500 horas no');
select pg_temp.igual((public.adn_purga_estado(null) ->> 'atrasada'), 'true', 'un umbral nulo usa 48 horas');
select pg_temp.igual((select string_agg(k, ',' order by k) from jsonb_object_keys(public.adn_purga_estado()) k), 'atrasada,en_borrado,horas_mas_atrasada,vencidas', 'solo devuelve cifras: ni nombres ni identificadores');
select pg_temp.igual((select string_agg(slug, ',' order by borrado_programado_en) from public.iglesias where id in (select public.adn_iglesias_vencidas())), 'prueba-purga-d,prueba-purga-c,prueba-purga-b', 'las vencidas salen por orden de antiguedad, la mas atrasada primero');

-- 2. La tarea programada, simulada: cada pasada toma un lote de las vencidas y purga cada una, como la funcion de borde
create temp table pasadas (n int, purgadas int);
do $$
declare lote constant int := 2; ids uuid[]; id uuid; n int := 0; hechas int;
begin
  loop
    select coalesce(array_agg(v), '{}') into ids from (select * from public.adn_iglesias_vencidas() v limit lote) q;
    exit when array_length(ids, 1) is null;
    n := n + 1; hechas := 0;
    foreach id in array ids loop perform public.adn_purgar_iglesia(id, null); hechas := hechas + 1; end loop;
    insert into pasadas values (n, hechas);
    exit when n > 10;
  end loop;
end $$;
select pg_temp.igual((select string_agg(purgadas::text, ',' order by n) from pasadas), '2,1', 'con lotes de 2, tres vencidas se purgan en dos pasadas');
select pg_temp.igual((select count(*)::text from public.iglesias where slug in ('prueba-purga-b', 'prueba-purga-c', 'prueba-purga-d')), '0', 'las vencidas han desaparecido');
select pg_temp.igual((select count(*)::text from public.miembros where email in ('m@prueba-purga-b.test', 'm@prueba-purga-c.test', 'm@prueba-purga-d.test')), '0', 'y con ellas sus datos');
select pg_temp.igual((select count(*)::text from public.iglesias where slug in ('prueba-purga-viva', 'prueba-purga-e', 'prueba-purga-f')), '3', 'una iglesia viva y dos con plazo sin vencer siguen intactas');
select pg_temp.igual((select count(*)::text from public.miembros where email in ('m@prueba-purga-viva.test', 'm@prueba-purga-e.test', 'm@prueba-purga-f.test')), '3', 'con sus datos');
select pg_temp.igual((select count(*)::text from public.adn_ciclo_auditoria where accion = 'purga' and iglesia_ref in ('a8100000-0000-0000-0000-00000000000b', 'a8100000-0000-0000-0000-00000000000c', 'a8100000-0000-0000-0000-00000000000d')), '3', 'la auditoria de las tres purgas sobrevive');
select pg_temp.igual((select count(*)::text from public.adn_ciclo_auditoria where iglesia_ref in ('a8100000-0000-0000-0000-00000000000b', 'a8100000-0000-0000-0000-00000000000c', 'a8100000-0000-0000-0000-00000000000d') and motivo is not null), '0', 'sin el texto libre del motivo');
select pg_temp.igual((public.adn_purga_estado() ->> 'vencidas'), '0', 'despues de la purga no queda nada vencido');
select pg_temp.igual((public.adn_purga_estado() ->> 'atrasada'), 'false', 'y no hay aviso de atraso');
select pg_temp.igual((select count(*)::text from public.adn_iglesias_vencidas()), '0', 'otra pasada no encuentra nada que purgar');

-- 3. Nada se purga antes de tiempo, y dentro del plazo se puede recuperar
select pg_temp.falla($$select public.adn_purgar_iglesia('a8100000-0000-0000-0000-00000000000e', null)$$, '', 'una iglesia con el plazo sin vencer no se puede purgar');
select pg_temp.igual((select count(*)::text from public.iglesias where slug = 'prueba-purga-e'), '1', 'y sigue existiendo');
select public.adn_recuperar_iglesia('a8100000-0000-0000-0000-00000000000f', null, 'prueba');
select pg_temp.igual((select (adn_borrada_en is null and borrado_programado_en is null)::text from public.iglesias where slug = 'prueba-purga-f'), 'true', 'dentro del plazo se recupera y se cancela la purga');
select pg_temp.igual((public.adn_purga_estado() ->> 'en_borrado'), '1', 'queda una sola en borrado suave');

-- 4. Si la tarea no corre, el aviso salta
update public.iglesias set borrado_programado_en = now() - interval '49 hours' where slug = 'prueba-purga-e';
select pg_temp.igual((public.adn_purga_estado() ->> 'atrasada'), 'true', 'una vencida que lleva 49 horas sin purgarse activa el aviso');
update public.iglesias set borrado_programado_en = now() - interval '47 hours' where slug = 'prueba-purga-e';
select pg_temp.igual((public.adn_purga_estado() ->> 'atrasada'), 'false', 'con 47 horas todavia no');

-- 5. Solo el servidor
set local role authenticated;
select pg_temp.falla($$select public.adn_purga_estado()$$, 'permission denied', 'una persona con sesion no consulta el estado de la purga');
reset role;
set local role anon;
select pg_temp.falla($$select public.adn_purga_estado()$$, 'permission denied', 'un visitante tampoco');
reset role;
set local role service_role;
select pg_temp.igual((public.adn_purga_estado() ->> 'en_borrado'), '1', 'el servidor si');
reset role;
rollback;
