-- Libro externo de purgas: exportarlo desde la auditoría y, tras una restauración que devuelve iglesias ya purgadas, volver a purgarlas.
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

insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('a8200000-0000-0000-0000-00000000000a', 'Prueba Libro A', 'prueba-libro-a', 'ES', 'Sevilla', 'premium'),
  ('a8200000-0000-0000-0000-00000000000b', 'Prueba Libro B', 'prueba-libro-b', 'ES', 'Sevilla', 'premium'),
  ('a8200000-0000-0000-0000-00000000000c', 'Prueba Libro C', 'prueba-libro-c', 'ES', 'Sevilla', 'premium'),
  ('a8200000-0000-0000-0000-00000000000d', 'Prueba Libro D viva', 'prueba-libro-d', 'ES', 'Sevilla', 'premium');
insert into public.miembros (iglesia_id, nombre, apellido, email) select id, 'M' || right(slug, 1), 'P', 'm@' || slug || '.test' from public.iglesias where slug like 'prueba-libro-%';

-- 1. El libro empieza vacío para estas iglesias, y registra cada purga con su fecha
select pg_temp.igual((select count(*)::text from public.adn_purgas_desde() where iglesia_ref::text like 'a8200000%'), '0', 'sin purgas, el libro no tiene nada de estas iglesias');
select public.adn_borrar_suave(id, null, 'prueba') from public.iglesias where slug in ('prueba-libro-a', 'prueba-libro-b');
update public.iglesias set borrado_programado_en = now() - interval '2 hours' where slug = 'prueba-libro-a';
update public.iglesias set borrado_programado_en = now() - interval '1 hour' where slug = 'prueba-libro-b';
select public.adn_purgar_iglesia('a8200000-0000-0000-0000-00000000000a', null);
select pg_temp.igual((select count(*)::text from public.adn_purgas_desde() where iglesia_ref::text like 'a8200000%'), '1', 'una purga, una fila en el libro');
select public.adn_purgar_iglesia('a8200000-0000-0000-0000-00000000000b', null);
select pg_temp.igual((select string_agg(right(iglesia_ref::text, 1), ',' order by purgada_en, iglesia_ref) from public.adn_purgas_desde() where iglesia_ref::text like 'a8200000%'), 'a,b', 'el libro sale por orden de purga');
select pg_temp.igual((select string_agg(k, ',' order by k) from jsonb_object_keys((select to_jsonb(p) from public.adn_purgas_desde() p limit 1)) k), 'iglesia_ref,purgada_en', 'el libro solo lleva identificador y fecha: ningun dato de personas ni de iglesias');
select pg_temp.igual((select count(*)::text from public.adn_purgas_desde(now() + interval '1 minute')), '0', 'desde una fecha futura no hay nada');
select pg_temp.igual((select count(*)::text from public.adn_purgas_desde((select min(purgada_en) from public.adn_purgas_desde() where iglesia_ref::text like 'a8200000%')) where iglesia_ref::text like 'a8200000%'), '2', 'desde la primera fecha (incluida) salen las dos');
select pg_temp.igual((select count(*)::text from public.adn_purgas_desde() where iglesia_ref = 'a8200000-0000-0000-0000-00000000000d'), '0', 'una iglesia viva no aparece en el libro');
-- Guardar el libro "fuera" de la base: una tabla temporal hace de archivo externo
create temp table libro_externo as select iglesia_ref, purgada_en from public.adn_purgas_desde() where iglesia_ref::text like 'a8200000%';

-- 2. Se simula una restauración anterior a las purgas: las dos iglesias reaparecen, vivas y con sus datos, y se añade una que nunca se purgó
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('a8200000-0000-0000-0000-00000000000a', 'Prueba Libro A', 'prueba-libro-a', 'ES', 'Sevilla', 'premium'),
  ('a8200000-0000-0000-0000-00000000000b', 'Prueba Libro B', 'prueba-libro-b', 'ES', 'Sevilla', 'premium');
insert into public.miembros (iglesia_id, nombre, apellido, email) select id, 'M' || right(slug, 1), 'P', 'm@' || slug || '.test' from public.iglesias where slug in ('prueba-libro-a', 'prueba-libro-b');
select pg_temp.igual((select count(*)::text from public.iglesias where slug in ('prueba-libro-a', 'prueba-libro-b')), '2', 'la restauracion devuelve las dos iglesias purgadas');
select pg_temp.igual((select count(*)::text from public.adn_iglesias_vencidas()), '0', 'y la purga normal no sabe que sobran');

-- 3. La re-purga con el libro
select pg_temp.falla($$select public.adn_repurgar_registradas(null, null)$$, 'ADN_LISTA_INVALIDA', 'una lista nula se rechaza');
select pg_temp.falla($$select public.adn_repurgar_registradas(array(select gen_random_uuid() from generate_series(1, 5001)), null)$$, 'ADN_LISTA_INVALIDA', 'una lista enorme se rechaza');
select pg_temp.igual((select cardinality(public.adn_repurgar_registradas(array['a8200000-0000-0000-0000-00000000000a', 'a8200000-0000-0000-0000-00000000000b', 'a8200000-0000-0000-0000-0000000000ff']::uuid[], null))::text), '2', 'marca las dos que reaparecen e ignora la que ya no existe');
select pg_temp.igual((select count(*)::text from public.iglesias where slug in ('prueba-libro-a', 'prueba-libro-b')), '2', 'marcar no borra nada: eso lo hace la purga normal');
select pg_temp.igual((select count(*)::text from public.adn_iglesias_vencidas()), '2', 'ahora la purga normal las ve vencidas');
select pg_temp.igual((public.adn_purga_estado() ->> 'vencidas'), '2', 'y el estado de la purga las cuenta');
select pg_temp.igual((select count(*)::text from public.adn_ciclo_auditoria where accion = 'borrado_suave' and detalle ->> 'origen' = 'libro_externo' and iglesia_ref::text like 'a8200000%'), '2', 'queda auditado que el origen fue el libro externo');
select pg_temp.igual((select count(*)::text from public.iglesias where slug = 'prueba-libro-d' and adn_borrada_en is null), '1', 'una iglesia viva que no esta en el libro no se toca');
do $$ declare v uuid; begin
  for v in select public.adn_iglesias_vencidas() loop perform public.adn_purgar_iglesia(v, null); end loop;
end $$;
select pg_temp.igual((select count(*)::text from public.iglesias where slug in ('prueba-libro-a', 'prueba-libro-b')), '0', 'la purga normal las elimina otra vez');
select pg_temp.igual((select count(*)::text from public.miembros where email in ('m@prueba-libro-a.test', 'm@prueba-libro-b.test')), '0', 'con sus datos');
select pg_temp.igual((select count(*)::text from public.miembros where email = 'm@prueba-libro-d.test'), '1', 'y la iglesia viva conserva los suyos');
select pg_temp.igual((select count(*)::text from public.adn_iglesias_vencidas()), '0', 'no queda nada vencido');
select pg_temp.igual((select cardinality(public.adn_repurgar_registradas((select array_agg(iglesia_ref) from libro_externo), null))::text), '0', 'repetir la re-purga con el libro entero es inocuo: ya no queda nada que marcar');

-- 4. Solo el servidor
set local role authenticated;
select pg_temp.falla($$select * from public.adn_purgas_desde()$$, 'permission denied', 'una persona con sesion no lee el libro');
select pg_temp.falla($$select public.adn_repurgar_registradas('{}'::uuid[], null)$$, 'permission denied', 'ni lo aplica');
reset role;
set local role anon;
select pg_temp.falla($$select * from public.adn_purgas_desde()$$, 'permission denied', 'un visitante tampoco lo lee');
select pg_temp.falla($$select public.adn_repurgar_registradas('{}'::uuid[], null)$$, 'permission denied', 'ni lo aplica');
reset role;
set local role service_role;
select pg_temp.igual((select count(distinct iglesia_ref)::text from public.adn_purgas_desde() where iglesia_ref::text like 'a8200000%'), '2', 'el servidor si lee el libro (dos iglesias, cada una purgada dos veces)');
reset role;
rollback;
