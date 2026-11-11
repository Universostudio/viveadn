-- Pruebas de las funciones que alimentan los informes: cifras exactas, permisos y aislamiento entre iglesias.
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
create or replace function pg_temp.falla(sentencia text, texto text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if sqlerrm like '%' || texto || '%' then raise notice 'OK: %', msg; return; end if;
    raise exception 'FALLO: % (error inesperado: %)', msg, sqlerrm;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.falla(text, text, text) to authenticated, anon, service_role;

insert into auth.users (id) values
  ('af000000-0000-0000-0000-000000000001'), ('af000000-0000-0000-0000-000000000002'), ('af000000-0000-0000-0000-000000000003'),
  ('af000000-0000-0000-0000-000000000004'), ('af000000-0000-0000-0000-000000000005');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('af100000-0000-0000-0000-00000000000a', 'Prueba Inf A', 'prueba-inf-a', 'ES', 'Sevilla', 'premium'),
  ('af100000-0000-0000-0000-00000000000b', 'Prueba Inf B', 'prueba-inf-b', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('af000000-0000-0000-0000-000000000001', 'af100000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@prueba.test', 'propietario', true),
  ('af000000-0000-0000-0000-000000000002', 'af100000-0000-0000-0000-00000000000a', 'Adm', 'A', 'adm@prueba.test', 'administrador', true),
  ('af000000-0000-0000-0000-000000000003', 'af100000-0000-0000-0000-00000000000a', 'Col', 'A', 'col@prueba.test', 'colaborador', true),
  ('af000000-0000-0000-0000-000000000004', 'af100000-0000-0000-0000-00000000000a', 'Lid', 'A', 'lid@prueba.test', 'lider_casa', true),
  ('af000000-0000-0000-0000-000000000005', 'af100000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@prueba.test', 'propietario', true);

-- Fechas relativas al mes actual (el dia 10 de cada mes, lejos de los limites)
create temp table f as select date_trunc('month', now())::date as m0,
  (date_trunc('month', now()) - interval '1 month')::date as m1, (date_trunc('month', now()) - interval '2 months')::date as m2,
  (date_trunc('month', now()) - interval '5 months')::date as m5, (date_trunc('month', now()) - interval '30 months')::date as m30;
grant select on f to authenticated;

insert into public.casas_oracion (id, iglesia_id, codigo_zona, nombre, pais, ciudad, direccion) values
  ('af300000-0000-0000-0000-000000000001', 'af100000-0000-0000-0000-00000000000a', 'ZN-1', 'Casa Norte', 'ES', 'Sevilla', 'x'),
  ('af300000-0000-0000-0000-000000000002', 'af100000-0000-0000-0000-00000000000a', 'ZN-2', 'Casa Sur', 'ES', 'Sevilla', 'y'),
  ('af300000-0000-0000-0000-000000000003', 'af100000-0000-0000-0000-00000000000b', 'ZN-3', 'CASA-DE-B', 'ES', 'Madrid', 'z');
-- Iglesia A: 3 miembros este mes, 2 hace dos meses, 1 hace cinco, 1 hace treinta (fuera de los 12 meses), uno inactivo
insert into public.miembros (id, iglesia_id, nombre, apellido, email, telefono, nivel_compromiso, casa_oracion_id, created_at, fecha_conversion, bautizado, fecha_bautismo, activo) select
  ('af400000-0000-0000-0000-00000000000' || n)::uuid, 'af100000-0000-0000-0000-00000000000a', 'M' || n, 'A', case when n <= 4 then 'm' || n || '@x.test' end, case when n = 1 then '600111222' end,
  (array['nuevo','nuevo','maduro','lider','nuevo','maduro','nuevo'])[n], case when n <= 2 then 'af300000-0000-0000-0000-000000000001'::uuid when n = 3 then 'af300000-0000-0000-0000-000000000002'::uuid end,
  (array[(select m0 from f), (select m0 from f), (select m0 from f), (select m2 from f), (select m2 from f), (select m5 from f), (select m30 from f)])[n] + 9,
  case when n in (1, 4) then (select m1 from f) + 9 end, n in (1, 3), case when n = 3 then (select m1 from f) + 14 end, n <> 6
from generate_series(1, 7) n;
insert into public.miembros (id, iglesia_id, nombre, apellido, created_at, activo) values
  ('af400000-0000-0000-0000-0000000000b1', 'af100000-0000-0000-0000-00000000000b', 'OTRA-IGLESIA', 'B', (select m0 from f) + 9, true);
-- Consolidaciones de A: dos iniciadas hace un mes, una de ellas completada este mes
insert into public.consolidaciones (iglesia_id, miembro_id, fecha_conversion, completado, completado_at) values
  ('af100000-0000-0000-0000-00000000000a', 'af400000-0000-0000-0000-000000000001', (select m1 from f) + 9, true, (select m0 from f) + 9),
  ('af100000-0000-0000-0000-00000000000a', 'af400000-0000-0000-0000-000000000002', (select m1 from f) + 10, false, null);
-- Asistencia a reuniones de casa: semana del lunes pasado y la anterior
insert into public.asistencias (iglesia_id, casa_oracion_id, miembro_id, fecha, presente) values
  ('af100000-0000-0000-0000-00000000000a', 'af300000-0000-0000-0000-000000000001', 'af400000-0000-0000-0000-000000000001', date '2026-11-02', true),
  ('af100000-0000-0000-0000-00000000000a', 'af300000-0000-0000-0000-000000000001', 'af400000-0000-0000-0000-000000000002', date '2026-11-03', true),
  ('af100000-0000-0000-0000-00000000000a', 'af300000-0000-0000-0000-000000000001', 'af400000-0000-0000-0000-000000000003', date '2026-11-04', false),
  ('af100000-0000-0000-0000-00000000000a', 'af300000-0000-0000-0000-000000000002', 'af400000-0000-0000-0000-000000000003', date '2026-11-04', true),
  ('af100000-0000-0000-0000-00000000000a', 'af300000-0000-0000-0000-000000000001', 'af400000-0000-0000-0000-000000000001', date '2026-10-27', true),
  ('af100000-0000-0000-0000-00000000000a', 'af300000-0000-0000-0000-000000000001', 'af400000-0000-0000-0000-000000000001', date '2026-08-01', true),
  ('af100000-0000-0000-0000-00000000000b', 'af300000-0000-0000-0000-000000000003', 'af400000-0000-0000-0000-0000000000b1', date '2026-11-02', true);
insert into public.eventos (id, iglesia_id, titulo, tipo, inicia_en) values
  ('af600000-0000-0000-0000-000000000001', 'af100000-0000-0000-0000-00000000000a', 'Culto, domingo', 'culto', '2026-11-01 10:00:00+00'),
  ('af600000-0000-0000-0000-000000000002', 'af100000-0000-0000-0000-00000000000a', 'Vigilia', 'especial', '2026-11-06 23:00:00+00'),
  ('af600000-0000-0000-0000-000000000009', 'af100000-0000-0000-0000-00000000000b', 'EVENTO-DE-B', 'culto', '2026-11-01 10:00:00+00');
insert into public.asistencia_evento (iglesia_id, evento_id, miembro_id, presente) values
  ('af100000-0000-0000-0000-00000000000a', 'af600000-0000-0000-0000-000000000001', 'af400000-0000-0000-0000-000000000001', true),
  ('af100000-0000-0000-0000-00000000000a', 'af600000-0000-0000-0000-000000000001', 'af400000-0000-0000-0000-000000000002', true),
  ('af100000-0000-0000-0000-00000000000a', 'af600000-0000-0000-0000-000000000001', 'af400000-0000-0000-0000-000000000003', false),
  ('af100000-0000-0000-0000-00000000000a', 'af600000-0000-0000-0000-000000000002', 'af400000-0000-0000-0000-000000000001', true),
  ('af100000-0000-0000-0000-00000000000b', 'af600000-0000-0000-0000-000000000009', 'af400000-0000-0000-0000-0000000000b1', true);

-- 1. Crecimiento, como propietario de A
select set_config('request.jwt.claim.sub', 'af000000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table cre as select * from public.adn_informe_crecimiento(12);
select pg_temp.igual((select count(*)::text from cre), '12', 'el informe de crecimiento trae 12 meses');
select pg_temp.igual((select (min(mes) = (select m0 - interval '11 months' from f) and max(mes) = (select m0 from f))::text from cre), 'true', 'del mes mas antiguo al actual');
select pg_temp.igual((select nuevos_miembros::text from cre where mes = (select m0 from f)), '3', 'tres miembros nuevos este mes');
select pg_temp.igual((select nuevos_miembros::text from cre where mes = (select m2 from f)), '2', 'dos hace dos meses');
select pg_temp.igual((select nuevos_miembros::text from cre where mes = (select m5 from f)), '1', 'uno hace cinco meses');
select pg_temp.igual((select sum(nuevos_miembros)::text from cre), '6', 'el de hace treinta meses queda fuera de la ventana');
select pg_temp.igual((select miembros_acumulados::text from cre where mes = (select m0 from f)), '7', 'el acumulado cuenta tambien a quien se registro antes de la ventana');
select pg_temp.igual((select miembros_acumulados::text from cre where mes = (select m5 from f)), '2', 'el acumulado de hace cinco meses: el antiguo y uno');
select pg_temp.igual((select conversiones::text from cre where mes = (select m1 from f)), '2', 'dos conversiones hace un mes');
select pg_temp.igual((select bautizos::text from cre where mes = (select m1 from f)), '1', 'un bautizo hace un mes');
select pg_temp.igual((select consolidaciones_iniciadas::text from cre where mes = (select m1 from f)), '2', 'dos consolidaciones iniciadas hace un mes');
select pg_temp.igual((select consolidaciones_completadas::text from cre where mes = (select m0 from f)), '1', 'una completada este mes');
select pg_temp.igual((select count(*)::text from public.adn_informe_crecimiento(1)), '1', 'un solo mes');
select pg_temp.falla($$select * from public.adn_informe_crecimiento(0)$$, 'ADN_PERIODO_INVALIDO', 'cero meses se rechaza');
select pg_temp.falla($$select * from public.adn_informe_crecimiento(61)$$, 'ADN_PERIODO_INVALIDO', 'mas de 60 meses se rechaza');
select pg_temp.falla($$select * from public.adn_informe_crecimiento(null)$$, 'ADN_PERIODO_INVALIDO', 'un periodo nulo se rechaza');

-- 2. Asistencia
create temp table asi as select public.adn_informe_asistencia(date '2026-10-26', date '2026-11-08') j;
select pg_temp.igual((select j -> 'casas' ->> 'registros' from asi), '5', 'cinco registros en reuniones de casa dentro del periodo (el de agosto queda fuera)');
select pg_temp.igual((select j -> 'casas' ->> 'presentes' from asi), '4', 'cuatro presentes');
select pg_temp.igual((select (j -> 'casas' -> 'semanal' -> 0 ->> 'semana') || ':' || (j -> 'casas' -> 'semanal' -> 0 ->> 'presentes') || '/' || (j -> 'casas' -> 'semanal' -> 0 ->> 'registros') from asi), '2026-10-26:1/1', 'primera semana');
select pg_temp.igual((select (j -> 'casas' -> 'semanal' -> 1 ->> 'semana') || ':' || (j -> 'casas' -> 'semanal' -> 1 ->> 'presentes') || '/' || (j -> 'casas' -> 'semanal' -> 1 ->> 'registros') from asi), '2026-11-02:3/4', 'segunda semana');
select pg_temp.igual((select (j -> 'casas' -> 'por_casa' -> 0 ->> 'casa') || ':' || (j -> 'casas' -> 'por_casa' -> 0 ->> 'presentes') || ':' || (j -> 'casas' -> 'por_casa' -> 0 ->> 'personas') from asi), 'Casa Norte:3:2', 'por casa, la de mas presentes primero: tres presencias de dos personas distintas');
select pg_temp.igual((select jsonb_array_length(j -> 'eventos' -> 'lista')::text from asi), '2', 'dos eventos con asistencia');
select pg_temp.igual((select (j -> 'eventos' -> 'lista' -> 0 ->> 'titulo') || ':' || (j -> 'eventos' -> 'lista' -> 0 ->> 'presentes') || '/' || (j -> 'eventos' -> 'lista' -> 0 ->> 'registros') from asi), 'Culto, domingo:2/3', 'el primer evento por fecha');
select pg_temp.igual((select j -> 'eventos' ->> 'presentes' from asi), '3', 'presentes en eventos');
select pg_temp.falla($$select public.adn_informe_asistencia(date '2026-11-08', date '2026-10-01')$$, 'ADN_PERIODO_INVALIDO', 'desde posterior a hasta se rechaza');
select pg_temp.falla($$select public.adn_informe_asistencia(date '2025-01-01', date '2026-11-01')$$, 'ADN_PERIODO_INVALIDO', 'mas de 366 dias se rechaza');
select pg_temp.falla($$select public.adn_informe_asistencia(null, date '2026-11-01')$$, 'ADN_PERIODO_INVALIDO', 'fechas nulas se rechazan');
select pg_temp.igual((select (public.adn_informe_asistencia(date '2020-01-01', date '2020-01-31') -> 'casas' ->> 'registros')), '0', 'un periodo sin datos da ceros, no falla');

-- 3. Miembros
select pg_temp.igual((select public.adn_informe_miembros_resumen() ->> 'total'), '7', 'siete miembros en A');
select pg_temp.igual((select (public.adn_informe_miembros_resumen() ->> 'activos') || '/' || (public.adn_informe_miembros_resumen() ->> 'inactivos')), '6/1', 'seis activos y uno inactivo');
select pg_temp.igual((select public.adn_informe_miembros_resumen() -> 'por_nivel' ->> 'nuevo'), '4', 'cuatro en nivel nuevo');
select pg_temp.igual((select (public.adn_informe_miembros_resumen() ->> 'con_correo') || '/' || (public.adn_informe_miembros_resumen() ->> 'con_telefono') || '/' || (public.adn_informe_miembros_resumen() ->> 'sin_casa')), '4/1/4', 'con correo, con telefono y sin casa');
select pg_temp.igual((select count(*)::text from public.adn_informe_miembros()), '7', 'la lista trae los siete');
select pg_temp.igual((select (string_agg(crm_id, ',' order by crm_id) = string_agg(crm_id, ','))::text from public.adn_informe_miembros()), 'true', 'ordenada por codigo');
select pg_temp.igual((select casa from public.adn_informe_miembros() where nombre = 'M1'), 'Casa Norte', 'cada miembro trae el nombre de su casa');
select pg_temp.igual((select count(*)::text from public.adn_informe_miembros() where nombre = 'OTRA-IGLESIA'), '0', 'ningun miembro de otra iglesia');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- 4. Permisos: el colaborador y el lider de casa no tienen ninguno de los dos permisos
select set_config('request.jwt.claim.sub', 'af000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.falla($$select * from public.adn_informe_crecimiento(12)$$, 'ADN_SIN_PERMISO', 'un colaborador no ve el crecimiento');
select pg_temp.falla($$select public.adn_informe_asistencia(date '2026-10-01', date '2026-11-01')$$, 'ADN_SIN_PERMISO', 'un colaborador no ve la asistencia');
select pg_temp.falla($$select * from public.adn_informe_miembros()$$, 'ADN_SIN_PERMISO', 'un colaborador no exporta miembros');
reset role;
select set_config('request.jwt.claim.sub', 'af000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.falla($$select public.adn_informe_miembros_resumen()$$, 'ADN_SIN_PERMISO', 'un lider de casa no exporta el resumen de miembros');
reset role;
select set_config('request.jwt.claim.sub', 'af000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_informe_miembros()), '7', 'un administrador si exporta miembros');
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select pg_temp.falla($$select * from public.adn_informe_crecimiento(12)$$, 'permission denied', 'un visitante no ve nada');
select pg_temp.falla($$select * from public.adn_informe_miembros()$$, 'permission denied', 'un visitante no exporta miembros');
reset role;

-- 5. Aislamiento: B solo ve lo suyo, en las tres funciones
select set_config('request.jwt.claim.sub', 'af000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select pg_temp.igual((select sum(nuevos_miembros)::text from public.adn_informe_crecimiento(12)), '1', 'B cuenta solo su miembro');
select pg_temp.igual((select miembros_acumulados::text from public.adn_informe_crecimiento(12) order by mes desc limit 1), '1', 'el acumulado de B es el suyo');
select pg_temp.igual((select (j -> 'casas' ->> 'registros') || '/' || (j -> 'eventos' ->> 'registros') from (select public.adn_informe_asistencia(date '2026-10-01', date '2026-11-30') j) x), '1/1', 'B solo ve su asistencia');
select pg_temp.igual((select (j::text like '%Casa Norte%' or j::text like '%Culto, domingo%')::text from (select public.adn_informe_asistencia(date '2026-10-01', date '2026-11-30') j) x), 'false', 'nada de A se cuela en el informe de B');
select pg_temp.igual((select string_agg(nombre, ',') from public.adn_informe_miembros()), 'OTRA-IGLESIA', 'la lista de B solo trae a su miembro');
reset role;
rollback;
