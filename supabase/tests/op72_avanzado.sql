-- OP72 gratuito y de pago: el modulo op72_avanzado se activa por plan o complemento y las metricas respetan permisos y datos visibles.
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
grant execute on function pg_temp.igual(text, text, text) to authenticated;

select pg_temp.igual((select string_agg(plan, ',' order by plan) from public.plan_modulos where modulo = 'op72_avanzado'), 'basico,premium', 'el modulo avanzado viene en Basico y Premium');
select pg_temp.igual((select count(*)::text from public.plan_modulos where plan = 'semilla' and modulo = 'consolidacion'), '1', 'el plan gratuito conserva OP72 basico');
select pg_temp.igual((select count(*)::text from public.plan_modulos where plan = 'semilla' and modulo = 'op72_avanzado'), '0', 'y no incluye el avanzado');

insert into auth.users (id) values
  ('0a000000-0000-0000-0000-000000000001'), ('0a000000-0000-0000-0000-000000000002'), ('0a000000-0000-0000-0000-000000000003');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('0a100000-0000-0000-0000-00000000000a', 'Prueba Pago', 'prueba-pago', 'ES', 'Sevilla', 'basico'),
  ('0a100000-0000-0000-0000-00000000000b', 'Prueba Gratis', 'prueba-gratis', 'ES', 'Sevilla', 'semilla');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('0a000000-0000-0000-0000-000000000001', '0a100000-0000-0000-0000-00000000000a', 'Pro', 'Pago', 'p@pago.test', 'propietario', true),
  ('0a000000-0000-0000-0000-000000000002', '0a100000-0000-0000-0000-00000000000b', 'Pro', 'Gratis', 'p@gratis.test', 'propietario', true),
  ('0a000000-0000-0000-0000-000000000003', '0a100000-0000-0000-0000-00000000000a', 'Colab', 'Pago', 'c@pago.test', 'colaborador', true);
insert into public.miembros (id, iglesia_id, nombre, apellido) values
  ('3a000000-0000-0000-0000-000000000001', '0a100000-0000-0000-0000-00000000000a', 'M1', 'X'), ('3a000000-0000-0000-0000-000000000002', '0a100000-0000-0000-0000-00000000000a', 'M2', 'X'),
  ('3a000000-0000-0000-0000-000000000003', '0a100000-0000-0000-0000-00000000000a', 'M3', 'X'), ('3a000000-0000-0000-0000-000000000004', '0a100000-0000-0000-0000-00000000000a', 'M4', 'X'),
  ('3a000000-0000-0000-0000-000000000005', '0a100000-0000-0000-0000-00000000000a', 'M5', 'X'), ('3a000000-0000-0000-0000-000000000009', '0a100000-0000-0000-0000-00000000000b', 'G1', 'X');
-- 1 abierto reciente; 2 vencido sin contacto; 3 abierto con primer contacto a las 5 h; 4 completado a las 70 h con contacto a las 30 h; 5 fuera del periodo
insert into public.consolidaciones (iglesia_id, miembro_id, consolidador_id, fecha_conversion, primer_contacto_fecha, completado, completado_at) values
  ('0a100000-0000-0000-0000-00000000000a', '3a000000-0000-0000-0000-000000000001', null, now() - interval '10 hours', null, false, null),
  ('0a100000-0000-0000-0000-00000000000a', '3a000000-0000-0000-0000-000000000002', null, now() - interval '100 hours', null, false, null),
  ('0a100000-0000-0000-0000-00000000000a', '3a000000-0000-0000-0000-000000000003', '0a000000-0000-0000-0000-000000000001', now() - interval '50 hours', now() - interval '45 hours', false, null),
  ('0a100000-0000-0000-0000-00000000000a', '3a000000-0000-0000-0000-000000000004', '0a000000-0000-0000-0000-000000000001', now() - interval '90 hours', now() - interval '60 hours', true, now() - interval '20 hours'),
  ('0a100000-0000-0000-0000-00000000000a', '3a000000-0000-0000-0000-000000000005', null, now() - interval '200 days', null, false, null),
  ('0a100000-0000-0000-0000-00000000000b', '3a000000-0000-0000-0000-000000000009', null, now() - interval '5 hours', null, false, null);

-- Iglesia de pago: propietario
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table m as select public.metricas_op72() j;
grant select on m to authenticated;
select pg_temp.igual((select j->>'total' from m), '4', 'cuenta las consolidaciones del periodo y deja fuera las antiguas');
select pg_temp.igual((select j->>'completados' from m), '1', 'completados');
select pg_temp.igual((select j->>'abiertos' from m), '3', 'abiertos');
select pg_temp.igual((select j->>'vencidos' from m), '1', 'vencidos: abiertos con mas de 72 horas');
select pg_temp.igual((select j->>'con_primer_contacto' from m), '2', 'con primer contacto');
select pg_temp.igual((select j->>'primer_contacto_24h' from m), '1', 'primer contacto en las primeras 24 horas');
select pg_temp.igual((select j->>'horas_primer_contacto' from m), '17.5', 'horas medias hasta el primer contacto');
select pg_temp.igual((select j->>'completados_72h' from m), '1', 'completados dentro de las 72 horas');
select pg_temp.igual((select jsonb_array_length(j->'por_consolidador')::text from m), '2', 'agrupa por consolidador, con los casos sin asignar aparte');
select pg_temp.igual((select (j->'por_consolidador'->0->>'total') from m), '2', 'el consolidador con mas casos va primero');
select pg_temp.igual((public.metricas_op72(now() - interval '1 hour') ->> 'total'), '0', 'un periodo sin casos devuelve cero');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Colaborador sin consolidacion.ver
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000003', true);
set local role authenticated;
do $$ begin
  begin perform public.metricas_op72(); exception when insufficient_privilege then return; end;
  raise exception 'FALLO: un colaborador sin consolidacion.ver vio las metricas';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Iglesia gratuita: bloqueado hasta que se contrate el complemento
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000002', true);
set local role authenticated;
do $$ begin
  begin perform public.metricas_op72(); exception when insufficient_privilege then return; end;
  raise exception 'FALLO: la iglesia gratuita vio las metricas avanzadas';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Con el complemento activado por la plataforma, la iglesia gratuita ya las ve, y solo ve lo suyo
insert into public.iglesia_modulos (iglesia_id, modulo, activo, origen) values ('0a100000-0000-0000-0000-00000000000b', 'op72_avanzado', true, 'addon');
select set_config('request.jwt.claim.sub', '0a000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((public.metricas_op72() ->> 'total'), '1', 'con el complemento activado ve las metricas, solo de su iglesia');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Anonimo: sin acceso a la funcion
select pg_temp.igual(has_function_privilege('anon', 'public.metricas_op72(timestamptz)', 'execute')::text, 'false', 'un anonimo no puede ejecutarla');
rollback;
