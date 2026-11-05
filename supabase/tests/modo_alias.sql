-- Modo alias: la base no guarda apellido ni correo de los miembros nuevos de una iglesia en ese modo.
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

insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, modo_alias) values
  ('1a000000-0000-0000-0000-00000000000a', 'Prueba Alias', 'prueba-alias', 'ES', 'Sevilla', 'premium', true),
  ('1a000000-0000-0000-0000-00000000000b', 'Prueba Normal', 'prueba-normal', 'ES', 'Sevilla', 'premium', false);
insert into public.eventos (id, iglesia_id, titulo, inicia_en) values
  ('4a000000-0000-0000-0000-0000000000a1', '1a000000-0000-0000-0000-00000000000a', 'Evento alias', now() + interval '1 hour'),
  ('4a000000-0000-0000-0000-0000000000b1', '1a000000-0000-0000-0000-00000000000b', 'Evento normal', now() + interval '1 hour');
insert into public.evento_checkin (iglesia_id, evento_id, token) values
  ('1a000000-0000-0000-0000-00000000000a', '4a000000-0000-0000-0000-0000000000a1', repeat('a', 64)),
  ('1a000000-0000-0000-0000-00000000000b', '4a000000-0000-0000-0000-0000000000b1', repeat('b', 64));

-- Alta directa
insert into public.miembros (iglesia_id, nombre, apellido, email, telefono) values
  ('1a000000-0000-0000-0000-00000000000a', 'Roble-01', 'Perez', 'real@correo.test', '+34 600 111 111'),
  ('1a000000-0000-0000-0000-00000000000b', 'Ana', 'Lopez', 'ana@correo.test', '+34 600 222 222');
select pg_temp.igual((select apellido || '|' || coalesce(email, 'nulo') from public.miembros where nombre = 'Roble-01'), '|nulo', 'en modo alias no se guardan apellido ni correo');
select pg_temp.igual((select telefono from public.miembros where nombre = 'Roble-01'), '+34 600 111 111', 'el telefono se conserva para la llamada de las 72 horas');
select pg_temp.igual((select apellido || '|' || email from public.miembros where nombre = 'Ana'), 'Lopez|ana@correo.test', 'sin modo alias nada cambia');

-- Edicion: solo se limpia lo que se intenta cambiar
update public.miembros set email = 'otro@correo.test', notas = 'n' where nombre = 'Roble-01';
select pg_temp.igual((select coalesce(email, 'nulo') || '|' || notas from public.miembros where nombre = 'Roble-01'), 'nulo|n', 'editar no permite poner un correo en modo alias y conserva el resto');
update public.miembros set apellido = 'Gomez' where nombre = 'Roble-01';
select pg_temp.igual((select apellido from public.miembros where nombre = 'Roble-01'), '', 'editar no permite poner un apellido en modo alias');

-- Una iglesia que ya tenia miembros no pierde datos al activar el modo
update public.iglesias set modo_alias = true where slug = 'prueba-normal';
select pg_temp.igual((select apellido || '|' || email from public.miembros where nombre = 'Ana'), 'Lopez|ana@correo.test', 'activar el modo no borra a los miembros que ya existian');
update public.miembros set notas = 'editada' where nombre = 'Ana';
select pg_temp.igual((select apellido || '|' || email from public.miembros where nombre = 'Ana'), 'Lopez|ana@correo.test', 'editar otro campo de un miembro antiguo tampoco borra nada');
update public.iglesias set modo_alias = false where slug = 'prueba-normal';

-- Registro por QR
select pg_temp.igual((public.info_checkin(repeat('a', 64)) ->> 'alias'), 'true', 'la pagina de registro sabe que la iglesia pide alias');
select pg_temp.igual((public.info_checkin(repeat('b', 64)) ->> 'alias'), 'false', 'y que la otra pide nombre y apellido');
select pg_temp.igual(public.registrar_checkin(repeat('a', 64), 'Cedro-07', '', '', '+34 600 333 333', 'ip1'), 'ok_nuevo', 'en modo alias el registro acepta alias sin apellido');
select pg_temp.igual((select apellido || '|' || coalesce(email, 'nulo') from public.miembros where nombre = 'Cedro-07'), '|nulo', 'y el miembro creado no tiene apellido ni correo');
select pg_temp.igual(public.registrar_checkin(repeat('a', 64), 'Cedro-07', '', '', '+34 600 333 333', 'ip2'), 'ok_existente', 'el mismo alias con el mismo telefono no se duplica');
select pg_temp.igual(public.registrar_checkin(repeat('b', 64), 'Pedro', '', '', '+34 600 444 444', 'ip3'), 'datos', 'sin modo alias el apellido sigue siendo obligatorio');
select pg_temp.igual(public.registrar_checkin(repeat('b', 64), 'Pedro', 'Gil', 'pedro@correo.test', '+34 600 444 444', 'ip3'), 'ok_nuevo', 'y con apellido se registra con normalidad');
select pg_temp.igual((select email from public.miembros where nombre = 'Pedro'), 'pedro@correo.test', 'sin modo alias se guarda el correo');
rollback;
