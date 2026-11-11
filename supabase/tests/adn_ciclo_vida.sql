-- Pruebas del borrado suave con plazo de 30 dias, la recuperacion, la purga y su auditoria.
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

insert into auth.users (id) values
  ('ad000000-0000-0000-0000-000000000001'), ('ad000000-0000-0000-0000-000000000002'),
  ('ad000000-0000-0000-0000-000000000003'), ('ad000000-0000-0000-0000-000000000004'),
  ('ad000000-0000-0000-0000-0000000000f1');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ad100000-0000-0000-0000-00000000000a', 'Prueba Suave A', 'prueba-suave-a', 'ES', 'Sevilla', 'premium'),
  ('ad100000-0000-0000-0000-00000000000b', 'Prueba Suave B', 'prueba-suave-b', 'ES', 'Sevilla', 'premium'),
  ('ad100000-0000-0000-0000-00000000000c', 'Prueba Suave C', 'prueba-suave-c', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('ad000000-0000-0000-0000-000000000001', 'ad100000-0000-0000-0000-00000000000a', 'P1', 'A', 'p1@prueba.test', 'propietario', true),
  ('ad000000-0000-0000-0000-000000000002', 'ad100000-0000-0000-0000-00000000000a', 'Adm', 'A', 'adm@prueba.test', 'administrador', true),
  ('ad000000-0000-0000-0000-000000000003', 'ad100000-0000-0000-0000-00000000000b', 'P1', 'B', 'pb@prueba.test', 'propietario', true),
  ('ad000000-0000-0000-0000-000000000004', 'ad100000-0000-0000-0000-00000000000c', 'P1', 'C', 'pc@prueba.test', 'propietario', true);
-- El segundo usuario de A tambien es administrador de plataforma: su cuenta no se retira
insert into public.plataforma_admins (user_id) values ('ad000000-0000-0000-0000-000000000002');
insert into public.miembros (iglesia_id, nombre, apellido) values
  ('ad100000-0000-0000-0000-00000000000a', 'M1', 'A'), ('ad100000-0000-0000-0000-00000000000a', 'M2', 'A'),
  ('ad100000-0000-0000-0000-00000000000b', 'M1', 'B');

-- 1. Borrado suave de una iglesia activa
create temp table plazo as select public.adn_borrar_suave('ad100000-0000-0000-0000-00000000000a', 'ad000000-0000-0000-0000-0000000000f1', 'cierre pedido por la iglesia') p;
select pg_temp.igual((select (p between now() + interval '29 days 23 hours' and now() + interval '30 days 1 hour')::text from plazo), 'true', 'el plazo de gracia es de 30 dias');
select pg_temp.igual((select etapa from public.iglesias where slug = 'prueba-suave-a'), 'suspendida', 'el borrado suave deja la iglesia suspendida');
select pg_temp.igual((select activa::text from public.iglesias where slug = 'prueba-suave-a'), 'false', 'la iglesia deja de estar activa');
select pg_temp.igual((select (borrado_programado_en = (select p from plazo))::text from public.iglesias where slug = 'prueba-suave-a'), 'true', 'la purga queda programada al fin del plazo');
select pg_temp.igual((select adn_estado_previo ->> 'etapa' from public.iglesias where slug = 'prueba-suave-a'), 'activa', 'guarda la etapa previa');
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = 'ad100000-0000-0000-0000-00000000000a'), '2', 'el borrado suave no toca los datos');
select pg_temp.igual((select count(*)::text from public.adn_ciclo_auditoria where iglesia_ref = 'ad100000-0000-0000-0000-00000000000a' and accion = 'borrado_suave' and actor = 'ad000000-0000-0000-0000-0000000000f1' and motivo is not null), '1', 'queda auditado con actor y motivo');
select pg_temp.falla($$select public.adn_borrar_suave('ad100000-0000-0000-0000-00000000000a', null)$$, 'ADN_YA_BORRADA', 'no se borra dos veces');
select pg_temp.falla($$select public.adn_borrar_suave('ad1000ff-0000-0000-0000-00000000000a', null)$$, 'no existe', 'una iglesia inexistente se rechaza');

-- El acceso queda cortado en la propia base
select set_config('request.jwt.claim.sub', 'ad000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select private.tiene_modulo('miembros')::text), 'false', 'una iglesia en borrado suave no tiene modulos');
select pg_temp.igual((select count(*)::text from public.miembros), '0', 'sus usuarios ya no leen sus miembros');
-- y quien la configura no puede ni editar la fila de una iglesia suspendida: la politica no le deja ninguna fila
do $$ declare n int; begin
  update public.iglesias set adn_borrada_en = null, borrado_programado_en = null where slug = 'prueba-suave-a';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO: el propietario pudo editar una iglesia en borrado suave'; end if;
  raise notice 'OK: el propietario no puede cancelar el borrado suave de su iglesia';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);
-- En una iglesia activa, la guarda rechaza que su propietario toque las marcas
select set_config('request.jwt.claim.sub', 'ad000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.falla($$update public.iglesias set adn_borrada_en = now() where slug = 'prueba-suave-c'$$, 'solo los cambia la plataforma', 'el propietario no marca su iglesia como borrada');
select pg_temp.falla($$update public.iglesias set adn_estado_previo = '{}'::jsonb where slug = 'prueba-suave-c'$$, 'solo los cambia la plataforma', 'el propietario no escribe el estado previo');
select pg_temp.falla($$update public.iglesias set adn_borrada_por = null, borrado_programado_en = now() where slug = 'prueba-suave-c'$$, 'solo los cambia la plataforma', 'el propietario no programa el borrado');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- 2. No se puede cancelar el plazo a mano estando en borrado suave: hay que recuperar
select pg_temp.falla($$update public.iglesias set borrado_programado_en = null where slug = 'prueba-suave-a'$$, 'adn_iglesias_borrada_check', 'sin plazo no hay borrado suave coherente');

-- 3. Recuperacion dentro del plazo
select pg_temp.igual(public.adn_recuperar_iglesia('ad100000-0000-0000-0000-00000000000a', 'ad000000-0000-0000-0000-0000000000f1', 'se arrepintieron'), 'activa', 'recuperar devuelve la etapa previa');
select pg_temp.igual((select activa::text from public.iglesias where slug = 'prueba-suave-a'), 'true', 'la iglesia vuelve a estar activa');
select pg_temp.igual((select (borrado_programado_en is null and adn_borrada_en is null and adn_estado_previo is null)::text from public.iglesias where slug = 'prueba-suave-a'), 'true', 'la recuperacion cancela el plazo y limpia las marcas');
select pg_temp.igual((select count(*)::text from public.adn_ciclo_auditoria where iglesia_ref = 'ad100000-0000-0000-0000-00000000000a' and accion = 'recuperacion'), '1', 'la recuperacion queda auditada');
select set_config('request.jwt.claim.sub', 'ad000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.miembros), '2', 'tras recuperar, sus usuarios vuelven a leer sus miembros');
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.falla($$select public.adn_recuperar_iglesia('ad100000-0000-0000-0000-00000000000a', null)$$, 'ADN_NO_BORRADA', 'no se recupera una iglesia que no esta borrada');

-- 4. Una prueba en curso vuelve con su fecha, y una iglesia en receso vuelve a receso
update public.iglesias set etapa = 'prueba', prueba_hasta = '2030-01-15 10:00:00+00' where slug = 'prueba-suave-b';
select public.adn_borrar_suave('ad100000-0000-0000-0000-00000000000b', null);
select pg_temp.igual((select etapa from public.iglesias where slug = 'prueba-suave-b'), 'suspendida', 'una iglesia en prueba tambien se suspende');
select public.adn_recuperar_iglesia('ad100000-0000-0000-0000-00000000000b', null);
select pg_temp.igual((select etapa || ' ' || prueba_hasta::text from public.iglesias where slug = 'prueba-suave-b'), 'prueba 2030-01-15 10:00:00+00', 'la prueba recupera su fecha exacta');
update public.iglesias set etapa = 'receso' where slug = 'prueba-suave-b';
select public.adn_borrar_suave('ad100000-0000-0000-0000-00000000000b', null);
select pg_temp.igual(public.adn_recuperar_iglesia('ad100000-0000-0000-0000-00000000000b', null), 'receso', 'una iglesia en receso vuelve a receso');
select pg_temp.igual((select (adn_borrada_en is null and borrado_programado_en is null)::text from public.iglesias where slug = 'prueba-suave-b'), 'true', 'y sin marcas de borrado');
update public.iglesias set etapa = 'activa' where slug = 'prueba-suave-b';

-- 5. Cambiar la etapa por la via normal tambien limpia las marcas
select public.adn_borrar_suave('ad100000-0000-0000-0000-00000000000b', null);
update public.iglesias set etapa = 'activa' where slug = 'prueba-suave-b';
select pg_temp.igual((select (adn_borrada_en is null and adn_estado_previo is null and borrado_programado_en is null and activa)::text from public.iglesias where slug = 'prueba-suave-b'), 'true', 'salir de suspendida limpia las marcas del borrado suave');
-- ni siquiera cambiar solo `activa` deja una iglesia activa con marcas
select public.adn_borrar_suave('ad100000-0000-0000-0000-00000000000b', null);
update public.iglesias set activa = true where slug = 'prueba-suave-b';
select pg_temp.igual((select (adn_borrada_en is null and activa)::text from public.iglesias where slug = 'prueba-suave-b'), 'true', 'reactivar con la columna activa tambien limpia las marcas');

-- 6. Purga: nada antes de tiempo, y pasado el plazo ya no se recupera
select public.adn_borrar_suave('ad100000-0000-0000-0000-00000000000a', 'ad000000-0000-0000-0000-0000000000f1', 'segundo intento');
select pg_temp.falla($$select public.adn_purgar_iglesia('ad100000-0000-0000-0000-00000000000a', null)$$, 'BORRADO_NO_VENCIDO', 'no se purga dentro del plazo');
select pg_temp.falla($$select public.adn_purgar_iglesia('ad100000-0000-0000-0000-00000000000c', null)$$, 'ADN_NO_BORRADA', 'no se purga una iglesia que no esta en borrado suave');
select pg_temp.igual((select count(*)::text from public.adn_iglesias_vencidas() id), '0', 'dentro del plazo no hay vencidas');
update public.iglesias set borrado_programado_en = now() - interval '1 minute' where slug = 'prueba-suave-a';
select pg_temp.igual((select string_agg(id::text, ',') from public.adn_iglesias_vencidas() id), 'ad100000-0000-0000-0000-00000000000a', 'solo la iglesia vencida aparece como vencida');
select pg_temp.falla($$select public.adn_recuperar_iglesia('ad100000-0000-0000-0000-00000000000a', null)$$, 'ADN_PLAZO_VENCIDO', 'pasado el plazo ya no se recupera');

create temp table retirar as select public.adn_purgar_iglesia('ad100000-0000-0000-0000-00000000000a', 'ad000000-0000-0000-0000-0000000000f1') u;
select pg_temp.igual((select count(*)::text from public.iglesias where id = 'ad100000-0000-0000-0000-00000000000a'), '0', 'la purga borra la iglesia');
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = 'ad100000-0000-0000-0000-00000000000a'), '0', 'la purga borra sus miembros');
select pg_temp.igual((select count(*)::text from public.perfiles where iglesia_id = 'ad100000-0000-0000-0000-00000000000a'), '0', 'la purga borra sus perfiles');
select pg_temp.igual((select u::text from retirar), '{ad000000-0000-0000-0000-000000000001}', 'devuelve las cuentas a retirar de Auth, sin las de plataforma');
-- La auditoria sobrevive, sin datos de personas ni motivos
select pg_temp.igual((select string_agg(accion, ',' order by id) from public.adn_ciclo_auditoria where iglesia_ref = 'ad100000-0000-0000-0000-00000000000a'),
  'borrado_suave,recuperacion,borrado_suave,purga', 'la auditoria completa sobrevive a la purga');
select pg_temp.igual((select count(*)::text from public.adn_ciclo_auditoria where iglesia_ref = 'ad100000-0000-0000-0000-00000000000a' and motivo is not null), '0', 'la purga anula los motivos de texto libre');
select pg_temp.igual((select detalle::text from public.adn_ciclo_auditoria where iglesia_ref = 'ad100000-0000-0000-0000-00000000000a' and accion = 'purga'),
  '{"miembros_borrados": 2, "usuarios_a_retirar": 1}', 'la purga deja solo conteos');
select pg_temp.igual((select (s::text ~ '(@|prueba-suave|M1|Prueba Suave)')::text from (select jsonb_agg(to_jsonb(a)) s from public.adn_ciclo_auditoria a where iglesia_ref = 'ad100000-0000-0000-0000-00000000000a') x), 'false', 'la auditoria no contiene correos, nombres ni direccion de la iglesia');

-- 7. Aislamiento: lo anterior no toco a las otras iglesias
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = 'ad100000-0000-0000-0000-00000000000b'), '1', 'la iglesia B conserva sus miembros');
select pg_temp.igual((select activa::text from public.iglesias where slug = 'prueba-suave-c'), 'true', 'la iglesia C sigue activa');

-- 8. Privilegios: nadie salvo service_role ejecuta las funciones ni lee la auditoria
set local role authenticated;
select pg_temp.falla($$select public.adn_borrar_suave('ad100000-0000-0000-0000-00000000000c', null)$$, 'permission denied', 'un usuario autenticado no puede borrar');
select pg_temp.falla($$select public.adn_recuperar_iglesia('ad100000-0000-0000-0000-00000000000c', null)$$, 'permission denied', 'un usuario autenticado no puede recuperar');
select pg_temp.falla($$select public.adn_purgar_iglesia('ad100000-0000-0000-0000-00000000000c', null)$$, 'permission denied', 'un usuario autenticado no puede purgar');
select pg_temp.falla($$select * from public.adn_ciclo_auditoria$$, 'permission denied', 'un usuario autenticado no lee la auditoria');
reset role;
set local role anon;
select pg_temp.falla($$select public.adn_borrar_suave('ad100000-0000-0000-0000-00000000000c', null)$$, 'permission denied', 'un visitante no puede borrar');
select pg_temp.falla($$select * from public.adn_ciclo_auditoria$$, 'permission denied', 'un visitante no lee la auditoria');
reset role;
set local role service_role;
select pg_temp.falla($$delete from public.adn_ciclo_auditoria$$, 'permission denied', 'ni el servidor borra filas de la auditoria');
select pg_temp.falla($$update public.adn_ciclo_auditoria set accion = 'purga'$$, 'permission denied', 'ni el servidor edita la auditoria, solo anula motivos');
reset role;
rollback;
