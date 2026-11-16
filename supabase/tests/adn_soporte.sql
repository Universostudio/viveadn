-- Soporte dentro de la plataforma: tickets, novedades y avisos masivos. Aislamiento entre iglesias, permisos, estados, límites, repartos por destino y seguridad
-- por filas. Todo dentro de una transacción que se deshace.
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
create or replace function pg_temp.filas(sentencia text) returns text language plpgsql as $$
declare n integer;
begin execute sentencia; get diagnostics n = row_count; return n::text; end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.falla(text, text, text), pg_temp.filas(text) to authenticated, anon, service_role;

insert into auth.users (id) values ('b2a00000-0000-0000-0000-000000000001'), ('b2a00000-0000-0000-0000-000000000002'), ('b2a00000-0000-0000-0000-000000000003');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, etapa, es_demo) values
  ('b2a10000-0000-0000-0000-00000000000a', 'Prueba Soporte A', 'prueba-soporte-a', 'ES', 'Sevilla', 'premium', 'activa', false),
  ('b2a10000-0000-0000-0000-00000000000b', 'Prueba Soporte B', 'prueba-soporte-b', 'ES', 'Sevilla', 'premium', 'prueba', false),
  ('b2a10000-0000-0000-0000-00000000000c', 'Prueba Soporte C', 'prueba-soporte-c', 'ES', 'Sevilla', 'semilla', 'receso', false),
  ('b2a10000-0000-0000-0000-00000000000d', 'Prueba Soporte D demo', 'prueba-soporte-d', 'ES', 'Sevilla', 'premium', 'activa', true),
  ('b2a10000-0000-0000-0000-00000000000e', 'Prueba Soporte E', 'prueba-soporte-e', 'ES', 'Sevilla', 'semilla', 'activa', false);
-- E está en baja (borrado suave)
update public.iglesias set etapa = 'suspendida', borrado_programado_en = now() + interval '20 days', adn_borrada_en = now() where id = 'b2a10000-0000-0000-0000-00000000000e';
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('b2a00000-0000-0000-0000-000000000001', 'b2a10000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@soporte.test', 'propietario', true),
  ('b2a00000-0000-0000-0000-000000000002', 'b2a10000-0000-0000-0000-00000000000a', 'C', 'A', 'ca@soporte.test', 'colaborador', true),
  ('b2a00000-0000-0000-0000-000000000003', 'b2a10000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@soporte.test', 'propietario', true);

-- ============ (a) Tickets
select set_config('request.jwt.claim.sub', 'b2a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.adn_ticket_crear('No me deja guardar', 'alta', 'Al guardar un miembro sale un error.') as id \gset t1_
select pg_temp.igual((select asunto || '/' || prioridad || '/' || estado || '/' || (iglesia_id = 'b2a10000-0000-0000-0000-00000000000a')::text || '/' || (creado_por = 'b2a00000-0000-0000-0000-000000000001')::text from public.adn_tickets where id = :'t1_id'),
  'No me deja guardar/alta/abierto/true/true', 'la propietaria de A abre un ticket: queda de su iglesia, a su nombre y abierto');
select pg_temp.igual((select count(*)::text || '/' || min(autor_tipo) from public.adn_ticket_mensajes where ticket_id = :'t1_id'), '1/iglesia', 'con su primer mensaje');
select pg_temp.falla($$select public.adn_ticket_crear('ab', 'normal', 'texto')$$, '23514', 'un asunto de menos de 3 letras se rechaza');
select pg_temp.falla($$select public.adn_ticket_crear('Asunto válido', 'urgentisima', 'texto')$$, '23514', 'una prioridad desconocida se rechaza');
select pg_temp.falla($$select public.adn_ticket_crear('Asunto válido', 'normal', '   ')$$, '23514', 'un texto vacío se rechaza');
select pg_temp.falla($$insert into public.adn_tickets (asunto, estado) values ('Quiero cerrarlo yo', 'cerrado')$$, '42501', 'la iglesia no fija el estado');
select pg_temp.falla($$insert into public.adn_tickets (asunto, iglesia_id) values ('A nombre de otra', 'b2a10000-0000-0000-0000-00000000000b')$$, '42501', 'ni la iglesia a la que pertenece el ticket');
select pg_temp.falla($$update public.adn_tickets set estado = 'cerrado' where id = (select id from public.adn_tickets limit 1)$$, '42501', 'la iglesia no edita tickets');
select pg_temp.falla($$delete from public.adn_tickets$$, '42501', 'ni los borra');
select pg_temp.falla($$delete from public.adn_ticket_mensajes$$, '42501', 'ni borra mensajes');
insert into public.adn_ticket_mensajes (ticket_id, texto) values (:'t1_id', 'Sigue pasando.');
select pg_temp.igual((select count(*)::text from public.adn_ticket_mensajes where ticket_id = :'t1_id'), '2', 'la iglesia añade un mensaje a su ticket');
reset role;

-- Un colaborador (sin iglesia.configurar) ni ve ni abre tickets
select set_config('request.jwt.claim.sub', 'b2a00000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_tickets), '0', 'un colaborador no ve los tickets de su iglesia');
select pg_temp.igual((select count(*)::text from public.adn_ticket_mensajes), '0', 'ni sus mensajes');
select pg_temp.falla($$select public.adn_ticket_crear('Desde colaborador', 'normal', 'texto')$$, '42501', 'ni abre uno');
select pg_temp.falla($$insert into public.adn_ticket_mensajes (ticket_id, texto) values ('$$ || :'t1_id' || $$', 'intruso')$$, '42501', 'ni escribe en uno ajeno');
reset role;

-- Otra iglesia no ve ni toca los de A
select set_config('request.jwt.claim.sub', 'b2a00000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_tickets), '0', 'B no ve los tickets de A');
select pg_temp.igual((select count(*)::text from public.adn_ticket_mensajes), '0', 'ni sus mensajes');
select pg_temp.falla($$insert into public.adn_ticket_mensajes (ticket_id, texto) values ('$$ || :'t1_id' || $$', 'intruso de B')$$, '42501', 'B no escribe en el ticket de A');
select pg_temp.falla($$insert into public.adn_ticket_mensajes (ticket_id, texto) values (gen_random_uuid(), 'a un ticket que no existe')$$, 'ADN_TICKET_INEXISTENTE', 'ni en uno que no existe');
select pg_temp.igual(public.adn_ticket_crear('Ticket de B', 'baja', 'Hola')::text is not null::text, 'true', 'B abre el suyo');
reset role;
select pg_temp.igual((select count(*)::text from public.adn_ticket_mensajes where texto = 'intruso de B'), '0', 'no se coló ningún mensaje');

-- La plataforma responde y cierra (service_role): cambia el estado y la conversación cerrada no admite mensajes
insert into public.adn_ticket_mensajes (ticket_id, autor_tipo, autor, texto) values (:'t1_id', 'plataforma', null, 'Estamos mirándolo.');
select pg_temp.igual((select estado from public.adn_tickets where id = :'t1_id'), 'respondido', 'una respuesta de la plataforma deja el ticket «respondido»');
select set_config('request.jwt.claim.sub', 'b2a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into public.adn_ticket_mensajes (ticket_id, texto) values (:'t1_id', 'Gracias, ya no pasa.');
reset role;
select pg_temp.igual((select estado from public.adn_tickets where id = :'t1_id'), 'abierto', 'y un mensaje de la iglesia lo reabre');
select pg_temp.falla($$update public.adn_tickets set estado = 'cerrado' where id = '$$ || :'t1_id' || $$'$$, '23514', 'cerrar exige la fecha de cierre (restricción de coherencia)');
update public.adn_tickets set estado = 'cerrado', cerrado_en = now() where id = :'t1_id';
select set_config('request.jwt.claim.sub', 'b2a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.falla($$insert into public.adn_ticket_mensajes (ticket_id, texto) values ('$$ || :'t1_id' || $$', 'después de cerrado')$$, 'ADN_TICKET_CERRADO', 'un ticket cerrado no admite mensajes');
reset role;

-- Límites: diez sin cerrar por iglesia; doscientos mensajes por ticket
insert into public.adn_tickets (iglesia_id, creado_por, asunto) select 'b2a10000-0000-0000-0000-00000000000a', 'b2a00000-0000-0000-0000-000000000001', 'Ticket ' || n from generate_series(1, 10) n;
select pg_temp.falla($$insert into public.adn_tickets (iglesia_id, creado_por, asunto) values ('b2a10000-0000-0000-0000-00000000000a', 'b2a00000-0000-0000-0000-000000000001', 'El undécimo')$$, 'ADN_DEMASIADOS_TICKETS', 'el undécimo ticket sin cerrar se rechaza (el cerrado no cuenta)');
update public.adn_tickets set estado = 'cerrado', cerrado_en = now() where asunto = 'Ticket 1';
insert into public.adn_tickets (iglesia_id, creado_por, asunto) values ('b2a10000-0000-0000-0000-00000000000a', 'b2a00000-0000-0000-0000-000000000001', 'Cabe otro');
select pg_temp.igual((select count(*)::text from public.adn_tickets where iglesia_id = 'b2a10000-0000-0000-0000-00000000000a' and estado <> 'cerrado'), '10', 'al cerrar uno se libera un hueco');
select id as t2_id from public.adn_tickets where asunto = 'Ticket 2' \gset
insert into public.adn_ticket_mensajes (ticket_id, autor_tipo, texto) select :'t2_id', 'plataforma', 'm' || n from generate_series(1, 200) n;
select pg_temp.falla($$insert into public.adn_ticket_mensajes (ticket_id, autor_tipo, texto) values ('$$ || :'t2_id' || $$', 'plataforma', 'el 201')$$, 'ADN_TICKET_LLENO', 'un ticket admite como mucho doscientos mensajes');

-- Sin sesión, nada
set local role anon;
select pg_temp.falla($$select count(*) from public.adn_tickets$$, '42501', 'sin sesión no se leen tickets');
select pg_temp.falla($$select public.adn_ticket_crear('Anónimo', 'normal', 'texto')$$, '42501', 'ni se abren');
reset role;

-- ============ (b) Novedades
insert into public.adn_novedades (id, version, titulo, texto) values
  ('b2a30000-0000-0000-0000-000000000001', '1.1.0', 'Seguimiento configurable', 'Ahora eliges el método de seguimiento.'),
  ('b2a30000-0000-0000-0000-000000000002', '1.0.9', 'Retirada', 'Esto se retiró.');
update public.adn_novedades set retirada_en = now() where id = 'b2a30000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub', 'b2a00000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select string_agg(version, ',') from public.adn_novedades), '1.1.0', 'cualquier persona con sesión lee las novedades publicadas, no las retiradas');
select pg_temp.falla($$insert into public.adn_novedades (version, titulo, texto) values ('9', 'Falsa novedad', 'texto')$$, '42501', 'pero no las publica');
select pg_temp.falla($$update public.adn_novedades set texto = 'cambiado'$$, '42501', 'ni las edita');
select public.adn_novedades_marcar_vistas();
select pg_temp.igual((select count(*)::text from public.adn_novedades_vistas), '1', 'marcar como vistas crea su fila');
select public.adn_novedades_marcar_vistas();
select pg_temp.igual((select count(*)::text from public.adn_novedades_vistas), '1', 'y repetirlo la actualiza, no la duplica');
select pg_temp.igual((select (iglesia_id = 'b2a10000-0000-0000-0000-00000000000a')::text from public.adn_novedades_vistas), 'true', 'con la iglesia de la persona');
select pg_temp.falla($$insert into public.adn_novedades_vistas (usuario, vista_en) values ('b2a00000-0000-0000-0000-000000000001', now())$$, '42501', 'no se marca por otra persona');
reset role;
select set_config('request.jwt.claim.sub', 'b2a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_novedades_vistas), '0', 'cada persona ve solo su marca');
reset role;
set local role anon;
select pg_temp.falla($$select count(*) from public.adn_novedades$$, '42501', 'sin sesión no se leen las novedades');
reset role;

-- ============ (c) Avisos masivos
select pg_temp.falla($$insert into public.adn_avisos (tipo, titulo, texto, destino) values ('alerta', 'Aviso', 'texto', '{}'::jsonb)$$, '23514', 'un destino vacío se rechaza');
select pg_temp.falla($$insert into public.adn_avisos (tipo, titulo, texto, destino) values ('alerta', 'Aviso', 'texto', '{"x": 1}'::jsonb)$$, '23514', 'ni uno con claves desconocidas');
select pg_temp.falla($$insert into public.adn_avisos (tipo, titulo, texto, destino) values ('alerta', 'Aviso', 'texto', '{"planes": []}'::jsonb)$$, '23514', 'ni una lista de planes vacía');
select pg_temp.falla($$insert into public.adn_avisos (tipo, titulo, texto, destino) values ('alerta', 'Aviso', 'texto', '{"estados": ["inventado"]}'::jsonb)$$, '23514', 'ni un estado que no existe');
select pg_temp.falla($$insert into public.adn_avisos (tipo, titulo, texto) values ('publicidad', 'Aviso', 'texto')$$, '23514', 'ni un tipo desconocido');
select pg_temp.falla($$insert into public.adn_avisos (tipo, titulo, texto, desde, hasta) values ('alerta', 'Aviso', 'texto', now(), now() - interval '1 day')$$, '23514', 'ni una vigencia que acaba antes de empezar');
select pg_temp.falla($$insert into public.adn_avisos (tipo, titulo, texto, por_correo) values ('alerta', 'Aviso', 'texto', true)$$, '23514', 'pedir correo exige anotar su estado');
select pg_temp.falla($$insert into public.adn_avisos (tipo, titulo, texto, correo_estado) values ('alerta', 'Aviso', 'texto', 'apagado')$$, '23514', 'y no anotarlo si no se pidió');

insert into public.adn_avisos (id, tipo, titulo, texto, destino) values ('b2a40000-0000-0000-0000-000000000001', 'actualizacion', 'Todas', 'Mantenimiento de la noche', '{"todas": true}');
insert into public.adn_avisos (id, tipo, titulo, texto, destino, incluir_demo) values ('b2a40000-0000-0000-0000-000000000002', 'actualizacion', 'Con demos', 'x', '{"todas": true}', true);
insert into public.adn_avisos (id, tipo, titulo, texto, destino) values ('b2a40000-0000-0000-0000-000000000003', 'alerta', 'Semilla en receso', 'x', '{"planes": ["semilla"], "estados": ["receso"]}');
insert into public.adn_avisos (id, tipo, titulo, texto, destino) values ('b2a40000-0000-0000-0000-000000000004', 'alerta', 'Solo activas', 'x', '{"estados": ["activa"]}');
insert into public.adn_avisos (id, tipo, titulo, texto, destino) values ('b2a40000-0000-0000-0000-000000000005', 'alerta', 'Solo Premium', 'x', '{"planes": ["premium"]}');
select pg_temp.igual(public.adn_aviso_entregar('b2a40000-0000-0000-0000-000000000001')::text, '2', '«todas» llega a las iglesias operativas reales: A (activa) y B (prueba); no a C (receso), ni a la demo D, ni a E (en baja)');
select pg_temp.igual(public.adn_aviso_entregar('b2a40000-0000-0000-0000-000000000002')::text, '3', 'con «incluir demostraciones» entra también la demo D, pero nunca la de baja');
select pg_temp.igual(public.adn_aviso_entregar('b2a40000-0000-0000-0000-000000000003')::text, '1', 'plan semilla y estado receso: solo C');
select pg_temp.igual(public.adn_aviso_entregar('b2a40000-0000-0000-0000-000000000004')::text, '1', 'solo estado activa: A (la demo D no entra sin pedirlo, y E está en baja)');
select pg_temp.igual(public.adn_aviso_entregar('b2a40000-0000-0000-0000-000000000005')::text, '2', 'solo plan premium: las operativas premium reales, A y B');
select pg_temp.igual(public.adn_aviso_entregar('b2a40000-0000-0000-0000-000000000001')::text, '0', 'repartir dos veces no duplica las entregas');
select pg_temp.falla($$select public.adn_aviso_entregar(gen_random_uuid())$$, 'ADN_AVISO_INEXISTENTE', 'repartir un aviso que no existe falla');

select set_config('request.jwt.claim.sub', 'b2a00000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select string_agg(titulo, ',' order by titulo) from public.adn_avisos), 'Con demos,Solo Premium,Solo activas,Todas', 'cualquier persona de A ve los avisos que le llegaron a su iglesia (cuatro de los cinco)');
select pg_temp.igual((select count(*)::text from public.adn_avisos_entregas), '4', 'y sus cuatro entregas, no las de otras iglesias');
update public.adn_avisos_entregas set leido_en = now() where aviso_id = 'b2a40000-0000-0000-0000-000000000001';
update public.adn_avisos_entregas set descartado_en = now() where aviso_id = 'b2a40000-0000-0000-0000-000000000001';
select pg_temp.igual((select (leido_en is not null and descartado_en is not null)::text from public.adn_avisos_entregas where aviso_id = 'b2a40000-0000-0000-0000-000000000001'), 'true', 'la iglesia marca el aviso como leído y descartado');
select pg_temp.falla($$update public.adn_avisos_entregas set entregado_en = now()$$, '42501', 'pero no cambia cuándo se entregó');
select pg_temp.falla($$update public.adn_avisos_entregas set iglesia_id = 'b2a10000-0000-0000-0000-00000000000b'$$, '42501', 'ni a quién');
select pg_temp.falla($$insert into public.adn_avisos (tipo, titulo, texto) values ('alerta', 'Falso aviso', 'texto')$$, '42501', 'ni crea avisos');
select pg_temp.falla($$select public.adn_aviso_entregar('b2a40000-0000-0000-0000-000000000001')$$, '42501', 'ni reparte');
reset role;
select set_config('request.jwt.claim.sub', 'b2a00000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select string_agg(titulo, ',' order by titulo) from public.adn_avisos), 'Con demos,Solo Premium,Todas', 'B (premium en prueba) ve tres: no los de semilla ni «solo activas»');
select pg_temp.igual(pg_temp.filas($$update public.adn_avisos_entregas set leido_en = now() where iglesia_id = 'b2a10000-0000-0000-0000-00000000000a'$$), '0', 'B no marca las entregas de A');
select pg_temp.igual((select (leido_en is null)::text from public.adn_avisos_entregas where aviso_id = 'b2a40000-0000-0000-0000-000000000001'), 'true', 'y su aviso sigue sin leer');
reset role;
-- Vigencia y retirada
update public.adn_avisos set retirado_en = now() where id = 'b2a40000-0000-0000-0000-000000000005';
update public.adn_avisos set hasta = now() - interval '1 second', desde = now() - interval '2 days' where id = 'b2a40000-0000-0000-0000-000000000004';
update public.adn_avisos set desde = now() + interval '1 day' where id = 'b2a40000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub', 'b2a00000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select string_agg(titulo, ',') from public.adn_avisos), 'Todas', 'un aviso retirado, uno caducado y uno que aún no ha empezado dejan de verse');
reset role;
set local role anon;
select pg_temp.falla($$select count(*) from public.adn_avisos$$, '42501', 'sin sesión no se ve ningún aviso');
select pg_temp.falla($$select count(*) from public.adn_avisos_entregas$$, '42501', 'ni entregas');
reset role;
-- Registro para la plataforma: entregas, lecturas y descartes por aviso
select pg_temp.igual((select count(*)::text || '/' || count(leido_en)::text || '/' || count(descartado_en)::text from public.adn_avisos_entregas where aviso_id = 'b2a40000-0000-0000-0000-000000000001'), '2/1/1', 'el registro dice 2 entregas, 1 lectura y 1 descarte');
rollback;
