-- Eventos y asistencia por evento: aislamiento entre iglesias, permisos por rol,
-- lider de casa limitado a su casa y a los miembros de su casa, y validaciones.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if exists (select 1 from public.iglesias where slug not like 'prueba-%') then
    raise exception 'Este script no se ejecuta en una base con iglesias reales';
  end if;
end $$;

create or replace function pg_temp.igual(obtenido int, esperado int, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
create or replace function pg_temp.debe_fallar(q text, msg text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then raise notice 'OK: %', msg; return; end;
  raise exception 'FALLO: debia fallar: %', msg;
end $$;
grant execute on function pg_temp.igual(int, int, text), pg_temp.debe_fallar(text, text) to authenticated, service_role;

insert into auth.users (id) values
  ('e1000000-0000-0000-0000-000000000001'), ('e1000000-0000-0000-0000-000000000002'),
  ('e1000000-0000-0000-0000-000000000003'), ('e1000000-0000-0000-0000-000000000004');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('18000000-0000-0000-0000-00000000000a', 'Prueba E1', 'prueba-e1', 'ES', 'Sevilla', 'premium'),
  ('18000000-0000-0000-0000-00000000000b', 'Prueba E2', 'prueba-e2', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('e1000000-0000-0000-0000-000000000001', '18000000-0000-0000-0000-00000000000a', 'Pro', 'Uno', 'p@e1.test', 'propietario', true),
  ('e1000000-0000-0000-0000-000000000002', '18000000-0000-0000-0000-00000000000a', 'Lid', 'Dos', 'l@e1.test', 'lider_casa', true),
  ('e1000000-0000-0000-0000-000000000003', '18000000-0000-0000-0000-00000000000a', 'Mie', 'Tres', 'm@e1.test', 'miembro', true),
  ('e1000000-0000-0000-0000-000000000004', '18000000-0000-0000-0000-00000000000b', 'Pro', 'Dos', 'p@e2.test', 'propietario', true);
insert into public.casas_oracion (id, iglesia_id, codigo_zona, nombre, lider_id, pais, ciudad, direccion) values
  ('28000000-0000-0000-0000-00000000000a', '18000000-0000-0000-0000-00000000000a', 'ZN', 'Casa propia', 'e1000000-0000-0000-0000-000000000002', 'ES', 'Sevilla', 'C1'),
  ('28000000-0000-0000-0000-0000000000a2', '18000000-0000-0000-0000-00000000000a', 'ZS', 'Casa ajena', null, 'ES', 'Sevilla', 'C2'),
  ('28000000-0000-0000-0000-00000000000b', '18000000-0000-0000-0000-00000000000b', 'ZN', 'Casa de E2', null, 'ES', 'Sevilla', 'C3');
insert into public.miembros (id, iglesia_id, nombre, apellido, casa_oracion_id) values
  ('38000000-0000-0000-0000-0000000000a1', '18000000-0000-0000-0000-00000000000a', 'EnMiCasa', 'A', '28000000-0000-0000-0000-00000000000a'),
  ('38000000-0000-0000-0000-0000000000a2', '18000000-0000-0000-0000-00000000000a', 'EnOtraCasa', 'A', '28000000-0000-0000-0000-0000000000a2'),
  ('38000000-0000-0000-0000-0000000000a3', '18000000-0000-0000-0000-00000000000a', 'SinCasa', 'A', null),
  ('38000000-0000-0000-0000-0000000000b1', '18000000-0000-0000-0000-00000000000b', 'DeE2', 'B', null);
insert into public.eventos (id, iglesia_id, titulo, tipo, inicia_en, casa_oracion_id) values
  ('48000000-0000-0000-0000-0000000000a1', '18000000-0000-0000-0000-00000000000a', 'Reunion de mi casa', 'casa_oracion', now() + interval '1 day', '28000000-0000-0000-0000-00000000000a'),
  ('48000000-0000-0000-0000-0000000000a2', '18000000-0000-0000-0000-00000000000a', 'Reunion de otra casa', 'casa_oracion', now() + interval '1 day', '28000000-0000-0000-0000-0000000000a2'),
  ('48000000-0000-0000-0000-0000000000a3', '18000000-0000-0000-0000-00000000000a', 'Culto general', 'culto', now() + interval '2 day', null),
  ('48000000-0000-0000-0000-0000000000b1', '18000000-0000-0000-0000-00000000000b', 'Culto de E2', 'culto', now() + interval '2 day', null);

-- Restricciones de datos
select pg_temp.debe_fallar($q$ insert into public.eventos (iglesia_id, titulo, tipo, inicia_en) values ('18000000-0000-0000-0000-00000000000a', 'X', 'inventado', now()) $q$, 'tipo de evento invalido');
select pg_temp.debe_fallar($q$ insert into public.eventos (iglesia_id, titulo, inicia_en, termina_en) values ('18000000-0000-0000-0000-00000000000a', 'X', now(), now() - interval '1 hour') $q$, 'termina antes de empezar');
select pg_temp.debe_fallar($q$ insert into public.eventos (iglesia_id, titulo, inicia_en) values ('18000000-0000-0000-0000-00000000000a', '   ', now()) $q$, 'titulo vacio');
select pg_temp.debe_fallar($q$ insert into public.eventos (iglesia_id, titulo, inicia_en, casa_oracion_id) values ('18000000-0000-0000-0000-00000000000a', 'X', now(), '28000000-0000-0000-0000-00000000000b') $q$, 'casa de otra iglesia en un evento');
select pg_temp.debe_fallar($q$ insert into public.asistencia_evento (iglesia_id, evento_id, miembro_id) values ('18000000-0000-0000-0000-00000000000a', '48000000-0000-0000-0000-0000000000a3', '38000000-0000-0000-0000-0000000000b1') $q$, 'miembro de otra iglesia en la asistencia');

-- Propietario: ve solo su iglesia, crea eventos, registra asistencia
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::int from public.eventos), 3, 'el propietario ve los eventos de su iglesia y no los de otra');
insert into public.eventos (titulo, inicia_en) values ('Creado por propietario', now() + interval '3 day');
select pg_temp.igual((select count(*)::int from public.eventos where titulo = 'Creado por propietario' and iglesia_id = '18000000-0000-0000-0000-00000000000a'), 1, 'el propietario crea un evento en su iglesia');
select pg_temp.debe_fallar($q$ insert into public.eventos (iglesia_id, titulo, inicia_en) values ('18000000-0000-0000-0000-00000000000b', 'Intruso', now()) $q$, 'crear evento en otra iglesia');
insert into public.asistencia_evento (evento_id, miembro_id) values ('48000000-0000-0000-0000-0000000000a3', '38000000-0000-0000-0000-0000000000a3');
select pg_temp.igual((select count(*)::int from public.asistencia_evento), 1, 'el propietario registra asistencia');
select pg_temp.debe_fallar($q$ insert into public.asistencia_evento (evento_id, miembro_id) values ('48000000-0000-0000-0000-0000000000a3', '38000000-0000-0000-0000-0000000000a3') $q$, 'asistencia repetida del mismo miembro');
reset role;

-- Lider de casa: ve eventos pero no los gestiona; registra solo en su casa y solo a miembros de su casa
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select count(*)::int from public.eventos), 4, 'el lider ve el calendario');
select pg_temp.debe_fallar($q$ insert into public.eventos (titulo, inicia_en) values ('Del lider', now()) $q$, 'el lider no crea eventos');
do $$ declare n int; begin update public.eventos set titulo = 'Cambiado'; get diagnostics n = row_count; perform pg_temp.igual(n, 0, 'el lider no edita eventos'); end $$;
insert into public.asistencia_evento (evento_id, miembro_id) values ('48000000-0000-0000-0000-0000000000a1', '38000000-0000-0000-0000-0000000000a1');
select pg_temp.igual((select count(*)::int from public.asistencia_evento where evento_id = '48000000-0000-0000-0000-0000000000a1'), 1, 'el lider registra a un miembro de su casa en el evento de su casa');
select pg_temp.debe_fallar($q$ insert into public.asistencia_evento (evento_id, miembro_id) values ('48000000-0000-0000-0000-0000000000a1', '38000000-0000-0000-0000-0000000000a2') $q$, 'el lider registra a alguien de otra casa');
select pg_temp.debe_fallar($q$ insert into public.asistencia_evento (evento_id, miembro_id) values ('48000000-0000-0000-0000-0000000000a2', '38000000-0000-0000-0000-0000000000a2') $q$, 'el lider registra en el evento de otra casa');
select pg_temp.debe_fallar($q$ insert into public.asistencia_evento (evento_id, miembro_id) values ('48000000-0000-0000-0000-0000000000a3', '38000000-0000-0000-0000-0000000000a1') $q$, 'el lider registra en un evento sin casa');
select pg_temp.igual((select count(*)::int from public.asistencia_evento), 1, 'el lider solo ve la asistencia de eventos de su casa');
do $$ declare n int; begin delete from public.asistencia_evento; get diagnostics n = row_count; perform pg_temp.igual(n, 0, 'el lider no borra asistencia'); end $$;
reset role;

-- Miembro: ve el calendario, no ve asistencia ni crea nada
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select count(*)::int from public.eventos), 4, 'el miembro ve el calendario');
select pg_temp.igual((select count(*)::int from public.asistencia_evento), 0, 'el miembro no ve la asistencia');
select pg_temp.debe_fallar($q$ insert into public.asistencia_evento (evento_id, miembro_id) values ('48000000-0000-0000-0000-0000000000a3', '38000000-0000-0000-0000-0000000000a2') $q$, 'el miembro no registra asistencia');
reset role;

-- Propietario de la otra iglesia: no ve nada de la primera
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.igual((select count(*)::int from public.eventos), 1, 'la otra iglesia solo ve sus eventos');
select pg_temp.igual((select count(*)::int from public.asistencia_evento), 0, 'la otra iglesia no ve asistencia ajena');
reset role;

-- Una iglesia nueva recibe los permisos de eventos en sus roles
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('18000000-0000-0000-0000-00000000000c', 'Prueba E3', 'prueba-e3', 'ES', 'Sevilla', 'semilla');
select pg_temp.igual((select count(*)::int from public.rol_permisos rp join public.roles r on r.id = rp.rol_id where r.iglesia_id = '18000000-0000-0000-0000-00000000000c' and r.clave = 'administrador' and rp.permiso like 'eventos.%'), 2, 'el administrador de una iglesia nueva gestiona eventos');
select pg_temp.igual((select count(*)::int from public.rol_permisos rp join public.roles r on r.id = rp.rol_id where r.iglesia_id = '18000000-0000-0000-0000-00000000000c' and r.clave = 'miembro' and rp.permiso = 'eventos.ver'), 1, 'el miembro de una iglesia nueva ve el calendario');

rollback;
