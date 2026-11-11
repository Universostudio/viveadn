-- Evidencia del consentimiento: el registro por QR anota la versión del texto aceptado y la importación guarda el
-- valor original del archivo. Es solo evidencia: no concede consentimiento ni cambia a quién se le envía.
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
create or replace function pg_temp.ev(p_miembro text, p_donde text default 'true') returns text language plpgsql as $$
declare n text;
begin
  execute format('select count(*)::text from public.adn_consentimiento_evidencias e where e.miembro_id = (select id from public.miembros where email = %L limit 1) and %s', p_miembro, p_donde) into n;
  return n;
end $$;
grant execute on function pg_temp.ev(text, text) to authenticated, service_role;

insert into auth.users (id) select ('af500000-0000-0000-0000-00000000000' || n)::uuid from generate_series(1, 4) n;
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('af510000-0000-0000-0000-00000000000a', 'Prueba Canales A', 'prueba-canales-a', 'ES', 'Sevilla', 'premium'),
  ('af510000-0000-0000-0000-00000000000b', 'Prueba Canales B', 'prueba-canales-b', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('af500000-0000-0000-0000-000000000001', 'af510000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@canales.test', 'propietario', true),
  ('af500000-0000-0000-0000-000000000002', 'af510000-0000-0000-0000-00000000000a', 'Adm', 'A', 'adm@canales.test', 'administrador', true),
  ('af500000-0000-0000-0000-000000000003', 'af510000-0000-0000-0000-00000000000a', 'Col', 'A', 'col@canales.test', 'colaborador', true),
  ('af500000-0000-0000-0000-000000000004', 'af510000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@canales.test', 'propietario', true);
insert into public.eventos (id, iglesia_id, titulo, inicia_en, termina_en) values
  ('af520000-0000-0000-0000-0000000000a1', 'af510000-0000-0000-0000-00000000000a', 'Culto', now() + interval '1 hour', null);
insert into public.evento_checkin (iglesia_id, evento_id, max_registros) values
  ('af510000-0000-0000-0000-00000000000a', 'af520000-0000-0000-0000-0000000000a1', 300);
create or replace function pg_temp.tk() returns text language sql as $$
  select token from public.evento_checkin where evento_id = 'af520000-0000-0000-0000-0000000000a1' $$;
grant execute on function pg_temp.tk() to service_role;


create or replace function pg_temp.est(p_email text, p_canal text) returns text language sql as $$
  select coalesce((select estado from public.adn_consentimientos where miembro_id = (select id from public.miembros where email = p_email limit 1) and canal = p_canal), 'sin registro') $$;
grant execute on function pg_temp.est(text, text) to authenticated, service_role;
create or replace function pg_temp.cancelar(p_email text, p_canal text) returns void language sql as $$
  select private.adn_escribir_consentimiento(m.iglesia_id, m.id, p_canal, 'cancelado', 'manual', null) from public.miembros m where m.email = p_email $$;

-- 1. Textos: la v1 se conserva y la v2 trae una finalidad por canal, en cuatro idiomas
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_textos where finalidad = 'checkin' and version = 'v1'), '4', 'la v1 del texto base se conserva para quien se registro antes');
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_textos where version = 'v2' and finalidad in ('checkin', 'checkin_email', 'checkin_whatsapp', 'checkin_sms')), '16', 'la v2 tiene texto base y un texto por canal en los cuatro idiomas');
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_textos where version = 'v2' and finalidad like 'checkin_%' and texto like '%{iglesia}%' and texto_hash = encode(sha256(convert_to(texto, 'UTF8')), 'hex')), '12', 'cada texto de canal nombra a la iglesia y lleva su huella');
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_textos where version = 'v2' and finalidad in ('checkin_email','checkin_whatsapp','checkin_sms') and idioma = 'es' and texto ~* '(correo|whatsapp|sms)'), '3', 'cada casilla nombra su canal');

-- 2. Una persona nueva marca correo y WhatsApp
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Nora', 'Uno', 'nora@canales.test', '+34 611 000 111', 'ip-1', 'v2', 'es', array['email', 'whatsapp']), 'ok_nuevo', 'persona nueva con dos casillas marcadas');
reset role;
select pg_temp.igual(pg_temp.est('nora@canales.test', 'email') || '/' || pg_temp.est('nora@canales.test', 'whatsapp') || '/' || pg_temp.est('nora@canales.test', 'sms'), 'suscrito/suscrito/sin registro', 'quedan suscritos los canales marcados y no el que no se marco');
select pg_temp.igual((select string_agg(origen || ':' || coalesce(usuario_id::text, 'sin_usuario'), ',' order by canal) from public.adn_consentimiento_auditoria where miembro_id = (select id from public.miembros where email = 'nora@canales.test')), 'qr:sin_usuario,qr:sin_usuario', 'cada cambio queda auditado con origen qr y sin usuario');
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_evidencias where miembro_id = (select id from public.miembros where email = 'nora@canales.test')), '3', 'una evidencia del texto base y una por casilla marcada');
select pg_temp.igual((select string_agg(e.finalidad || ':' || e.texto_version || ':' || e.aplicado::text || ':' || (e.texto_hash = t.texto_hash)::text, ',' order by e.finalidad)
  from public.adn_consentimiento_evidencias e join public.adn_consentimiento_textos t on t.finalidad = e.finalidad and t.version = e.texto_version and t.idioma = e.idioma
  where e.miembro_id = (select id from public.miembros where email = 'nora@canales.test') and e.canal is not null), 'checkin_email:v2:true:true,checkin_whatsapp:v2:true:true', 'cada casilla anota su texto, su version y su huella, y que concedio el consentimiento');
select set_config('request.jwt.claim.sub', 'af500000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((public.adn_vista_previa_envio('email', 'todos') ->> 'recibiran'), '1', 'quien marco correo recibiria un mensaje por correo');
select pg_temp.igual((public.adn_vista_previa_envio('whatsapp', 'todos') ->> 'recibiran'), '1', 'y por WhatsApp, que tiene su propio consentimiento');
reset role;

-- 3. Casillas que no se pueden atender o no valen
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Omar', 'Dos', '', '+34 611 000 222', 'ip-2', 'v2', 'es', array['email', 'sms', 'telegram', 'sms']), 'ok_nuevo', 'casillas repetidas, de un canal desconocido o de correo sin correo');
reset role;
select pg_temp.igual((select string_agg(canal, ',' order by canal) from public.adn_consentimientos where miembro_id = (select id from public.miembros where telefono = '+34 611 000 222')), 'sms', 'solo consta sms: el correo exige un correo y un canal desconocido no vale');
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_evidencias where miembro_id = (select id from public.miembros where telefono = '+34 611 000 222') and canal = 'sms'), '1', 'una casilla repetida deja una sola evidencia');
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Pau', 'Tres', 'pau@canales.test', '+34 611 000 333', 'ip-3', 'v2', 'es'), 'ok_nuevo', 'sin casillas el registro funciona igual');
reset role;
select pg_temp.igual((select count(*)::text from public.adn_consentimientos where miembro_id = (select id from public.miembros where email = 'pau@canales.test')), '0', 'y no concede ningun consentimiento');
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_evidencias where miembro_id = (select id from public.miembros where email = 'pau@canales.test') and canal is null), '1', 'pero deja la evidencia del texto base');

-- 4. Sin una version verificable, la casilla se anota pero no concede nada
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Quim', 'Cuatro', 'quim@canales.test', '+34 611 000 444', 'ip-4', 'v9', 'es', array['email']), 'ok_nuevo', 'version desconocida con una casilla marcada');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Rut', 'Cinco', 'rut@canales.test', '+34 611 000 555', 'ip-5', 'v1', 'es', array['email']), 'ok_nuevo', 'una pagina antigua (v1) que envia casillas');
reset role;
select pg_temp.igual((select count(*)::text from public.adn_consentimientos where miembro_id in (select id from public.miembros where email in ('quim@canales.test', 'rut@canales.test'))), '0', 'ninguna de las dos concede consentimiento');
select pg_temp.igual((select string_agg(distinct e.texto_version || ':' || e.aplicado::text, ',') from public.adn_consentimiento_evidencias e where e.canal = 'email' and e.miembro_id in (select id from public.miembros where email in ('quim@canales.test', 'rut@canales.test'))), 'sin_version:false', 'la evidencia dice sin_version y no aplicada');

-- 5. A quien ya existia no se le cambia el consentimiento
select pg_temp.cancelar('nora@canales.test', 'whatsapp');
select max(id) as ultima from public.adn_consentimiento_evidencias \gset
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Nora', 'Uno', 'nora@canales.test', '', 'ip-6', 'v2', 'es', array['whatsapp', 'sms']), 'ok_existente', 'una persona que ya existia marca casillas');
reset role;
select pg_temp.igual(pg_temp.est('nora@canales.test', 'whatsapp') || '/' || pg_temp.est('nora@canales.test', 'sms'), 'cancelado/sin registro', 'su baja no se deshace y no se la suscribe a un canal nuevo');
select pg_temp.igual((select string_agg(e.canal || ':' || e.aplicado::text, ',' order by e.id) from public.adn_consentimiento_evidencias e where e.miembro_id = (select id from public.miembros where email = 'nora@canales.test') and e.canal in ('whatsapp', 'sms') and e.id > :ultima), 'sms:false,whatsapp:false', 'las casillas quedan anotadas como no aplicadas');

-- 6. Permisos
set local role authenticated;
select pg_temp.falla($$select public.registrar_checkin('x', 'a', 'b', '', '', 'i', 'v2', 'es', array['email'])$$, '42501', 'una persona con sesion no llama al registro por QR');
reset role;
rollback;
