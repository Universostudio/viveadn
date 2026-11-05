-- Corte duro de los limites del plan: miembros, usuarios e invitaciones.
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
create or replace function pg_temp.limite(q text, msg text) returns void language plpgsql as $$
begin
  begin execute q; exception when check_violation then
    if sqlerrm like 'PLAN_LIMITE%' then raise notice 'OK: %', msg; return; end if;
    raise exception 'FALLO: fallo por otra causa (%): %', sqlerrm, msg;
  end;
  raise exception 'FALLO: debia rechazarse por el limite del plan: %', msg;
end $$;

grant execute on function pg_temp.igual(text, text, text), pg_temp.limite(text, text) to authenticated;

-- Semilla: 50 miembros y 3 usuarios. Premium: 5000 y sin tope de usuarios.
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('5e000000-0000-0000-0000-00000000000a', 'Prueba Semilla', 'prueba-ls1', 'ES', 'Sevilla', 'semilla'),
  ('5e000000-0000-0000-0000-00000000000b', 'Prueba Premium', 'prueba-lp1', 'ES', 'Sevilla', 'premium');

-- Miembros: 49 de una vez caben, el 50 entra y el 51 se rechaza
insert into public.miembros (iglesia_id, nombre, apellido) select '5e000000-0000-0000-0000-00000000000a', 'M' || g, 'Prueba' from generate_series(1, 49) g;
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = '5e000000-0000-0000-0000-00000000000a'), '49', 'caben 49 miembros en un solo alta');
insert into public.miembros (iglesia_id, nombre, apellido) values ('5e000000-0000-0000-0000-00000000000a', 'Cincuenta', 'Prueba');
select pg_temp.limite($q$ insert into public.miembros (iglesia_id, nombre, apellido) values ('5e000000-0000-0000-0000-00000000000a', 'Cincuenta y uno', 'Prueba') $q$, 'el miembro 51 se rechaza');
select pg_temp.limite($q$ insert into public.miembros (iglesia_id, nombre, apellido) select '5e000000-0000-0000-0000-00000000000a', 'X' || g, 'Prueba' from generate_series(1, 3) g $q$, 'una carga masiva que pasa del tope se rechaza entera');
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = '5e000000-0000-0000-0000-00000000000a'), '50', 'tras los rechazos siguen siendo 50');

-- Un miembro inactivo no cuenta; reactivarlo comprueba el tope
update public.miembros set activo = false where iglesia_id = '5e000000-0000-0000-0000-00000000000a' and nombre = 'M1';
insert into public.miembros (iglesia_id, nombre, apellido) values ('5e000000-0000-0000-0000-00000000000a', 'Reemplazo', 'Prueba');
select pg_temp.limite($q$ update public.miembros set activo = true where iglesia_id = '5e000000-0000-0000-0000-00000000000a' and nombre = 'M1' $q$, 'reactivar por encima del tope se rechaza');
update public.miembros set apellido = 'Editado' where iglesia_id = '5e000000-0000-0000-0000-00000000000a' and nombre = 'M2';
select pg_temp.igual((select apellido from public.miembros where iglesia_id = '5e000000-0000-0000-0000-00000000000a' and nombre = 'M2'), 'Editado', 'editar un miembro activo no cuenta como alta');
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = '5e000000-0000-0000-0000-00000000000b'), '0', 'otra iglesia no se ve afectada');
insert into public.miembros (iglesia_id, nombre, apellido) select '5e000000-0000-0000-0000-00000000000b', 'P' || g, 'Prueba' from generate_series(1, 120) g;
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = '5e000000-0000-0000-0000-00000000000b'), '120', 'Premium admite mucho mas que Semilla');

-- Usuarios: 3 en Semilla; Premium sin tope
insert into auth.users (id) select ('5f000000-0000-0000-0000-00000000000' || g)::uuid from generate_series(1, 9) g;
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('5f000000-0000-0000-0000-000000000001', '5e000000-0000-0000-0000-00000000000a', 'U', '1', 'u1@ls.test', 'propietario', true),
  ('5f000000-0000-0000-0000-000000000002', '5e000000-0000-0000-0000-00000000000a', 'U', '2', 'u2@ls.test', 'propietario', true),
  ('5f000000-0000-0000-0000-000000000003', '5e000000-0000-0000-0000-00000000000a', 'U', '3', 'u3@ls.test', 'miembro', true);
select pg_temp.limite($q$ insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values ('5f000000-0000-0000-0000-000000000004', '5e000000-0000-0000-0000-00000000000a', 'U', '4', 'u4@ls.test', 'miembro', true) $q$, 'el usuario 4 de Semilla se rechaza');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('5f000000-0000-0000-0000-000000000005', '5e000000-0000-0000-0000-00000000000b', 'P', '1', 'p1@lp.test', 'propietario', true),
  ('5f000000-0000-0000-0000-000000000006', '5e000000-0000-0000-0000-00000000000b', 'P', '2', 'p2@lp.test', 'propietario', true),
  ('5f000000-0000-0000-0000-000000000007', '5e000000-0000-0000-0000-00000000000b', 'P', '3', 'p3@lp.test', 'miembro', true),
  ('5f000000-0000-0000-0000-000000000008', '5e000000-0000-0000-0000-00000000000b', 'P', '4', 'p4@lp.test', 'miembro', true);
select pg_temp.igual((select count(*)::text from public.perfiles where iglesia_id = '5e000000-0000-0000-0000-00000000000b'), '4', 'Premium no tiene tope de usuarios');
-- Un usuario inactivo no cuenta: su plaza la ocupa otro, y reactivarlo comprueba el tope
update public.perfiles set activo = false where id = '5f000000-0000-0000-0000-000000000003';
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('5f000000-0000-0000-0000-000000000004', '5e000000-0000-0000-0000-00000000000a', 'U', '4', 'u4@ls.test', 'miembro', true);
select pg_temp.limite($q$ update public.perfiles set activo = true where id = '5f000000-0000-0000-0000-000000000003' $q$, 'reactivar un usuario por encima del tope se rechaza');
update public.perfiles set activo = false where id = '5f000000-0000-0000-0000-000000000004';

-- Invitaciones: una pendiente reserva su plaza (2 perfiles activos + 1 invitacion = 3)
insert into public.invitaciones (iglesia_id, email, nombre, apellido, rol, token_hash) values
  ('5e000000-0000-0000-0000-00000000000a', 'inv1@ls.test', 'I', '1', 'miembro', repeat('1', 64));
select pg_temp.limite($q$ insert into public.invitaciones (iglesia_id, email, nombre, apellido, rol, token_hash) values ('5e000000-0000-0000-0000-00000000000a', 'inv2@ls.test', 'I', '2', 'miembro', repeat('2', 64)) $q$, 'la plaza reservada por una invitacion cuenta');
update public.invitaciones set revocada_en = now() where email = 'inv1@ls.test';
insert into public.invitaciones (iglesia_id, email, nombre, apellido, rol, token_hash) values
  ('5e000000-0000-0000-0000-00000000000a', 'inv2@ls.test', 'I', '2', 'miembro', repeat('2', 64));
select pg_temp.igual('ok', 'ok', 'revocar una invitacion libera su plaza');
update public.invitaciones set caduca_en = now() - interval '1 day' where email = 'inv2@ls.test';
insert into public.invitaciones (iglesia_id, email, nombre, apellido, rol, token_hash) values
  ('5e000000-0000-0000-0000-00000000000a', 'inv3@ls.test', 'I', '3', 'miembro', repeat('3', 64));
select pg_temp.igual('ok', 'ok', 'una invitacion caducada no ocupa plaza');

-- Un colaborador solo ve lo que registra, pero el tope cuenta TODOS los miembros de la iglesia
insert into auth.users (id) values ('5f000000-0000-0000-0000-0000000000c1'), ('5f000000-0000-0000-0000-0000000000c2'), ('5f000000-0000-0000-0000-0000000000c3');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('5e000000-0000-0000-0000-00000000000c', 'Prueba Colaborador', 'prueba-ls2', 'ES', 'Sevilla', 'semilla');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('5f000000-0000-0000-0000-0000000000c1', '5e000000-0000-0000-0000-00000000000c', 'P', '1', 'p1@ls2.test', 'propietario', true),
  ('5f000000-0000-0000-0000-0000000000c2', '5e000000-0000-0000-0000-00000000000c', 'P', '2', 'p2@ls2.test', 'propietario', true),
  ('5f000000-0000-0000-0000-0000000000c3', '5e000000-0000-0000-0000-00000000000c', 'C', '1', 'c1@ls2.test', 'colaborador', true);
insert into public.miembros (iglesia_id, nombre, apellido) select '5e000000-0000-0000-0000-00000000000c', 'L' || g, 'Prueba' from generate_series(1, 50) g;
select set_config('request.jwt.claim.sub', '5f000000-0000-0000-0000-0000000000c3', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.miembros), '0', 'el colaborador no ve a los miembros que no registro');
select pg_temp.limite($q$ insert into public.miembros (iglesia_id, nombre, apellido) values ('5e000000-0000-0000-0000-00000000000c', 'Extra', 'Colab') $q$, 'un colaborador no se salta el tope aunque no vea a los demas miembros');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Reactivar un perfil no ocupa una plaza reservada por una invitacion vigente
insert into auth.users (id) values ('5f000000-0000-0000-0000-0000000000d1'), ('5f000000-0000-0000-0000-0000000000d2'), ('5f000000-0000-0000-0000-0000000000d3'), ('5f000000-0000-0000-0000-0000000000d4');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('5e000000-0000-0000-0000-00000000000d', 'Prueba Reservas', 'prueba-ls3', 'ES', 'Sevilla', 'semilla');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('5f000000-0000-0000-0000-0000000000d1', '5e000000-0000-0000-0000-00000000000d', 'P', '1', 'p1@ls3.test', 'propietario', true),
  ('5f000000-0000-0000-0000-0000000000d2', '5e000000-0000-0000-0000-00000000000d', 'P', '2', 'p2@ls3.test', 'propietario', true),
  ('5f000000-0000-0000-0000-0000000000d3', '5e000000-0000-0000-0000-00000000000d', 'I', '1', 'i1@ls3.test', 'miembro', false);
insert into public.invitaciones (id, iglesia_id, email, nombre, apellido, rol, token_hash) values
  ('5d000000-0000-0000-0000-0000000000d1', '5e000000-0000-0000-0000-00000000000d', 'inv@ls3.test', 'I', 'V', 'miembro', repeat('d', 64));
select pg_temp.limite($q$ update public.perfiles set activo = true where id = '5f000000-0000-0000-0000-0000000000d3' $q$, 'reactivar un perfil no ocupa la plaza reservada por una invitacion vigente');
-- Quien acepta la invitacion entra: reclamar la marca como usada antes de crear su perfil, y no se cuenta dos veces
update public.invitaciones set usada_en = now() where id = '5d000000-0000-0000-0000-0000000000d1';
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('5f000000-0000-0000-0000-0000000000d4', '5e000000-0000-0000-0000-00000000000d', 'I', 'V', 'inv@ls3.test', 'miembro', true);
select pg_temp.igual((select count(*)::text from public.perfiles where iglesia_id = '5e000000-0000-0000-0000-00000000000d' and activo), '3', 'quien acepta su invitacion ocupa la plaza que tenia reservada');
select pg_temp.limite($q$ update public.perfiles set activo = true where id = '5f000000-0000-0000-0000-0000000000d3' $q$, 'con las plazas llenas, reactivar sigue rechazado');

-- Las funciones de los disparadores no se ejecutan a mano
set local role authenticated;
do $$ begin
  begin perform private.limitar_plan_miembros(); raise exception 'FALLO: authenticated ejecuto el disparador'; exception when insufficient_privilege then raise notice 'OK: authenticated no ejecuta el disparador de miembros'; end;
end $$;
reset role;

rollback;
