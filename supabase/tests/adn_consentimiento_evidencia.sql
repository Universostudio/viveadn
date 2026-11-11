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

insert into auth.users (id) select ('ae500000-0000-0000-0000-00000000000' || n)::uuid from generate_series(1, 4) n;
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ae510000-0000-0000-0000-00000000000a', 'Prueba Evid A', 'prueba-evid-a', 'ES', 'Sevilla', 'premium'),
  ('ae510000-0000-0000-0000-00000000000b', 'Prueba Evid B', 'prueba-evid-b', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('ae500000-0000-0000-0000-000000000001', 'ae510000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@evid.test', 'propietario', true),
  ('ae500000-0000-0000-0000-000000000002', 'ae510000-0000-0000-0000-00000000000a', 'Adm', 'A', 'adm@evid.test', 'administrador', true),
  ('ae500000-0000-0000-0000-000000000003', 'ae510000-0000-0000-0000-00000000000a', 'Col', 'A', 'col@evid.test', 'colaborador', true),
  ('ae500000-0000-0000-0000-000000000004', 'ae510000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@evid.test', 'propietario', true);
insert into public.eventos (id, iglesia_id, titulo, inicia_en, termina_en) values
  ('ae520000-0000-0000-0000-0000000000a1', 'ae510000-0000-0000-0000-00000000000a', 'Culto', now() + interval '1 hour', null);
insert into public.evento_checkin (iglesia_id, evento_id, max_registros) values
  ('ae510000-0000-0000-0000-00000000000a', 'ae520000-0000-0000-0000-0000000000a1', 300);
create or replace function pg_temp.tk() returns text language sql as $$
  select token from public.evento_checkin where evento_id = 'ae520000-0000-0000-0000-0000000000a1' $$;
grant execute on function pg_temp.tk() to service_role;

-- 1. Los textos: cuatro idiomas, con su huella, que nadie edita ni borra
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_textos where finalidad = 'checkin' and version = 'v1'), '4', 'la version v1 del texto del registro por QR existe en los cuatro idiomas');
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_textos where texto_hash = encode(sha256(convert_to(texto, 'UTF8')), 'hex')), '4', 'cada texto lleva la huella SHA-256 de su contenido');
select pg_temp.falla($$insert into public.adn_consentimiento_textos (finalidad, version, idioma, texto, texto_hash) values ('checkin', 'v9', 'es', 'x', repeat('a', 64))$$, '23514', 'una huella que no es la del texto se rechaza');
select pg_temp.falla($$update public.adn_consentimiento_textos set texto = 'otro'$$, 'ADN_REGISTRO_INMUTABLE', 'ni el servicio edita un texto: se crea otra version');
select pg_temp.falla($$delete from public.adn_consentimiento_textos$$, 'ADN_REGISTRO_INMUTABLE', 'ni el servicio borra un texto');
set local role anon;
select pg_temp.falla($$select * from public.adn_consentimiento_textos$$, '42501', 'un visitante sin sesion no lee la tabla de textos');
reset role;
select set_config('request.jwt.claim.sub', 'ae500000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_textos), '4', 'una persona con sesion lee los textos');
select pg_temp.falla($$insert into public.adn_consentimiento_textos (finalidad, version, idioma, texto, texto_hash) values ('checkin', 'v2', 'es', 'x', encode(sha256(convert_to('x', 'UTF8')), 'hex'))$$, '42501', 'nadie con sesion crea textos');
reset role;

-- 2. Registro por QR: cada registro deja su evidencia
set local role service_role;
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Nora', 'Uno', 'nora@evid.test', '+34 611 000 111', 'ip-1', 'v1', 'es'), 'ok_nuevo', 'una persona nueva se registra con la version del texto');
select pg_temp.igual(pg_temp.ev('nora@evid.test'), '1', 'el registro deja una fila de evidencia');
select pg_temp.igual((select e.tipo || '/' || e.texto_version || '/' || e.idioma || '/' || e.origen || '/' || (e.texto_hash = t.texto_hash)::text || '/' || (e.evento_id = 'ae520000-0000-0000-0000-0000000000a1')::text
  from public.adn_consentimiento_evidencias e join public.adn_consentimiento_textos t on t.finalidad = 'checkin' and t.version = e.texto_version and t.idioma = e.idioma
  where e.miembro_id = (select id from public.miembros where email = 'nora@evid.test')), 'checkin/v1/es/qr/true/true', 'anota tipo, version, idioma, origen, la huella del texto y el evento');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Nora', 'Uno', 'nora@evid.test', '', 'ip-2', 'v1', 'en'), 'ok_existente', 'la misma persona vuelve a registrarse');
select pg_temp.igual(pg_temp.ev('nora@evid.test'), '2', 'cada registro deja su propia evidencia, tambien el de una persona que ya existia');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Omar', 'Dos', 'omar@evid.test', '+34 611 000 222', 'ip-3'), 'ok_nuevo', 'la llamada anterior, con seis parametros, sigue funcionando');
select pg_temp.igual((select e.texto_version || '/' || coalesce(e.idioma, 'nulo') || '/' || coalesce(e.texto_hash, 'nulo') from public.adn_consentimiento_evidencias e where e.miembro_id = (select id from public.miembros where email = 'omar@evid.test')), 'sin_version/nulo/nulo', 'sin version consta como sin_version y no se inventa una huella');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Pau', 'Tres', 'pau@evid.test', '+34 611 000 333', 'ip-4', 'v9', 'es'), 'ok_nuevo', 'una version desconocida no impide el registro');
select pg_temp.igual((select e.texto_version from public.adn_consentimiento_evidencias e where e.miembro_id = (select id from public.miembros where email = 'pau@evid.test')), 'sin_version', 'una version que no consta en la tabla de textos se anota como sin_version');
select pg_temp.igual(public.registrar_checkin(pg_temp.tk(), 'Quim', 'Cuatro', 'quim@evid.test', '+34 611 000 444', 'ip-5', 'v1', 'de'), 'ok_nuevo', 'un idioma sin texto registrado tampoco impide el registro');
select pg_temp.igual((select e.texto_version from public.adn_consentimiento_evidencias e where e.miembro_id = (select id from public.miembros where email = 'quim@evid.test')), 'sin_version', 'y la version se anota como sin_version');
reset role;
-- El registro por QR no concede consentimiento de comunicacion
select pg_temp.igual((select count(*)::text from public.adn_consentimientos c join public.miembros m on m.id = c.miembro_id where m.email like '%@evid.test'), '0', 'el registro por QR no crea ningun consentimiento de comunicacion');
select set_config('request.jwt.claim.sub', 'ae500000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((public.adn_vista_previa_envio('email', 'todos') ->> 'sin_consentimiento'), '4', 'quienes se registraron por QR siguen sin recibir mensajes hasta que conste su consentimiento');
reset role;

-- 3. Importacion: el valor original del archivo queda como evidencia
select set_config('request.jwt.claim.sub', 'ae500000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.adn_importar_miembros($j$[
  {"nombre": "Uno", "apellido": "W", "email": "uno@w.evid.test", "consentimiento": {"email": "suscrito"},
   "consentimiento_original": {"email": "Subscribed", "sms": "Pending raro"}},
  {"nombre": "Dos", "apellido": "W", "email": "dos@w.evid.test", "consentimiento_original": {"email": "Valor\nraro\t con   saltos"}},
  {"nombre": "Tres", "apellido": "W", "email": "tres@w.evid.test", "consentimiento": {"email": "suscrito"}},
  {"nombre": "Cuatro", "apellido": "W", "email": "cuatro@w.evid.test", "consentimiento": {"email": "suscrito"},
   "consentimiento_original": {"email": "Suscrito de verdad ... y un texto larguisimo que no cabe en sesenta caracteres de ninguna manera"}}
]$j$::jsonb, 'wix');
reset role;
select pg_temp.igual((select e.texto_original || '/' || e.estado_importado || '/' || e.aplicado::text || '/' || e.origen from public.adn_consentimiento_evidencias e
  where e.tipo = 'importacion' and e.canal = 'email' and e.miembro_id = (select id from public.miembros where email = 'uno@w.evid.test')), 'Subscribed/suscrito/true/wix', 'guarda el valor original, el estado resultante, si se aplico y de que importacion viene');
select pg_temp.igual((select e.texto_original || '/' || coalesce(e.estado_importado, 'nulo') || '/' || e.aplicado::text from public.adn_consentimiento_evidencias e
  where e.tipo = 'importacion' and e.canal = 'sms' and e.miembro_id = (select id from public.miembros where email = 'uno@w.evid.test')), 'Pending raro/nulo/false', 'un valor que no se entiende se conserva como texto y no cambia el consentimiento');
select pg_temp.igual((select count(*)::text from public.adn_consentimientos c join public.miembros m on m.id = c.miembro_id where m.email = 'uno@w.evid.test' and c.canal = 'sms'), '0', 'y no crea consentimiento de sms');
select pg_temp.igual((select e.texto_original from public.adn_consentimiento_evidencias e where e.canal = 'email' and e.miembro_id = (select id from public.miembros where email = 'dos@w.evid.test')), 'Valor raro con saltos', 'saltos y caracteres de control se limpian');
select pg_temp.igual(pg_temp.ev('tres@w.evid.test'), '0', 'una fila sin valor original no deja evidencia');
select pg_temp.igual((select char_length(e.texto_original)::text from public.adn_consentimiento_evidencias e where e.canal = 'email' and e.miembro_id = (select id from public.miembros where email = 'cuatro@w.evid.test')), '60', 'el valor original se recorta a 60 caracteres');
select pg_temp.igual((select (count(*) = 0)::text from public.adn_consentimiento_evidencias e where e.tipo = 'importacion' and e.estado_importado = 'suscrito' and e.canal = 'email' and not exists (select 1 from public.adn_consentimientos c where c.miembro_id = e.miembro_id and c.canal = 'email')), 'true', 'cada estado importado como suscrito tiene su consentimiento registrado');
-- Reimportar sobre una persona existente: la evidencia dice que pasó, el consentimiento solo endurece
select set_config('request.jwt.claim.sub', 'ae500000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.adn_importar_miembros($j$[
  {"nombre": "Uno", "apellido": "W", "email": "uno@w.evid.test", "consentimiento": {"email": "cancelado"}, "consentimiento_original": {"email": "Unsubscribed"}}
]$j$::jsonb, 'wix');
select public.adn_importar_miembros($j$[
  {"nombre": "Uno", "apellido": "W", "email": "uno@w.evid.test", "consentimiento": {"email": "suscrito"}, "consentimiento_original": {"email": "Subscribed"}}
]$j$::jsonb, 'wix');
reset role;
select pg_temp.igual((select string_agg(e.texto_original || ':' || e.aplicado::text, ',' order by e.id) from public.adn_consentimiento_evidencias e
  where e.tipo = 'importacion' and e.canal = 'email' and e.miembro_id = (select id from public.miembros where email = 'uno@w.evid.test')), 'Subscribed:true,Unsubscribed:true,Subscribed:false', 'la baja del archivo se aplica y el archivo que dice suscrito despues queda como evidencia no aplicada');
select pg_temp.igual((select estado from public.adn_consentimientos where canal = 'email' and miembro_id = (select id from public.miembros where email = 'uno@w.evid.test')), 'cancelado', 'y el consentimiento sigue cancelado: la evidencia no lo resucita');

-- 4. Permisos y aislamiento
select set_config('request.jwt.claim.sub', 'ae500000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select (count(*) > 0)::text from public.adn_consentimiento_evidencias), 'true', 'quien tiene permiso de comunicacion lee las evidencias de su iglesia');
select pg_temp.falla($$insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, finalidad, texto_version, origen) select iglesia_id, id, 'checkin', 'checkin', 'v1', 'qr' from public.miembros limit 1$$, '42501', 'nadie inserta evidencias a mano');
select pg_temp.falla($$update public.adn_consentimiento_evidencias set texto_version = 'v1'$$, '42501', 'nadie modifica evidencias');
select pg_temp.falla($$delete from public.adn_consentimiento_evidencias$$, '42501', 'nadie borra evidencias');
reset role;
select set_config('request.jwt.claim.sub', 'ae500000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_evidencias), '0', 'el colaborador, sin permiso de comunicacion, no lee evidencias');
reset role;
select set_config('request.jwt.claim.sub', 'ae500000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_evidencias), '0', 'otra iglesia no ve ninguna evidencia ajena');
reset role;
set local role anon;
select pg_temp.falla($$select * from public.adn_consentimiento_evidencias$$, '42501', 'un visitante sin sesion no lee evidencias');
reset role;
select pg_temp.falla($$update public.adn_consentimiento_evidencias set texto_version = 'v1'$$, 'ADN_REGISTRO_INMUTABLE', 'ni el servicio modifica una evidencia');
-- Las funciones nuevas no se pueden llamar sin ser servidor
set local role authenticated;
select pg_temp.falla($$select public.registrar_checkin('x', 'a', 'b', '', '', 'i', 'v1', 'es')$$, '42501', 'una persona con sesion no llama al registro por QR');
reset role;
-- Borrar al miembro borra su evidencia
delete from public.miembros where email = 'uno@w.evid.test';
select pg_temp.igual((select count(*)::text from public.adn_consentimiento_evidencias e where not exists (select 1 from public.miembros m where m.id = e.miembro_id)), '0', 'borrar a un miembro borra sus evidencias');
rollback;
