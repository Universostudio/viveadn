-- Soporte con la prueba vencida: el propietario sigue pudiendo pedir ayuda y leer las respuestas; un rol sin permiso, no; y en receso nadie.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if exists (select 1 from public.iglesias where slug not like 'prueba-%') then raise exception 'Este script no se ejecuta en una base con iglesias reales'; end if;
end $$;
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
create or replace function pg_temp.falla(sentencia text, texto text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if sqlerrm not like '%' || texto || '%' and sqlstate <> texto then raise exception 'FALLO: % (error inesperado % %)', msg, sqlstate, sqlerrm; end if;
    raise notice 'OK: % (%)', msg, sqlstate; return;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.falla(text, text, text) to authenticated;
insert into auth.users (id) values ('b4a00000-0000-0000-0000-000000000001'), ('b4a00000-0000-0000-0000-000000000002');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, etapa) values ('b4a10000-0000-0000-0000-00000000000a', 'Prueba Ayuda', 'prueba-ayuda', 'ES', 'Sevilla', 'basico', 'prueba');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('b4a00000-0000-0000-0000-000000000001', 'b4a10000-0000-0000-0000-00000000000a', 'P', 'A', 'p@ayuda.test', 'propietario', true),
  ('b4a00000-0000-0000-0000-000000000002', 'b4a10000-0000-0000-0000-00000000000a', 'C', 'A', 'c@ayuda.test', 'colaborador', true);

-- Prueba vencida: el propietario abre un ticket y lo lee
update public.iglesias set prueba_hasta = now() - interval '2 days' where slug = 'prueba-ayuda';
select set_config('request.jwt.claim.sub', 'b4a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select private.tiene_permiso('iglesia.configurar')::text), 'false', 'con la prueba vencida el propietario ya no tiene iglesia.configurar');
select public.adn_ticket_crear('Mi prueba terminó', 'normal', 'Necesito saber cómo seguir.') as id \gset t_
select pg_temp.igual((select count(*)::text from public.adn_tickets where id = :'t_id'), '1', 'con la prueba vencida el propietario abre un ticket y lo lee');
insert into public.adn_ticket_mensajes (ticket_id, texto) values (:'t_id', 'Gracias.');
select pg_temp.igual((select count(*)::text from public.adn_ticket_mensajes where ticket_id = :'t_id'), '2', 'y escribe en él');
reset role;
select set_config('request.jwt.claim.sub', '', true);
-- Responde la plataforma (servidor)
insert into public.adn_ticket_mensajes (ticket_id, autor_tipo, texto) values (:'t_id', 'plataforma', 'Elige un plan y vuelves a editar.');
select set_config('request.jwt.claim.sub', 'b4a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_ticket_mensajes where ticket_id = :'t_id' and autor_tipo = 'plataforma'), '1', 'y lee la respuesta de la plataforma');
reset role;

-- Un colaborador, sin permiso de configurar, no ve ni abre tickets
select set_config('request.jwt.claim.sub', 'b4a00000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_tickets), '0', 'un colaborador no ve los tickets de la iglesia');
select pg_temp.falla($$select public.adn_ticket_crear('Intento', 'normal', 'texto')$$, '42501', 'ni abre uno');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- En receso (sin acceso) ni el propietario
update public.iglesias set etapa = 'receso' where slug = 'prueba-ayuda';
select set_config('request.jwt.claim.sub', 'b4a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_tickets), '0', 'en receso el propietario no ve tickets');
select pg_temp.falla($$select public.adn_ticket_crear('Intento', 'normal', 'texto')$$, '42501', 'ni abre uno');
reset role;
rollback;
