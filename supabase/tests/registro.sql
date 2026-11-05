-- Registro de iglesias: codigos de acceso, limite por dispositivo y cierre a anon y authenticated.
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
create or replace function pg_temp.debe_fallar(q text, msg text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then raise notice 'OK: %', msg; return; end;
  raise exception 'FALLO: debia fallar: %', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.debe_fallar(text, text) to authenticated, anon, service_role;

-- Ajustes por defecto: registro abierto y con codigo
select pg_temp.igual((select valor::text from public.plataforma_ajustes where clave = 'registro_abierto'), 'true', 'el registro viene abierto');
select pg_temp.igual((select valor::text from public.plataforma_ajustes where clave = 'registro_requiere_codigo'), 'true', 'el codigo se exige por defecto');
select pg_temp.debe_fallar($q$ insert into public.plataforma_ajustes (clave, valor) values ('Mal Nombre', 'true'::jsonb) $q$, 'clave de ajuste invalida');

-- Codigos
insert into public.registro_codigos (id, codigo_hash, etiqueta, usos_max) values
  ('4d000000-0000-0000-0000-000000000001', repeat('a', 64), 'uso unico', 1),
  ('4d000000-0000-0000-0000-000000000002', repeat('b', 64), 'tres usos', 3),
  ('4d000000-0000-0000-0000-000000000003', repeat('c', 64), 'vencido', 5),
  ('4d000000-0000-0000-0000-000000000004', repeat('d', 64), 'desactivado', 5);
update public.registro_codigos set vence_en = now() - interval '1 day' where etiqueta = 'vencido';
update public.registro_codigos set activo = false where etiqueta = 'desactivado';

select pg_temp.igual(public.consumir_codigo_registro(repeat('a', 64))::text, '4d000000-0000-0000-0000-000000000001', 'un codigo valido se consume');
select pg_temp.igual(public.consumir_codigo_registro(repeat('a', 64))::text, null, 'un codigo de un solo uso no se reutiliza');
select pg_temp.igual(public.consumir_codigo_registro(repeat('c', 64))::text, null, 'un codigo vencido no sirve');
select pg_temp.igual(public.consumir_codigo_registro(repeat('d', 64))::text, null, 'un codigo desactivado no sirve');
select pg_temp.igual(public.consumir_codigo_registro(repeat('e', 64))::text, null, 'un codigo desconocido no sirve');
select public.consumir_codigo_registro(repeat('b', 64));
select public.consumir_codigo_registro(repeat('b', 64));
select public.consumir_codigo_registro(repeat('b', 64));
select pg_temp.igual(public.consumir_codigo_registro(repeat('b', 64))::text, null, 'tres usos y no mas');
select public.devolver_codigo_registro('4d000000-0000-0000-0000-000000000002');
select pg_temp.igual((select usos::text from public.registro_codigos where etiqueta = 'tres usos'), '2', 'devolver un uso lo libera');
select pg_temp.igual(public.consumir_codigo_registro(repeat('b', 64))::text, '4d000000-0000-0000-0000-000000000002', 'el uso devuelto vuelve a estar disponible');
select public.devolver_codigo_registro('4d000000-0000-0000-0000-000000000001');
select public.devolver_codigo_registro('4d000000-0000-0000-0000-000000000001');
select pg_temp.igual((select usos::text from public.registro_codigos where etiqueta = 'uso unico'), '0', 'los usos nunca bajan de cero');
select pg_temp.debe_fallar($q$ insert into public.registro_codigos (codigo_hash, etiqueta) values ('corto', 'x') $q$, 'el codigo se guarda como huella de 64 caracteres');
select pg_temp.debe_fallar($q$ insert into public.registro_codigos (codigo_hash, etiqueta, usos_max, usos) values (repeat('f', 64), 'x', 1, 2) $q$, 'los usos no superan el maximo');

-- Limite por dispositivo: 3 intentos y el cuarto se rechaza; otro dispositivo no se ve afectado
select pg_temp.igual(public.registrar_intento_registro(repeat('1', 64), 3, 60)::text, 'true', 'intento 1');
select pg_temp.igual(public.registrar_intento_registro(repeat('1', 64), 3, 60)::text, 'true', 'intento 2');
select pg_temp.igual(public.registrar_intento_registro(repeat('1', 64), 3, 60)::text, 'true', 'intento 3');
select pg_temp.igual(public.registrar_intento_registro(repeat('1', 64), 3, 60)::text, 'false', 'el cuarto intento se rechaza');
select pg_temp.igual(public.registrar_intento_registro(repeat('2', 64), 3, 60)::text, 'true', 'otro dispositivo no se ve afectado');
update public.registro_intentos set created_at = now() - interval '2 hours' where ip_hash = repeat('1', 64);
select pg_temp.igual(public.registrar_intento_registro(repeat('1', 64), 3, 60)::text, 'true', 'pasada la ventana se puede volver a intentar');
select pg_temp.debe_fallar($q$ insert into public.registro_intentos (ip_hash) values ('no-es-huella') $q$, 'solo se guardan huellas');

-- anon y authenticated no tocan nada
set local role authenticated;
select pg_temp.debe_fallar($q$ select * from public.registro_codigos $q$, 'authenticated no lee los codigos');
select pg_temp.debe_fallar($q$ select * from public.plataforma_ajustes $q$, 'authenticated no lee los ajustes');
select pg_temp.debe_fallar($q$ select public.consumir_codigo_registro(repeat('b', 64)) $q$, 'authenticated no ejecuta consumir_codigo_registro');
select pg_temp.debe_fallar($q$ select public.registrar_intento_registro(repeat('9', 64), 3, 60) $q$, 'authenticated no ejecuta registrar_intento_registro');
reset role;
set local role anon;
select pg_temp.debe_fallar($q$ select * from public.registro_intentos $q$, 'anon no lee los intentos');
select pg_temp.debe_fallar($q$ select public.devolver_codigo_registro('4d000000-0000-0000-0000-000000000001') $q$, 'anon no ejecuta devolver_codigo_registro');
reset role;

rollback;
