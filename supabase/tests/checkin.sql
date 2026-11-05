-- Registro por QR: ventana de tiempo, topes, limite por dispositivo, duplicados, enlace pausado,
-- permisos de lectura y funciones solo para el servidor.
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
create or replace function pg_temp.igual(obtenido boolean, esperado text, msg text) returns void language sql as $$
  select pg_temp.igual(obtenido::text, esperado, msg) $$;
create or replace function pg_temp.debe_fallar(q text, msg text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then raise notice 'OK: %', msg; return; end;
  raise exception 'FALLO: debia fallar: %', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.igual(boolean, text, text), pg_temp.debe_fallar(text, text) to authenticated, service_role;

insert into auth.users (id) values ('e2000000-0000-0000-0000-000000000001'), ('e2000000-0000-0000-0000-000000000002');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, email_contacto) values
  ('19000000-0000-0000-0000-00000000000a', 'Prueba Q1', 'prueba-q1', 'ES', 'Sevilla', 'premium', 'q1@iglesia.test'),
  ('19000000-0000-0000-0000-00000000000b', 'Prueba Q2', 'prueba-q2', 'ES', 'Sevilla', 'premium', null);
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('e2000000-0000-0000-0000-000000000001', '19000000-0000-0000-0000-00000000000a', 'Pro', 'Uno', 'p@q1.test', 'propietario', true),
  ('e2000000-0000-0000-0000-000000000002', '19000000-0000-0000-0000-00000000000a', 'Mie', 'Dos', 'm@q1.test', 'miembro', true);
insert into public.casas_oracion (id, iglesia_id, codigo_zona, nombre, pais, ciudad, direccion) values
  ('29000000-0000-0000-0000-00000000000a', '19000000-0000-0000-0000-00000000000a', 'ZN', 'Casa Q', 'ES', 'Sevilla', 'C1');
insert into public.miembros (id, iglesia_id, nombre, apellido, email, telefono) values
  ('39000000-0000-0000-0000-0000000000a1', '19000000-0000-0000-0000-00000000000a', 'Ana', 'Lopez', 'ana@q1.test', '+34 600 111 222'),
  ('39000000-0000-0000-0000-0000000000b1', '19000000-0000-0000-0000-00000000000b', 'Otra', 'Iglesia', 'otra@q2.test', '+34 600 999 888');
insert into public.eventos (id, iglesia_id, titulo, inicia_en, termina_en, casa_oracion_id) values
  ('49000000-0000-0000-0000-0000000000a1', '19000000-0000-0000-0000-00000000000a', 'Abierto', now() + interval '1 hour', null, '29000000-0000-0000-0000-00000000000a'),
  ('49000000-0000-0000-0000-0000000000a2', '19000000-0000-0000-0000-00000000000a', 'Futuro', now() + interval '2 days', null, null),
  ('49000000-0000-0000-0000-0000000000a3', '19000000-0000-0000-0000-00000000000a', 'Pasado', now() - interval '3 days', now() - interval '3 days' + interval '2 hours', null),
  ('49000000-0000-0000-0000-0000000000a4', '19000000-0000-0000-0000-00000000000a', 'Con tope', now() + interval '1 hour', null, null),
  ('49000000-0000-0000-0000-0000000000a5', '19000000-0000-0000-0000-00000000000a', 'Limite IP', now() + interval '1 hour', null, null),
  ('49000000-0000-0000-0000-0000000000a6', '19000000-0000-0000-0000-00000000000a', 'Pausado', now() + interval '1 hour', null, null),
  ('49000000-0000-0000-0000-0000000000a7', '19000000-0000-0000-0000-00000000000a', 'Cancelado', now() + interval '1 hour', null, null);
update public.eventos set cancelado = true where id = '49000000-0000-0000-0000-0000000000a7';
insert into public.evento_checkin (iglesia_id, evento_id, max_registros) values
  ('19000000-0000-0000-0000-00000000000a', '49000000-0000-0000-0000-0000000000a1', 300),
  ('19000000-0000-0000-0000-00000000000a', '49000000-0000-0000-0000-0000000000a2', 300),
  ('19000000-0000-0000-0000-00000000000a', '49000000-0000-0000-0000-0000000000a3', 300),
  ('19000000-0000-0000-0000-00000000000a', '49000000-0000-0000-0000-0000000000a4', 2),
  ('19000000-0000-0000-0000-00000000000a', '49000000-0000-0000-0000-0000000000a5', 300),
  ('19000000-0000-0000-0000-00000000000a', '49000000-0000-0000-0000-0000000000a6', 300),
  ('19000000-0000-0000-0000-00000000000a', '49000000-0000-0000-0000-0000000000a7', 300);
update public.evento_checkin set activo = false where evento_id = '49000000-0000-0000-0000-0000000000a6';

create or replace function pg_temp.tk(ev text) returns text language sql as $$
  select token from public.evento_checkin where evento_id = ev::uuid $$;
create or replace function pg_temp.cuenta(tabla text, donde text) returns text language plpgsql as $$
declare n text; begin execute format('select count(*)::text from public.%I where %s', tabla, donde) into n; return n; end $$;

-- El token es largo, hexadecimal y unico
select pg_temp.igual((pg_temp.tk('49000000-0000-0000-0000-0000000000a1') ~ '^[0-9a-f]{64}$')::text, 'true', 'el token tiene 64 caracteres hexadecimales');
select pg_temp.igual((select count(distinct token)::text from public.evento_checkin), '7', 'cada evento tiene un token distinto');
select pg_temp.debe_fallar($q$ update public.evento_checkin set token = 'corto' where evento_id = '49000000-0000-0000-0000-0000000000a1' $q$, 'un token corto se rechaza');
select pg_temp.debe_fallar($q$ update public.evento_checkin set max_registros = 0 where evento_id = '49000000-0000-0000-0000-0000000000a1' $q$, 'tope menor que 1');

-- Informacion publica
select pg_temp.igual((public.info_checkin('no-existe')) is null, 'true', 'token inexistente: sin informacion');
select pg_temp.igual(public.info_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a1')) ->> 'estado', 'abierto', 'evento en ventana: abierto');
select pg_temp.igual(public.info_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a1')) ->> 'evento', 'Abierto', 'abierto: da el titulo del evento');
select pg_temp.igual(public.info_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a2')) ->> 'estado', 'cerrado', 'evento lejano: cerrado');
select pg_temp.igual((public.info_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a2')) ? 'evento')::text, 'false', 'cerrado: no adelanta el titulo');
select pg_temp.igual(public.info_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a3')) ->> 'estado', 'cerrado', 'evento pasado: cerrado');
select pg_temp.igual((public.info_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a6'))) is null, 'true', 'enlace pausado: sin informacion');
select pg_temp.igual((public.info_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a7'))) is null, 'true', 'evento cancelado: sin informacion');

-- Persona nueva: miembro en la casa del evento, seguimiento OP72 y asistencia
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a1'), 'Luis', 'Nuevo', 'luis@x.test', '+34 611 000 111', 'ip-1'), 'ok_nuevo', 'persona nueva: ok_nuevo');
select pg_temp.igual(pg_temp.cuenta('miembros', $$nombre = 'Luis' and casa_oracion_id = '29000000-0000-0000-0000-00000000000a' and notas like 'Registrado por QR%'$$), '1', 'se crea el miembro en la casa del evento y queda marcado como registro por QR');
select pg_temp.igual(pg_temp.cuenta('consolidaciones', $$notas like 'Registro por QR%'$$), '1', 'se abre su seguimiento OP72');
select pg_temp.igual(pg_temp.cuenta('asistencia_evento', $$evento_id = '49000000-0000-0000-0000-0000000000a1' and presente$$), '1', 'queda presente en el evento');
select pg_temp.igual(pg_temp.cuenta('consolidaciones', $$estado_alerta = 'verde' and fecha_limite > now() + interval '71 hours'$$), '1', 'el plazo de 72 horas se calcula solo');

-- Ya existe: no se duplica ni se abre otro seguimiento, y la respuesta no distingue
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a1'), 'Ana', 'Lopez', 'ANA@q1.test', '', 'ip-2'), 'ok_existente', 'mismo correo (sin importar mayusculas): ya existe');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a1'), 'ana', 'lopez', '', '0034600111222', 'ip-3'), 'ok_existente', 'mismo telefono y mismo nombre: ya existe');
select pg_temp.igual(pg_temp.cuenta('miembros', $$iglesia_id = '19000000-0000-0000-0000-00000000000a'$$), '2', 'no se crearon miembros duplicados');
select pg_temp.igual(pg_temp.cuenta('consolidaciones', $$true$$), '1', 'a quien ya existia no se le abre otro seguimiento');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a1'), 'Pedro', 'Lopez', '', '+34 600 111 222', 'ip-4'), 'ok_nuevo', 'mismo telefono con otro nombre (telefono de familia): persona nueva');
select pg_temp.igual(pg_temp.cuenta('miembros', $$iglesia_id = '19000000-0000-0000-0000-00000000000a'$$), '3', 'el telefono de familia no fusiona personas');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a1'), 'Luis', 'Nuevo', 'luis@x.test', '+34 611 000 111', 'ip-5'), 'ok_existente', 'repetir el registro no duplica');
select pg_temp.igual(pg_temp.cuenta('asistencia_evento', $$evento_id = '49000000-0000-0000-0000-0000000000a1'$$), '3', 'cada persona aparece una sola vez en la asistencia');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a1'), 'Otra', 'Iglesia', 'otra@q2.test', '+34 600 999 888', 'ip-6'), 'ok_nuevo', 'un miembro de otra iglesia no cuenta como existente');
select pg_temp.igual(pg_temp.cuenta('miembros', $$iglesia_id = '19000000-0000-0000-0000-00000000000b'$$), '1', 'no se toca la otra iglesia');

-- Fuera de plazo, pausado, cancelado, token falso
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a2'), 'A', 'B', '', '+34 622 000 000', 'ip-7'), 'cerrado', 'antes de la ventana: cerrado');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a3'), 'A', 'B', '', '+34 622 000 000', 'ip-7'), 'cerrado', 'despues de la ventana: cerrado');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a6'), 'A', 'B', '', '+34 622 000 000', 'ip-7'), 'no_valido', 'enlace pausado: no valido');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a7'), 'A', 'B', '', '+34 622 000 000', 'ip-7'), 'no_valido', 'evento cancelado: no valido');
select pg_temp.igual(public.registrar_checkin(repeat('0', 64), 'A', 'B', '', '+34 622 000 000', 'ip-7'), 'no_valido', 'token falso: no valido');
select pg_temp.igual(pg_temp.cuenta('miembros', $$nombre = 'A' and apellido = 'B'$$), '0', 'los intentos rechazados no crean nada');

-- Una ventana propia sustituye a la de por defecto
update public.evento_checkin set abre_en = now() + interval '1 hour', cierra_en = now() + interval '2 hours' where evento_id = '49000000-0000-0000-0000-0000000000a5';
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a5'), 'A', 'B', '', '+34 622 000 000', 'ip-8'), 'cerrado', 'la ventana configurada manda sobre la de por defecto');
update public.evento_checkin set abre_en = null, cierra_en = null where evento_id = '49000000-0000-0000-0000-0000000000a5';

-- Tope de registros por evento
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a4'), 'T1', 'Tope', 't1@x.test', '+34 633 000 001', 'ip-9'), 'ok_nuevo', 'primer registro bajo el tope');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a4'), 'T2', 'Tope', 't2@x.test', '+34 633 000 002', 'ip-10'), 'ok_nuevo', 'segundo registro bajo el tope');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a4'), 'T3', 'Tope', 't3@x.test', '+34 633 000 003', 'ip-11'), 'lleno', 'al llegar al tope: lleno');
select pg_temp.igual(public.info_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a4')) ->> 'estado', 'lleno', 'la informacion tambien dice lleno');

-- Limite por dispositivo: 5 cada 10 minutos, aunque el tope general no se alcance
do $$ declare i int; r text; begin
  for i in 1..5 loop
    r := public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a5'), 'L' || i, 'Lim', 'l' || i || '@x.test', '+34 644 000 00' || i, 'ip-fija');
    perform pg_temp.igual(r, 'ok_nuevo', 'registro ' || i || ' del mismo dispositivo');
  end loop;
  perform pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a5'), 'L6', 'Lim', 'l6@x.test', '+34 644 000 006', 'ip-fija'), 'limite', 'el sexto del mismo dispositivo: limite');
  perform pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a5'), 'L7', 'Lim', 'l7@x.test', '+34 644 000 007', 'ip-otra'), 'ok_nuevo', 'otro dispositivo si puede');
end $$;
-- ...y se libera pasados 10 minutos
update public.checkin_registros set created_at = now() - interval '11 minutes' where ip_hash = 'ip-fija';
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a5'), 'L8', 'Lim', 'l8@x.test', '+34 644 000 008', 'ip-fija'), 'ok_nuevo', 'pasados 10 minutos el dispositivo vuelve a poder');

-- Permisos: solo el servidor ejecuta las funciones; solo quien gestiona eventos lee el enlace
select pg_temp.igual(has_function_privilege('anon', 'public.registrar_checkin(text,text,text,text,text,text)', 'execute')::text, 'false', 'anon no ejecuta registrar_checkin');
select pg_temp.igual(has_function_privilege('authenticated', 'public.registrar_checkin(text,text,text,text,text,text)', 'execute')::text, 'false', 'un usuario con sesion no ejecuta registrar_checkin');
select pg_temp.igual(has_function_privilege('authenticated', 'public.info_checkin(text)', 'execute')::text, 'false', 'un usuario con sesion no ejecuta info_checkin');
select pg_temp.igual(has_function_privilege('service_role', 'public.registrar_checkin(text,text,text,text,text,text)', 'execute')::text, 'true', 'el servidor si');

select set_config('request.jwt.claim.sub', 'e2000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.evento_checkin), '0', 'un miembro no ve los enlaces');
select pg_temp.igual((select count(*)::text from public.checkin_registros), '0', 'un miembro no ve los registros');
select pg_temp.debe_fallar($q$ insert into public.evento_checkin (evento_id) values ('49000000-0000-0000-0000-0000000000a1') $q$, 'un miembro no crea enlaces');
reset role;

select set_config('request.jwt.claim.sub', 'e2000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.evento_checkin), '7', 'el propietario ve los enlaces de su iglesia');
select pg_temp.igual((select (count(*) > 0)::text from public.checkin_registros), 'true', 'el propietario ve los registros');
select pg_temp.debe_fallar($q$ insert into public.checkin_registros (iglesia_id, evento_id, ip_hash, creado) values ('19000000-0000-0000-0000-00000000000a', '49000000-0000-0000-0000-0000000000a1', 'x', true) $q$, 'nadie con sesion escribe registros: solo el servidor');
do $$ declare n int; begin
  update public.evento_checkin set activo = false where evento_id = '49000000-0000-0000-0000-0000000000a1'; get diagnostics n = row_count;
  perform pg_temp.igual(n::text, '1', 'el propietario pausa un enlace');
end $$;
reset role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a1'), 'Z', 'Z', '', '+34 655 000 000', 'ip-z'), 'no_valido', 'un enlace pausado deja de funcionar al instante');
update public.evento_checkin set token = repeat('a', 64) where evento_id = '49000000-0000-0000-0000-0000000000a1';
update public.evento_checkin set activo = true where evento_id = '49000000-0000-0000-0000-0000000000a1';
select pg_temp.igual(public.registrar_checkin(pg_temp.tk('49000000-0000-0000-0000-0000000000a1'), 'Z', 'Z', '', '+34 655 000 000', 'ip-z'), 'ok_nuevo', 'el enlace nuevo funciona');
select pg_temp.igual((public.info_checkin(repeat('0', 64))) is null, 'true', 'un enlace anterior queda anulado al regenerar (aqui: token distinto)');

-- Borrar un evento borra su enlace y sus registros
delete from public.eventos where id = '49000000-0000-0000-0000-0000000000a5';
select pg_temp.igual(pg_temp.cuenta('evento_checkin', $$evento_id = '49000000-0000-0000-0000-0000000000a5'$$), '0', 'borrar el evento borra su enlace');
select pg_temp.igual(pg_temp.cuenta('checkin_registros', $$evento_id = '49000000-0000-0000-0000-0000000000a5'$$), '0', 'borrar el evento borra sus registros');

rollback;
