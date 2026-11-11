-- Pruebas de los datos del panel de inicio: cifras exactas, cumpleaños (29 de febrero y cambio de año), lo que
-- ve cada rol y el aislamiento entre iglesias.
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

insert into auth.users (id) values ('ad100000-0000-0000-0000-000000000001'), ('ad100000-0000-0000-0000-000000000002'), ('ad100000-0000-0000-0000-000000000003');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ad200000-0000-0000-0000-00000000000a', 'Prueba Pan A', 'prueba-pan-a', 'ES', 'Sevilla', 'premium'),
  ('ad200000-0000-0000-0000-00000000000b', 'Prueba Pan B', 'prueba-pan-b', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('ad100000-0000-0000-0000-000000000001', 'ad200000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@prueba.test', 'propietario', true),
  ('ad100000-0000-0000-0000-000000000002', 'ad200000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@prueba.test', 'propietario', true),
  ('ad100000-0000-0000-0000-000000000003', 'ad200000-0000-0000-0000-00000000000a', 'Lid', 'A', 'lid@prueba.test', 'lider_casa', true);

insert into public.casas_oracion (id, iglesia_id, codigo_zona, nombre, pais, ciudad, direccion) values
  ('ad300000-0000-0000-0000-000000000001', 'ad200000-0000-0000-0000-00000000000a', 'ZN-1', 'Casa Norte', 'ES', 'Sevilla', 'x');
-- Miembros de A: 2 nuevos en los ultimos 30 dias, 1 en los 30 anteriores, 1 antiguo e inactivo; 2 sin casa; 1 bautizado
insert into public.miembros (id, iglesia_id, nombre, apellido, casa_oracion_id, bautizado, created_at, activo, fecha_nacimiento) values
  ('ad400000-0000-0000-0000-000000000001', 'ad200000-0000-0000-0000-00000000000a', 'Ana', 'Uno', null, true, now() - interval '3 days', true, '1990-06-12'),
  ('ad400000-0000-0000-0000-000000000002', 'ad200000-0000-0000-0000-00000000000a', 'Bea', 'Dos', 'ad300000-0000-0000-0000-000000000001', false, now() - interval '20 days', true, '2000-02-29'),
  ('ad400000-0000-0000-0000-000000000003', 'ad200000-0000-0000-0000-00000000000a', 'Cai', 'Tres', 'ad300000-0000-0000-0000-000000000001', false, now() - interval '45 days', true, '1985-01-05'),
  ('ad400000-0000-0000-0000-000000000004', 'ad200000-0000-0000-0000-00000000000a', 'Dan', 'Cuatro', null, false, now() - interval '200 days', false, '1990-06-13'),
  ('ad400000-0000-0000-0000-0000000000b1', 'ad200000-0000-0000-0000-00000000000b', 'OTRA-IGLESIA', 'B', null, true, now() - interval '3 days', true, '1990-06-12');
-- Asistencia: semana de referencia 2026-11-09 (lunes) y la anterior
insert into public.asistencias (iglesia_id, casa_oracion_id, miembro_id, fecha, presente) values
  ('ad200000-0000-0000-0000-00000000000a', 'ad300000-0000-0000-0000-000000000001', 'ad400000-0000-0000-0000-000000000001', '2026-11-09', true),
  ('ad200000-0000-0000-0000-00000000000a', 'ad300000-0000-0000-0000-000000000001', 'ad400000-0000-0000-0000-000000000002', '2026-11-10', true),
  ('ad200000-0000-0000-0000-00000000000a', 'ad300000-0000-0000-0000-000000000001', 'ad400000-0000-0000-0000-000000000003', '2026-11-12', false),
  ('ad200000-0000-0000-0000-00000000000a', 'ad300000-0000-0000-0000-000000000001', 'ad400000-0000-0000-0000-000000000001', '2026-11-03', true),
  ('ad200000-0000-0000-0000-00000000000a', 'ad300000-0000-0000-0000-000000000001', 'ad400000-0000-0000-0000-000000000002', '2026-11-04', false),
  ('ad200000-0000-0000-0000-00000000000a', 'ad300000-0000-0000-0000-000000000001', 'ad400000-0000-0000-0000-000000000001', '2026-09-22', true);
-- Eventos: 2 proximos (uno cancelado aparte), uno pasado
insert into public.eventos (iglesia_id, titulo, tipo, inicia_en, lugar, cancelado) values
  ('ad200000-0000-0000-0000-00000000000a', 'Pasado', 'culto', now() - interval '2 days', null, false),
  ('ad200000-0000-0000-0000-00000000000a', 'Proximo 2', 'culto', now() + interval '5 days', 'Templo', false),
  ('ad200000-0000-0000-0000-00000000000a', 'Proximo 1', 'especial', now() + interval '1 day', null, false),
  ('ad200000-0000-0000-0000-00000000000a', 'Cancelado', 'culto', now() + interval '2 days', null, true),
  ('ad200000-0000-0000-0000-00000000000b', 'EVENTO-DE-B', 'culto', now() + interval '1 day', null, false);
insert into public.eventos (iglesia_id, titulo, inicia_en) select 'ad200000-0000-0000-0000-00000000000a', 'Relleno ' || i, now() + (i + 10) * interval '1 day' from generate_series(1, 6) i;
-- Formacion
insert into public.programas_formacion (id, iglesia_id, nombre) values ('ad500000-0000-0000-0000-000000000001', 'ad200000-0000-0000-0000-00000000000a', 'Discipulado');
insert into public.inscripciones_formacion (iglesia_id, programa_id, miembro_id, estado, completado_en) values
  ('ad200000-0000-0000-0000-00000000000a', 'ad500000-0000-0000-0000-000000000001', 'ad400000-0000-0000-0000-000000000001', 'en_curso', null),
  ('ad200000-0000-0000-0000-00000000000a', 'ad500000-0000-0000-0000-000000000001', 'ad400000-0000-0000-0000-000000000002', 'en_curso', null),
  ('ad200000-0000-0000-0000-00000000000a', 'ad500000-0000-0000-0000-000000000001', 'ad400000-0000-0000-0000-000000000003', 'completado', now());

select set_config('request.jwt.claim.sub', 'ad100000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table p as select public.adn_panel_inicio(date '2026-11-11') j;
select pg_temp.igual((select j -> 'miembros' ->> 'activos' from p), '3', 'tres miembros activos');
select pg_temp.igual((select (j -> 'miembros' ->> 'nuevos_30d') || '/' || (j -> 'miembros' ->> 'nuevos_30d_previos') from p), '2/1', 'dos nuevos en 30 dias y uno en los 30 anteriores');
select pg_temp.igual((select (j -> 'miembros' ->> 'sin_casa') || '/' || (j -> 'miembros' ->> 'bautizados') from p), '1/1', 'sin casa y bautizados cuentan solo a los activos');
select pg_temp.igual((select (j -> 'asistencia' -> 'semana_actual' ->> 'semana') || ':' || (j -> 'asistencia' -> 'semana_actual' ->> 'presentes') || '/' || (j -> 'asistencia' -> 'semana_actual' ->> 'registros') from p), '2026-11-09:2/3', 'semana actual (desde el lunes): 2 presentes de 3');
select pg_temp.igual((select (j -> 'asistencia' -> 'semana_anterior' ->> 'semana') || ':' || (j -> 'asistencia' -> 'semana_anterior' ->> 'presentes') || '/' || (j -> 'asistencia' -> 'semana_anterior' ->> 'registros') from p), '2026-11-02:1/2', 'semana anterior: 1 de 2');
select pg_temp.igual((select jsonb_array_length(j -> 'asistencia' -> 'serie')::text from p), '8', 'la serie trae 8 semanas');
select pg_temp.igual((select (j -> 'asistencia' -> 'serie' -> 7 ->> 'presentes') || ',' || (j -> 'asistencia' -> 'serie' -> 6 ->> 'presentes') || ',' || (j -> 'asistencia' -> 'serie' -> 0 ->> 'presentes') from p), '2,1,1', 'la serie acaba en la semana actual y la primera semana (21 de septiembre) recoge la asistencia del 22');
select pg_temp.igual((select string_agg(e ->> 'titulo', ',' order by (e ->> 'inicia_en')) from p, jsonb_array_elements(j -> 'eventos_proximos') e), 'Proximo 1,Proximo 2,Relleno 1,Relleno 2,Relleno 3', 'cinco proximos por fecha, sin el pasado, el cancelado ni los de otra iglesia');
select pg_temp.igual((select (j -> 'formacion' ->> 'en_curso') || '/' || (j -> 'formacion' ->> 'completadas_mes') from p), '2/1', 'formacion: 2 en curso y 1 completada este mes');
select pg_temp.igual((select jsonb_array_length(j -> 'crecimiento')::text from p), '6', 'seis meses de crecimiento');
select pg_temp.igual((select sum((m ->> 'nuevos')::int)::text from p, jsonb_array_elements(j -> 'crecimiento') m), '3', 'tres miembros caen en los seis meses; el de hace 200 dias queda fuera');
select pg_temp.igual((select (m ->> 'nuevos') from p, jsonb_array_elements(j -> 'crecimiento') m order by m ->> 'mes' desc limit 1), (select count(*)::text from public.miembros where created_at >= date_trunc('month', now())), 'el ultimo mes es el actual');
select pg_temp.igual((select (j -> 'comunicacion' ->> 'mensajes_30d') from p), '0', 'sin mensajes enviados, la comunicacion marca 0');

-- Cumpleanos: proximos 14 dias, solo de miembros activos
select pg_temp.igual((select string_agg((c ->> 'nombre') || ':' || (c ->> 'fecha') || ':' || (c ->> 'en_dias'), ',') from jsonb_array_elements(public.adn_panel_inicio(date '2026-06-10') -> 'cumpleanos') c), 'Ana:2026-06-12:2', 'Ana cumple dentro de 2 dias; Dan tambien pero esta inactivo');
select pg_temp.igual((select string_agg((c ->> 'nombre') || ':' || (c ->> 'fecha') || ':' || (c ->> 'en_dias'), ',') from jsonb_array_elements(public.adn_panel_inicio(date '2026-06-12') -> 'cumpleanos') c), 'Ana:2026-06-12:0', 'quien cumple hoy aparece con 0 dias');
select pg_temp.igual((select jsonb_array_length(public.adn_panel_inicio(date '2026-06-13') -> 'cumpleanos')::text), '0', 'quien cumplio ayer no aparece hasta el año que viene');
select pg_temp.igual((select (c ->> 'fecha') || ':' || (c ->> 'en_dias') from jsonb_array_elements(public.adn_panel_inicio(date '2026-02-20') -> 'cumpleanos') c), '2026-02-28:8', 'el 29 de febrero se celebra el 28 en un año no bisiesto');
select pg_temp.igual((select (c ->> 'fecha') || ':' || (c ->> 'en_dias') from jsonb_array_elements(public.adn_panel_inicio(date '2028-02-20') -> 'cumpleanos') c), '2028-02-29:9', 'y el 29 en un año bisiesto');
select pg_temp.igual((select (c ->> 'fecha') || ':' || (c ->> 'en_dias') from jsonb_array_elements(public.adn_panel_inicio(date '2026-12-28') -> 'cumpleanos') c), '2027-01-05:8', 'el cambio de año se resuelve');
select pg_temp.igual((select jsonb_array_length(public.adn_panel_inicio(date '2026-03-01') -> 'cumpleanos')::text), '0', 'sin cumpleaños cercanos la lista va vacia, no nula');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Cada rol ve lo suyo: un lider de casa sin miembros asignados ve ceros, sin error
select set_config('request.jwt.claim.sub', 'ad100000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select (public.adn_panel_inicio() -> 'miembros' ->> 'activos')), '0', 'un lider de casa sin asignados ve 0 miembros');
select pg_temp.igual((select jsonb_array_length(public.adn_panel_inicio() -> 'cumpleanos')::text), '0', 'y ningun cumpleaños');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Aislamiento: B solo ve lo suyo
select set_config('request.jwt.claim.sub', 'ad100000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select public.adn_panel_inicio() -> 'miembros' ->> 'activos'), '1', 'B cuenta su miembro');
select pg_temp.igual((select string_agg(e ->> 'titulo', ',') from jsonb_array_elements(public.adn_panel_inicio() -> 'eventos_proximos') e), 'EVENTO-DE-B', 'B solo ve su evento');
select pg_temp.igual((select (public.adn_panel_inicio() -> 'formacion' ->> 'en_curso')), '0', 'la formacion de A no cuenta en B');
select pg_temp.igual((select (public.adn_panel_inicio(date '2026-06-10')::text like '%Ana%')::text), 'false', 'ningun nombre de A en el panel de B');
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$ begin
  begin perform public.adn_panel_inicio(); exception when insufficient_privilege then raise notice 'OK: un visitante no ve el panel'; return; end;
  raise exception 'FALLO: un visitante vio el panel';
end $$;
reset role;
rollback;
