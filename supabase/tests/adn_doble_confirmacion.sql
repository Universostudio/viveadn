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

insert into auth.users (id) select ('a9500000-0000-0000-0000-00000000000' || n)::uuid from generate_series(1, 4) n;
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('a9510000-0000-0000-0000-00000000000a', 'Prueba Doble A', 'prueba-doble-a', 'ES', 'Sevilla', 'premium'),
  ('a9510000-0000-0000-0000-00000000000b', 'Prueba Doble B', 'prueba-doble-b', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('a9500000-0000-0000-0000-000000000001', 'a9510000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@doble.test', 'propietario', true),
  ('a9500000-0000-0000-0000-000000000002', 'a9510000-0000-0000-0000-00000000000a', 'Adm', 'A', 'adm@doble.test', 'administrador', true),
  ('a9500000-0000-0000-0000-000000000003', 'a9510000-0000-0000-0000-00000000000a', 'Col', 'A', 'col@doble.test', 'colaborador', true),
  ('a9500000-0000-0000-0000-000000000004', 'a9510000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@doble.test', 'propietario', true);
insert into public.eventos (id, iglesia_id, titulo, inicia_en, termina_en) values
  ('a9520000-0000-0000-0000-0000000000a1', 'a9510000-0000-0000-0000-00000000000a', 'Culto', now() + interval '1 hour', null);
insert into public.evento_checkin (iglesia_id, evento_id, max_registros) values
  ('a9510000-0000-0000-0000-00000000000a', 'a9520000-0000-0000-0000-0000000000a1', 300);
create or replace function pg_temp.tk() returns text language sql as $$
  select token from public.evento_checkin where evento_id = 'a9520000-0000-0000-0000-0000000000a1' $$;
grant execute on function pg_temp.tk() to service_role;


create or replace function pg_temp.est(p_email text, p_canal text) returns text language sql as $$
  select coalesce((select estado from public.adn_consentimientos where miembro_id = (select id from public.miembros where email = p_email limit 1) and canal = p_canal), 'sin registro') $$;
grant execute on function pg_temp.est(text, text) to authenticated, service_role;
create or replace function pg_temp.cancelar(p_email text, p_canal text) returns void language sql as $$
  select private.adn_escribir_consentimiento(m.iglesia_id, m.id, p_canal, 'cancelado', 'manual', null) from public.miembros m where m.email = p_email $$;


create or replace function pg_temp.est(p_email text, p_canal text) returns text language sql as $$
  select coalesce((select estado from public.adn_consentimientos where miembro_id = (select id from public.miembros where email = p_email limit 1) and canal = p_canal), 'sin registro') $$;
create or replace function pg_temp.cancelar(p_email text, p_canal text) returns void language sql as $$
  select private.adn_escribir_consentimiento(m.iglesia_id, m.id, p_canal, 'cancelado', 'manual', null) from public.miembros m where m.email = p_email $$;
grant execute on function pg_temp.est(text, text) to authenticated, service_role;

create or replace function pg_temp.activar(p boolean) returns void language sql as $$
  update public.plataforma_ajustes set valor = to_jsonb(p) where clave = 'adn_doble_confirmacion' $$;
create or replace function pg_temp.conf(p_email text, p_donde text default 'true') returns text language plpgsql as $$
declare n text;
begin
  execute format('select count(*)::text from public.adn_confirmaciones c where c.miembro_id = (select id from public.miembros where email = %L limit 1) and %s', p_email, p_donde) into n;
  return n;
end $$;
grant execute on function pg_temp.activar(boolean), pg_temp.conf(text, text) to service_role;
-- El token de una solicitud preparada, para confirmarla
create temp table tokens (email text primary key, token text, baja text);
grant all on tokens to service_role;

-- 1. Apagada por defecto: el registro por QR se comporta como antes
select pg_temp.igual((select valor::text from public.plataforma_ajustes where clave = 'adn_doble_confirmacion'), 'false', 'el ajuste existe y esta apagado');
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Ana', 'Apagada', 'ana@doble.test', '+34 611 000 111', 'ip-1', 'v2', 'es', array['email']), 'ok_nuevo', 'persona nueva con la casilla de correo, con la doble confirmacion apagada');
reset role;
select pg_temp.igual(pg_temp.est('ana@doble.test', 'email'), 'suscrito', 'queda suscrita como hasta ahora');
select pg_temp.igual(pg_temp.conf('ana@doble.test'), '0', 'y no se crea ninguna solicitud');
set local role service_role;
select pg_temp.igual((select count(*)::text from public.adn_confirmacion_preparar(10)), '0', 'preparar con el ajuste apagado no devuelve nada');
reset role;

-- 2. Encendida: la casilla no concede nada y se crea una solicitud
select pg_temp.activar(true);
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Berta', 'Nueva', 'berta@doble.test', '+34 611 000 222', 'ip-2', 'v2', 'fr', array['email', 'whatsapp', 'sms']), 'ok_nuevo', 'persona nueva con tres casillas, con la doble confirmacion encendida');
reset role;
select pg_temp.igual((select count(*)::text from public.adn_consentimientos where miembro_id = (select id from public.miembros where email = 'berta@doble.test')), '0', 'ninguna casilla concede consentimiento todavia');
select pg_temp.igual(pg_temp.conf('berta@doble.test', $$c.estado = 'por_enviar' and c.canal = 'email' and c.destino = 'berta@doble.test' and c.idioma = 'fr' and c.token_hash is null$$), '1', 'se crea una solicitud de correo por enviar, con su idioma y sin secreto');
select pg_temp.igual((select string_agg(canal || ':' || aplicado::text, ',' order by canal) from public.adn_consentimiento_evidencias where miembro_id = (select id from public.miembros where email = 'berta@doble.test') and canal is not null), 'email:false,sms:false,whatsapp:false', 'las tres casillas quedan anotadas como no aplicadas');
select set_config('request.jwt.claim.sub', 'a9500000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((public.adn_vista_previa_envio('email', 'todos') ->> 'recibiran'), '1', 'solo recibe la persona suscrita antes de encender el ajuste (Ana); Berta no');
reset role;
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Berta', 'Nueva', 'berta@doble.test', '', 'ip-3', 'v2', 'fr', array['email']), 'ok_existente', 'la persona vuelve a registrarse');
reset role;
select pg_temp.igual(pg_temp.conf('berta@doble.test'), '1', 'quien ya existia no crea otra solicitud');
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Carla', 'Sin', '', '+34 611 000 333', 'ip-4', 'v2', 'es', array['whatsapp']), 'ok_nuevo', 'persona nueva solo con WhatsApp');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Dani', 'Sin', 'dani@doble.test', '+34 611 000 444', 'ip-5', 'v9', 'es', array['email']), 'ok_nuevo', 'persona nueva con una version de texto desconocida');
reset role;
select pg_temp.igual((select count(*)::text from public.adn_confirmaciones where miembro_id in (select id from public.miembros where nombre in ('Carla', 'Dani'))), '0', 'sin canal de correo o sin version verificable no hay solicitud');

-- 3. Preparar el envio: secreto de un solo uso, solo su huella en la base
set local role service_role;
insert into tokens select destino, token, baja_token from public.adn_confirmacion_preparar(10);
reset role;
select pg_temp.igual((select count(*)::text from tokens), '1', 'se prepara una solicitud');
select pg_temp.igual((select (token ~ '^[0-9a-f]{64}$' and baja ~ '^[0-9a-f]{64}$' and token <> baja)::text from tokens where email = 'berta@doble.test'), 'true', 'cada solicitud lleva un secreto de confirmacion y otro de baja, de 64 caracteres y distintos');
select pg_temp.igual((select (c.estado = 'pendiente' and c.token_hash = encode(sha256(convert_to(t.token, 'UTF8')), 'hex') and c.token_hash <> t.token and c.expira_en > now() + interval '2 days' and c.expira_en < now() + interval '4 days')::text
  from public.adn_confirmaciones c join tokens t on t.email = c.destino), 'true', 'queda pendiente, con la huella del secreto (no el secreto) y caducidad de tres dias');
select pg_temp.igual((select count(*)::text from public.adn_confirmaciones where token_hash = (select token from tokens)), '0', 'la base no guarda el secreto');
select pg_temp.igual((select count(*)::text from public.adn_bajas_enlaces b join tokens t on b.token_hash = encode(sha256(convert_to(t.baja, 'UTF8')), 'hex') where b.canal = 'email' and b.miembro_id = (select id from public.miembros where email = 'berta@doble.test') and b.usado_en is null), '1', 'y se crea su enlace de baja de un solo uso para la cabecera List-Unsubscribe');
set local role service_role;
select pg_temp.igual((select count(*)::text from public.adn_confirmacion_preparar(10)), '0', 'preparar otra vez no repite una solicitud ya preparada');
select pg_temp.falla($$select * from public.adn_confirmacion_preparar(0)$$, 'ADN_DATOS_INVALIDOS', 'un lote de tamano cero se rechaza');
select pg_temp.falla($$select * from public.adn_confirmacion_preparar(10, 99)$$, 'ADN_DATOS_INVALIDOS', 'una caducidad de 99 dias se rechaza');
reset role;

-- 4. Si el envio falla, la solicitud vuelve a por enviar sin secreto y se puede reintentar
set local role service_role;
select public.adn_confirmacion_fallida((select id from public.adn_confirmaciones where destino = 'berta@doble.test'));
reset role;
select pg_temp.igual(pg_temp.conf('berta@doble.test', $$c.estado = 'por_enviar' and c.token_hash is null and c.expira_en is null$$), '1', 'un envio fallido devuelve la solicitud a por_enviar sin secreto');
set local role service_role;
select pg_temp.igual(public.adn_confirmacion_consumir((select token from tokens)) ->> 'motivo', 'invalido', 'el secreto del intento fallido ya no vale');
truncate tokens;
insert into tokens select destino, token, baja_token from public.adn_confirmacion_preparar(10);
reset role;
select pg_temp.igual((select count(*)::text from tokens), '1', 'se vuelve a preparar con un secreto nuevo');

-- 5. Confirmar
set local role service_role;
select pg_temp.igual(public.adn_confirmacion_consumir('no-es-un-secreto') ->> 'motivo', 'invalido', 'un secreto con mala forma es invalido');
select pg_temp.igual(public.adn_confirmacion_consumir(repeat('a', 64)) ->> 'motivo', 'invalido', 'un secreto que no existe es invalido');
select pg_temp.igual(public.adn_confirmacion_consumir(null) ->> 'motivo', 'invalido', 'un secreto nulo es invalido');
reset role;
select pg_temp.igual(pg_temp.est('berta@doble.test', 'email'), 'sin registro', 'antes de confirmar no consta consentimiento');
set local role service_role;
select pg_temp.igual((select public.adn_confirmacion_consumir(token)::text from tokens), '{"ok": true, "canal": "email"}', 'confirmar devuelve solo ok y el canal');
reset role;
select pg_temp.igual(pg_temp.est('berta@doble.test', 'email'), 'suscrito', 'al confirmar queda suscrita al correo');
select pg_temp.igual((select origen from public.adn_consentimientos where miembro_id = (select id from public.miembros where email = 'berta@doble.test') and canal = 'email'), 'qr_confirmado', 'con origen qr_confirmado');
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_auditoria where miembro_id = (select id from public.miembros where email = 'berta@doble.test') and origen = 'qr_confirmado' and usuario_id is null), '1', 'queda en la auditoria, sin usuario');
select pg_temp.igual((select tipo || ':' || canal || ':' || aplicado::text || ':' || origen from public.adn_consentimiento_evidencias where miembro_id = (select id from public.miembros where email = 'berta@doble.test') and tipo = 'confirmacion'), 'confirmacion:email:true:qr_confirmado', 'y como evidencia de tipo confirmacion');
select pg_temp.igual((select count(*)::text from public.adn_consentimientos where miembro_id = (select id from public.miembros where email = 'berta@doble.test') and canal in ('whatsapp', 'sms')), '0', 'WhatsApp y SMS siguen sin concederse: no tienen mecanismo de confirmacion');
set local role service_role;
select pg_temp.igual((select public.adn_confirmacion_consumir(token) ->> 'motivo' from tokens), 'usado', 'un segundo uso se rechaza');
reset role;
select set_config('request.jwt.claim.sub', 'a9500000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((public.adn_vista_previa_envio('email', 'todos') ->> 'recibiran'), '2', 'ahora Berta tambien recibiria un mensaje');
reset role;

-- 6. Caducidad y proteccion de bajas
select pg_temp.igual((select count(*)::text from (select public.registrar_checkin(pg_temp.tk(), 'Eva', 'Caduca', 'eva@doble.test', '+34 611 000 555', 'ip-6', 'v2', 'en', array['email'])) x), '1', 'otra persona nueva pide confirmacion') ;
set local role service_role;
truncate tokens;
insert into tokens select destino, token, baja_token from public.adn_confirmacion_preparar(10);
reset role;
update public.adn_confirmaciones set expira_en = now() - interval '1 minute' where destino = 'eva@doble.test';
set local role service_role;
select pg_temp.igual((select public.adn_confirmacion_consumir(token) ->> 'motivo' from tokens), 'caducado', 'un enlace caducado se rechaza');
reset role;
select pg_temp.igual((select estado from public.adn_confirmaciones where destino = 'eva@doble.test'), 'caducada', 'y la solicitud queda caducada');
select pg_temp.igual(pg_temp.est('eva@doble.test', 'email'), 'sin registro', 'sin conceder nada');
-- Una baja entre la solicitud y la confirmacion no se deshace
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Fran', 'Baja', 'fran@doble.test', '+34 611 000 666', 'ip-7', 'v2', 'es', array['email']), 'ok_nuevo', 'otra persona nueva pide confirmacion');
truncate tokens;
insert into tokens select destino, token, baja_token from public.adn_confirmacion_preparar(10);
reset role;
select pg_temp.cancelar('fran@doble.test', 'email');
set local role service_role;
select pg_temp.igual((select public.adn_confirmacion_consumir(token)::text from tokens), '{"ok": true, "canal": "email"}', 'confirmar tras una baja responde igual, sin revelar nada');
reset role;
select pg_temp.igual(pg_temp.est('fran@doble.test', 'email'), 'cancelado', 'pero la baja no se deshace');
select pg_temp.igual((select aplicado::text from public.adn_consentimiento_evidencias where miembro_id = (select id from public.miembros where email = 'fran@doble.test') and tipo = 'confirmacion'), 'false', 'y la evidencia dice que no se aplico');

-- 7. Permisos: solo el servidor
set local role authenticated;
select pg_temp.falla($$select count(*) from public.adn_confirmaciones$$, '42501', 'ninguna persona con sesion lee las solicitudes');
select pg_temp.falla($$select * from public.adn_confirmacion_preparar(1)$$, '42501', 'ni prepara envios');
select pg_temp.falla($$select public.adn_confirmacion_consumir(repeat('a', 64))$$, '42501', 'ni confirma');
reset role;
set local role anon;
select pg_temp.falla($$select count(*) from public.adn_confirmaciones$$, '42501', 'un visitante sin sesion tampoco lee solicitudes');
select pg_temp.falla($$select public.adn_confirmacion_consumir(repeat('a', 64))$$, '42501', 'ni confirma desde la base');
reset role;
select pg_temp.activar(false);
select pg_temp.igual((select valor::text from public.plataforma_ajustes where clave = 'adn_doble_confirmacion'), 'false', 'se puede volver a apagar');
rollback;
