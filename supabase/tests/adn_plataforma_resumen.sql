-- Panel Maestro: lecturas agregadas sin datos de personas, límites, orden y privilegios.
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

insert into auth.users (id) values ('a9300000-0000-0000-0000-000000000001'), ('a9300000-0000-0000-0000-000000000002');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, created_at) values
  ('a9400000-0000-0000-0000-00000000000a', 'Prueba Resumen A', 'prueba-resumen-a', 'ES', 'Sevilla', 'premium', now() - interval '3 days'),
  ('a9400000-0000-0000-0000-00000000000b', 'Prueba Resumen B', 'prueba-resumen-b', 'ES', 'Sevilla', 'premium', now() - interval '2 days'),
  ('a9400000-0000-0000-0000-00000000000c', 'Prueba Resumen C', 'prueba-resumen-c', 'ES', 'Sevilla', 'premium', now() - interval '1 day');
set local session_replication_role = replica;
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('a9300000-0000-0000-0000-000000000001', 'a9400000-0000-0000-0000-00000000000a', 'Pro', 'Pietario', 'p@resumen-a.test', 'propietario', true),
  ('a9300000-0000-0000-0000-000000000002', 'a9400000-0000-0000-0000-00000000000a', 'Adm', 'Inistra', 'a@resumen-a.test', 'administrador', true);
reset session_replication_role;
insert into public.miembros (id, iglesia_id, nombre, apellido, created_at, activo)
  select gen_random_uuid(), 'a9400000-0000-0000-0000-00000000000a', 'M' || g, 'A', now(), true from generate_series(1, 5) g;
insert into public.miembros (id, iglesia_id, nombre, apellido, created_at, activo)
  select gen_random_uuid(), 'a9400000-0000-0000-0000-00000000000b', 'M' || g, 'B', now(), true from generate_series(1, 2) g;

-- 1. Resumen: una fila por iglesia con sus conteos; las iglesias sin datos salen con ceros
select pg_temp.igual((select miembros::text || '/' || usuarios::text from public.adn_plataforma_resumen() where iglesia_id = 'a9400000-0000-0000-0000-00000000000a'), '5/2', 'conteo de miembros y usuarios de A');
select pg_temp.igual((select miembros::text || '/' || usuarios::text from public.adn_plataforma_resumen() where iglesia_id = 'a9400000-0000-0000-0000-00000000000b'), '2/0', 'B tiene miembros y ningún usuario');
select pg_temp.igual((select miembros::text || '/' || usuarios::text from public.adn_plataforma_resumen() where iglesia_id = 'a9400000-0000-0000-0000-00000000000c'), '0/0', 'una iglesia vacía sale con ceros, no desaparece');
select pg_temp.igual((select count(*)::text from public.adn_plataforma_resumen()), (select count(*)::text from public.iglesias), 'exactamente una fila por iglesia');
select pg_temp.igual((select (sum(miembros))::text from public.adn_plataforma_resumen()), (select count(*)::text from public.miembros), 'la suma de miembros coincide con el total real');

-- 2. Privacidad: solo estas columnas, y ningún valor de las filas contiene datos de personas sembrados arriba
select pg_temp.igual((select string_agg(k, ',' order by k) from (select distinct jsonb_object_keys(to_jsonb(r)) k from public.adn_plataforma_resumen() r) s), 'iglesia_id,miembros,usuarios', 'el resumen solo devuelve identificador y dos números');
select pg_temp.igual((select string_agg(k, ',' order by k) from (select distinct jsonb_object_keys(to_jsonb(r)) k from public.adn_plataforma_actividad(100) r) s), 'accion,fecha,iglesia_id,iglesia_nombre,tipo', 'la actividad no tiene columna de detalle ni de personas');

-- 3. Actividad: altas y acciones juntas, de más reciente a más antigua, sin el detalle de la auditoría
insert into public.plataforma_auditoria (actor, accion, iglesia_id, detalle, created_at) values
  (null, 'cambiar_plan', 'a9400000-0000-0000-0000-00000000000a', '{"email":"secreto@persona.test","telefono":"600000000"}', now() - interval '2 hours'),
  (null, 'etapa_iglesia', 'a9400000-0000-0000-0000-00000000000b', '{"nota":"dato personal"}', now() - interval '1 hour'),
  (null, 'crear_iglesia', 'a9400000-0000-0000-0000-00000000000c', '{}', now() - interval '1 day'),
  (null, 'registro_ajustes', null, '{}', now() - interval '30 minutes');
select pg_temp.igual((select tipo || ':' || accion from public.adn_plataforma_actividad(100) limit 1), 'accion:registro_ajustes', 'lo más reciente va primero');
select pg_temp.igual((select string_agg(tipo || ':' || accion, ' ' order by fecha desc, tipo, accion) from (select * from public.adn_plataforma_actividad(4)) s), 'accion:registro_ajustes accion:etapa_iglesia accion:cambiar_plan alta:crear_iglesia', 'el orden es por fecha descendente');
select pg_temp.igual((select count(*)::text from public.adn_plataforma_actividad(100) where accion = 'crear_iglesia' and tipo = 'accion'), '0', 'la alta no se repite como acción');
select pg_temp.igual((select count(*)::text from public.adn_plataforma_actividad(100) where accion = 'crear_iglesia' and tipo = 'alta'), (select count(*)::text from public.iglesias), 'cada iglesia aparece una vez como alta');
select pg_temp.igual((select count(*)::text from public.adn_plataforma_actividad(2)), '2', 'respeta el límite');
select pg_temp.igual((select count(*)::text from public.adn_plataforma_actividad(0)), '1', 'un límite de 0 se sube a 1');
select pg_temp.igual((select count(*)::text from public.adn_plataforma_actividad(null)), (select least(20, count(*))::text from public.adn_plataforma_actividad(100)), 'sin límite usa 20');
select pg_temp.igual((select count(*)::text from public.adn_plataforma_actividad(100000)), (select least(100, (select count(*) from public.iglesias) + (select count(*) from public.plataforma_auditoria where accion <> 'crear_iglesia'))::text), 'un límite enorme se recorta a 100');
select pg_temp.igual((select iglesia_nombre from public.adn_plataforma_actividad(100) where accion = 'cambiar_plan'), 'Prueba Resumen A', 'la acción lleva el nombre de la iglesia');
select pg_temp.igual((select coalesce(iglesia_nombre, 'sin iglesia') from public.adn_plataforma_actividad(100) where accion = 'registro_ajustes'), 'sin iglesia', 'una acción de plataforma sin iglesia sale sin nombre');
-- El detalle sembrado con datos personales no aparece en ninguna salida
select pg_temp.igual((select count(*)::text from (select to_jsonb(r)::text t from public.adn_plataforma_actividad(100) r union all select to_jsonb(r)::text from public.adn_plataforma_historial('a9400000-0000-0000-0000-00000000000a', 50) r) s where t like '%secreto%' or t like '%600000000%' or t like '%dato personal%'), '0', 'el detalle de la auditoría nunca sale');

-- 4. Historial de una iglesia
select pg_temp.igual((select string_agg(k, ',' order by k) from (select distinct jsonb_object_keys(to_jsonb(r)) k from public.adn_plataforma_historial('a9400000-0000-0000-0000-00000000000a', 50) r) s), 'accion,fecha', 'el historial solo devuelve acción y fecha');
select pg_temp.igual((select string_agg(accion, ',' order by fecha desc) from public.adn_plataforma_historial('a9400000-0000-0000-0000-00000000000a', 50)), 'cambiar_plan', 'el historial de A tiene su acción');
select pg_temp.igual((select count(*)::text from public.adn_plataforma_historial('a9400000-0000-0000-0000-00000000000b', 50)), '1', 'el de B tiene la suya y no la de A');
select pg_temp.igual((select count(*)::text from public.adn_plataforma_historial(null, 50)), '0', 'sin iglesia no devuelve nada (no mezcla acciones sin iglesia)');
select pg_temp.igual((select count(*)::text from public.adn_plataforma_historial('a9400000-0000-0000-0000-0000000000ee', 50)), '0', 'una iglesia inexistente no devuelve nada');
insert into public.plataforma_auditoria (actor, accion, iglesia_id, detalle, created_at)
  select null, 'cambiar_plan', 'a9400000-0000-0000-0000-00000000000a', '{}', now() - (g || ' minutes')::interval from generate_series(1, 250) g;
select pg_temp.igual((select count(*)::text from public.adn_plataforma_historial('a9400000-0000-0000-0000-00000000000a', 100000)), '200', 'el historial se recorta a 200');
select pg_temp.igual((select count(*)::text from public.adn_plataforma_historial('a9400000-0000-0000-0000-00000000000a', 3)), '3', 'y respeta un límite menor');

-- 5. Privilegios: solo el servidor las ejecuta
select pg_temp.igual(has_function_privilege('anon', 'public.adn_plataforma_resumen()', 'execute')::text, 'false', 'anon no ejecuta el resumen');
select pg_temp.igual(has_function_privilege('authenticated', 'public.adn_plataforma_resumen()', 'execute')::text, 'false', 'un usuario con sesión no ejecuta el resumen');
select pg_temp.igual(has_function_privilege('service_role', 'public.adn_plataforma_resumen()', 'execute')::text, 'true', 'el servidor sí');
select pg_temp.igual(has_function_privilege('anon', 'public.adn_plataforma_actividad(integer)', 'execute')::text, 'false', 'anon no ejecuta la actividad');
select pg_temp.igual(has_function_privilege('authenticated', 'public.adn_plataforma_actividad(integer)', 'execute')::text, 'false', 'un usuario con sesión no ejecuta la actividad');
select pg_temp.igual(has_function_privilege('service_role', 'public.adn_plataforma_actividad(integer)', 'execute')::text, 'true', 'el servidor sí ejecuta la actividad');
select pg_temp.igual(has_function_privilege('anon', 'public.adn_plataforma_historial(uuid, integer)', 'execute')::text, 'false', 'anon no ejecuta el historial');
select pg_temp.igual(has_function_privilege('authenticated', 'public.adn_plataforma_historial(uuid, integer)', 'execute')::text, 'false', 'un usuario con sesión no ejecuta el historial');
select pg_temp.igual(has_function_privilege('service_role', 'public.adn_plataforma_historial(uuid, integer)', 'execute')::text, 'true', 'el servidor sí ejecuta el historial');
-- Un usuario con sesión no puede llamarlas aunque lo intente
set local role authenticated;
do $$ begin
  begin perform public.adn_plataforma_resumen(); raise exception 'FALLO: un usuario con sesión pudo leer el resumen'; exception when insufficient_privilege then raise notice 'OK: el resumen rechaza a un usuario con sesión'; end;
  begin perform public.adn_plataforma_actividad(5); raise exception 'FALLO: un usuario con sesión pudo leer la actividad'; exception when insufficient_privilege then raise notice 'OK: la actividad rechaza a un usuario con sesión'; end;
end $$;
reset role;
set local role anon;
do $$ begin
  begin perform public.adn_plataforma_historial(null, 5); raise exception 'FALLO: anon pudo leer el historial'; exception when insufficient_privilege then raise notice 'OK: el historial rechaza a anon'; end;
end $$;
reset role;
-- No son SECURITY DEFINER: no elevan privilegios de quien las llame
select pg_temp.igual((select count(*)::text from pg_proc where proname in ('adn_plataforma_resumen', 'adn_plataforma_actividad', 'adn_plataforma_historial') and prosecdef), '0', 'ninguna es security definer');
select pg_temp.igual((select count(*)::text from pg_proc where proname in ('adn_plataforma_resumen', 'adn_plataforma_actividad', 'adn_plataforma_historial') and proconfig::text like '%search_path=%'), '3', 'las tres fijan el search_path');
rollback;
