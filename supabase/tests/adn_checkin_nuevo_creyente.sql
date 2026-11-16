-- Registro por QR con la pregunta «¿Es nuevo creyente?»: solo una persona nueva que responde que si abre seguimiento.
-- Quien responde que no queda registrada (miembro, asistencia, evidencia de consentimiento) sin consolidacion; sin respuesta
-- se conserva el comportamiento anterior; y una persona que ya existia no abre seguimiento desde el formulario publico.
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
create or replace function pg_temp.falla(sentencia text, codigos text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if position(sqlstate in codigos) = 0 and sqlerrm not like '%' || codigos || '%' then raise exception 'FALLO: % (error inesperado % %)', msg, sqlstate, sqlerrm; end if;
    raise notice 'OK: % (%)', msg, sqlstate; return;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.falla(text, text, text) to authenticated, anon, service_role;

insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('af610000-0000-0000-0000-00000000000a', 'Prueba Nuevo Creyente', 'prueba-nuevo-creyente', 'ES', 'Sevilla', 'premium');
insert into public.eventos (id, iglesia_id, titulo, inicia_en, termina_en) values
  ('af620000-0000-0000-0000-0000000000a1', 'af610000-0000-0000-0000-00000000000a', 'Culto', now() + interval '1 hour', null);
insert into public.evento_checkin (iglesia_id, evento_id, max_registros) values
  ('af610000-0000-0000-0000-00000000000a', 'af620000-0000-0000-0000-0000000000a1', 300);
create or replace function pg_temp.tk() returns text language sql as $$
  select token from public.evento_checkin where evento_id = 'af620000-0000-0000-0000-0000000000a1' $$;
grant execute on function pg_temp.tk() to service_role;
-- consolidaciones, asistencia al evento y miembros de una persona por correo
create or replace function pg_temp.cuenta(p_email text, p_tabla text) returns text language plpgsql as $$
declare n text;
begin
  execute format('select count(*)::text from public.%I t where t.%I = (select id from public.miembros where email = %L limit 1)', p_tabla, case when p_tabla = 'miembros' then 'id' else 'miembro_id' end, p_email) into n;
  return n;
end $$;
grant execute on function pg_temp.cuenta(text, text) to service_role;

set local role service_role;
-- 1. Responde que si: abre seguimiento, con la nota
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Ana', 'Si', 'ana@nuevo.test', '+34 611 100 001', 'ip-1', 'v2', 'es', null, true), 'ok_nuevo', 'persona nueva que dice ser nuevo creyente');
reset role;
select pg_temp.igual(pg_temp.cuenta('ana@nuevo.test', 'consolidaciones'), '1', 'se abre su seguimiento');
select pg_temp.igual((select notas from public.consolidaciones where miembro_id = (select id from public.miembros where email = 'ana@nuevo.test')), 'Registro por QR en el evento: Culto. Dijo ser nuevo creyente.', 'la nota recuerda que lo dijo ella');

-- 2. Responde que no: queda registrada y con asistencia y consentimiento, sin seguimiento
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Beto', 'No', 'beto@nuevo.test', '+34 611 100 002', 'ip-2', 'v2', 'es', array['email'], false), 'ok_nuevo', 'persona nueva que no es nuevo creyente');
reset role;
select pg_temp.igual(pg_temp.cuenta('beto@nuevo.test', 'miembros'), '1', 'la visita queda registrada como persona');
select pg_temp.igual(pg_temp.cuenta('beto@nuevo.test', 'consolidaciones'), '0', 'no se le abre seguimiento');
select pg_temp.igual(pg_temp.cuenta('beto@nuevo.test', 'asistencia_evento'), '1', 'su asistencia al evento se anota igual');
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_evidencias where miembro_id = (select id from public.miembros where email = 'beto@nuevo.test')), '2', 'la evidencia de lo que acepto se guarda igual (texto base y casilla de correo)');
select pg_temp.igual((select estado from public.adn_consentimientos where miembro_id = (select id from public.miembros where email = 'beto@nuevo.test') and canal = 'email'), 'suscrito', 'su casilla de correo sigue concediendo lo que ella marco');

-- 3. Sin respuesta (pagina antigua): se conserva el comportamiento anterior
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Cleo', 'Antigua', 'cleo@nuevo.test', '+34 611 100 003', 'ip-3', 'v2', 'es'), 'ok_nuevo', 'una pagina antigua que no pregunta');
reset role;
select pg_temp.igual(pg_temp.cuenta('cleo@nuevo.test', 'consolidaciones'), '1', 'abre seguimiento como antes');
select pg_temp.igual((select notas from public.consolidaciones where miembro_id = (select id from public.miembros where email = 'cleo@nuevo.test')), 'Registro por QR en el evento: Culto', 'sin afirmar lo que nadie dijo');

-- 4. Una persona que ya existia no abre seguimiento desde el formulario publico, diga lo que diga
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Beto', 'No', 'beto@nuevo.test', '', 'ip-4', 'v2', 'es', null, true), 'ok_existente', 'una persona que ya existia responde que si');
reset role;
select pg_temp.igual(pg_temp.cuenta('beto@nuevo.test', 'consolidaciones'), '0', 'sigue sin seguimiento: un formulario publico no prueba quien es');
select pg_temp.igual(pg_temp.cuenta('beto@nuevo.test', 'miembros'), '1', 'y no se duplica como persona');

-- 5. Permisos y firma
select pg_temp.igual((select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'registrar_checkin'), '1', 'queda una sola version de registrar_checkin (sin sobrecargas)');
set local role authenticated;
select pg_temp.falla($$select public.registrar_checkin('x', 'a', 'b', '', '', 'i', 'v2', 'es', null, true)$$, '42501', 'una persona con sesion no llama al registro por QR');
reset role;
rollback;
