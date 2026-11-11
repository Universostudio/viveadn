-- Consentimiento de comunicacion por persona y canal: Comunicacion solo envia a quien consta como suscrito, una
-- suscripcion cancelada protege tambien a la direccion compartida, y reimportar nunca relaja un consentimiento.
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
create or replace function pg_temp.estado(p_miembro text, p_canal text) returns text language sql as $$
  select coalesce((select estado from public.adn_consentimientos where miembro_id = (select id from public.miembros where email = p_miembro or nombre = p_miembro limit 1) and canal = p_canal), 'sin registro') $$;
grant execute on function pg_temp.estado(text, text) to authenticated;

insert into auth.users (id) select ('ac000000-0000-0000-0000-00000000000' || n)::uuid from generate_series(1, 4) n;
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ac100000-0000-0000-0000-00000000000a', 'Prueba Cons A', 'prueba-cons-a', 'ES', 'Sevilla', 'premium'),
  ('ac100000-0000-0000-0000-00000000000b', 'Prueba Cons B', 'prueba-cons-b', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('ac000000-0000-0000-0000-000000000001', 'ac100000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@prueba.test', 'propietario', true),
  ('ac000000-0000-0000-0000-000000000002', 'ac100000-0000-0000-0000-00000000000a', 'Adm', 'A', 'adm@prueba.test', 'administrador', true),
  ('ac000000-0000-0000-0000-000000000003', 'ac100000-0000-0000-0000-00000000000a', 'Col', 'A', 'col@prueba.test', 'colaborador', true),
  ('ac000000-0000-0000-0000-000000000004', 'ac100000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@prueba.test', 'propietario', true);
insert into public.miembros (id, iglesia_id, nombre, apellido, email, telefono, activo) values
  ('ac400000-0000-0000-0000-000000000001', 'ac100000-0000-0000-0000-00000000000a', 'Ana', 'Pérez', 'ana@x.test', '+34 600 111 222', true),
  ('ac400000-0000-0000-0000-000000000002', 'ac100000-0000-0000-0000-00000000000a', 'Luis', 'Gil', 'luis@x.test', '600333444', true),
  ('ac400000-0000-0000-0000-000000000003', 'ac100000-0000-0000-0000-00000000000a', 'Pía', 'Mar', 'ana@x.test', null, true),
  ('ac400000-0000-0000-0000-000000000004', 'ac100000-0000-0000-0000-00000000000a', 'Eva', 'Sol', 'eva@x.test', null, true),
  ('ac400000-0000-0000-0000-0000000000b1', 'ac100000-0000-0000-0000-00000000000b', 'Bea', 'B', 'bea@x.test', null, true);

-- 1. Sin registro de consentimiento no se envia a nadie
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((public.adn_vista_previa_envio('email', 'todos') = '{"baja": 0, "total": 4, "recibiran": 0, "repetido": 0, "sin_destino": 0, "sin_consentimiento": 4}'::jsonb)::text, 'true',
  'sin ningun registro de consentimiento nadie recibe: los 4 se omiten por falta de consentimiento');
reset role;
-- 2. Registro manual por quien edita miembros (administrador de A)
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000001', 'email', 'suscrito');
select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000002', 'email', 'nunca');
select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000004', 'email', 'sin_dato');
select pg_temp.igual((public.adn_vista_previa_envio('email', 'todos') = '{"baja": 0, "total": 4, "recibiran": 1, "repetido": 0, "sin_destino": 0, "sin_consentimiento": 3}'::jsonb)::text, 'true',
  'solo recibe Ana, suscrita: Luis (nunca), Pia (sin registro) y Eva (sin dato) quedan fuera');
-- Una suscripcion cancelada protege tambien a quien comparte la direccion
select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000003', 'email', 'suscrito');
select pg_temp.igual((public.adn_vista_previa_envio('email', 'todos') ->> 'recibiran'), '1', 'Pia suscrita comparte direccion con Ana: una sola recibe (la otra es repetida)');
select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000001', 'email', 'cancelado');
select pg_temp.igual((public.adn_vista_previa_envio('email', 'todos') = '{"baja": 2, "total": 4, "recibiran": 0, "repetido": 0, "sin_destino": 0, "sin_consentimiento": 2}'::jsonb)::text, 'true',
  'Ana cancela: ni ella ni Pia, que comparte su direccion, reciben nada');
-- Un registro manual puede volver a suscribir: es una decision humana
select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000001', 'email', 'suscrito');
select pg_temp.igual(pg_temp.estado('ana@x.test', 'email'), 'suscrito', 'quien edita miembros puede volver a dejar a alguien suscrito');
-- Cada canal tiene el suyo: el de correo y el de SMS no valen para WhatsApp
select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000002', 'sms', 'suscrito');
select pg_temp.igual((public.adn_vista_previa_envio('whatsapp', 'todos') ->> 'recibiran'), '0', 'el consentimiento de correo y de SMS no habilita WhatsApp');
select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000002', 'whatsapp', 'suscrito');
select pg_temp.igual((public.adn_vista_previa_envio('whatsapp', 'todos') ->> 'recibiran'), '1', 'con su propio consentimiento de WhatsApp, Luis recibe');
-- Validaciones
select pg_temp.falla($$select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000001', 'fax', 'suscrito')$$, 'ADN_DATOS_INVALIDOS', 'un canal desconocido se rechaza');
select pg_temp.falla($$select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000001', 'email', 'quizas')$$, 'ADN_DATOS_INVALIDOS', 'un estado desconocido se rechaza');
select pg_temp.falla($$select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-0000000000b1', 'email', 'suscrito')$$, 'ADN_DATOS_INVALIDOS', 'no se registra el consentimiento de un miembro de otra iglesia');
-- Nadie escribe la tabla a mano
select pg_temp.falla($$insert into public.adn_consentimientos (miembro_id, canal, estado, origen) values ('ac400000-0000-0000-0000-000000000004', 'email', 'suscrito', 'x')$$, '42501', 'nadie inserta consentimientos a mano');
select pg_temp.falla($$update public.adn_consentimientos set estado = 'suscrito'$$, '42501', 'nadie modifica consentimientos a mano');
select pg_temp.falla($$delete from public.adn_consentimientos$$, '42501', 'nadie borra consentimientos a mano');
reset role;
-- El colaborador no edita miembros
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.falla($$select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000004', 'email', 'suscrito')$$, 'ADN_SIN_PERMISO', 'quien no edita miembros no registra consentimientos');
reset role;
-- La otra iglesia no ve ni toca los de A
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_consentimientos), '0', 'B no ve ningun consentimiento de A');
select pg_temp.falla($$select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000004', 'email', 'suscrito')$$, 'ADN_DATOS_INVALIDOS', 'B no registra el consentimiento de un miembro de A');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- 3. Importacion: el archivo trae el estado de suscripcion por canal y la reimportacion solo puede endurecerlo
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.adn_importar_miembros($j$[
  {"nombre": "Uno", "apellido": "W", "email": "uno@w.test", "consentimiento": {"email": "suscrito", "sms": "nunca"},
   "contactos": [{"tipo": "etiqueta", "etiqueta": "fuente", "valor": "Wix Forms"}, {"tipo": "etiqueta", "etiqueta": "creado", "valor": "2024-05-01"}]},
  {"nombre": "Dos", "apellido": "W", "email": "dos@w.test", "consentimiento": {"email": "cancelado", "sms": "cancelado"}},
  {"nombre": "Tres", "apellido": "W", "email": "tres@w.test", "consentimiento": {"email": "sin_dato"}},
  {"nombre": "Cuatro", "apellido": "W", "email": "cuatro@w.test", "consentimiento": {"email": "peligro", "sms": 5}},
  {"nombre": "Cinco", "apellido": "W", "email": "cinco@w.test"}
]$j$::jsonb, 'wix');
reset role;
select pg_temp.igual(pg_temp.estado('uno@w.test', 'email') || '/' || pg_temp.estado('uno@w.test', 'sms'), 'suscrito/nunca', 'una persona nueva guarda el estado de cada canal tal como viene');
select pg_temp.igual(pg_temp.estado('dos@w.test', 'email') || '/' || pg_temp.estado('dos@w.test', 'sms'), 'cancelado/cancelado', 'una suscripcion cancelada se guarda');
select pg_temp.igual(pg_temp.estado('tres@w.test', 'email'), 'sin registro', 'un estado vacio no crea consentimiento');
select pg_temp.igual(pg_temp.estado('cuatro@w.test', 'email') || '/' || pg_temp.estado('cuatro@w.test', 'sms'), 'sin registro/sin registro', 'un estado desconocido no crea consentimiento');
select pg_temp.igual(pg_temp.estado('cinco@w.test', 'email'), 'sin registro', 'una fila sin consentimiento no lo crea');
select pg_temp.igual((select origen from public.adn_consentimientos where miembro_id = (select id from public.miembros where email = 'uno@w.test') and canal = 'email'), 'wix', 'queda anotado de que importacion viene');
select pg_temp.igual((select count(*)::text from public.adn_miembro_contactos where miembro_id = (select id from public.miembros where email = 'uno@w.test') and etiqueta in ('fuente', 'creado')), '2', 'la fuente y la fecha de alta se guardan como datos del contacto');

-- Reimportar: solo endurece
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table reimp as select public.adn_importar_miembros($j$[
  {"nombre": "Uno", "apellido": "W", "email": "uno@w.test", "consentimiento": {"email": "cancelado"}},
  {"nombre": "Dos", "apellido": "W", "email": "dos@w.test", "consentimiento": {"email": "suscrito", "sms": "suscrito"}},
  {"nombre": "Tres", "apellido": "W", "email": "tres@w.test", "consentimiento": {"email": "suscrito"}},
  {"nombre": "Cuatro", "apellido": "W", "email": "cuatro@w.test", "consentimiento": {"email": "nunca"}},
  {"nombre": "Ana", "apellido": "Pérez", "email": "ana@x.test", "consentimiento": {"email": "cancelado"}}
]$j$::jsonb, 'wix') r;
reset role;
select pg_temp.igual((select (r ->> 'importados') || '/' || (r ->> 'duplicados_correo') from reimp), '0/5', 'reimportar el mismo archivo no crea a nadie');
select pg_temp.igual(pg_temp.estado('uno@w.test', 'email'), 'cancelado', 'reimportar con una baja pasa a quien estaba suscrito a cancelado');
select pg_temp.igual(pg_temp.estado('dos@w.test', 'email') || '/' || pg_temp.estado('dos@w.test', 'sms'), 'cancelado/cancelado', 'reimportar con "suscrito" no resucita una baja');
select pg_temp.igual(pg_temp.estado('tres@w.test', 'email'), 'sin registro', 'reimportar con "suscrito" no crea consentimiento a quien no lo tenia');
select pg_temp.igual(pg_temp.estado('cuatro@w.test', 'email'), 'nunca', 'reimportar con "nunca" si queda anotado');
select pg_temp.igual(pg_temp.estado('ana@x.test', 'email'), 'cancelado', 'la baja del archivo alcanza tambien a un miembro creado a mano');
-- Un registro manual de "sin_dato" tampoco sube a suscrito por reimportar
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select public.adn_registrar_consentimiento((select id from public.miembros where email = 'eva@x.test'), 'email', 'sin_dato');
reset role;
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.adn_importar_miembros('[{"nombre": "Eva", "apellido": "Sol", "email": "eva@x.test", "consentimiento": {"email": "suscrito"}}]'::jsonb, 'wix');
reset role;
select pg_temp.igual(pg_temp.estado('eva@x.test', 'email'), 'sin_dato', 'reimportar no sube de "sin dato" a "suscrito"');

-- La otra iglesia importa un correo que ya existe en A: no toca nada de A
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select public.adn_importar_miembros('[{"nombre": "Ana", "apellido": "Otra", "email": "ana@x.test", "consentimiento": {"email": "suscrito"}}]'::jsonb, 'wix');
reset role;
select pg_temp.igual((select count(*)::text from public.adn_consentimientos c join public.miembros m on m.id = c.miembro_id where m.iglesia_id = 'ac100000-0000-0000-0000-00000000000b' and m.nombre = 'Ana'), '1', 'en B, la misma direccion es otra persona y trae su propio consentimiento');
select pg_temp.igual((select estado from public.adn_consentimientos where miembro_id = 'ac400000-0000-0000-0000-000000000001' and canal = 'email'), 'cancelado', 'y no modifica el consentimiento de Ana en A');

-- 4. El envio respeta todo lo anterior
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.adn_registrar_consentimiento('ac400000-0000-0000-0000-000000000004', 'email', 'suscrito');
create temp table env as select public.adn_enviar_mensaje('22222222-2222-2222-2222-222222222222', 'email', 'todos', 'Aviso', 'Hola {{nombre}}') r;
reset role;
select pg_temp.igual((select string_agg(m.nombre, ',' order by m.nombre) from public.adn_mensaje_destinatarios d join public.miembros m on m.id = d.miembro_id where d.estado = 'enviado'), 'Eva', 'el envio solo llega a quien consta como suscrito y no esta protegido por una baja');
select pg_temp.igual((select string_agg(distinct d.motivo, ',' order by d.motivo) from public.adn_mensaje_destinatarios d where d.estado = 'omitido'), 'baja,sin_consentimiento', 'los demas se omiten por baja o por falta de consentimiento');
select pg_temp.igual((select (r -> 'omitidos' ->> 'sin_consentimiento') from env), (select count(*)::text from public.adn_mensaje_destinatarios where motivo = 'sin_consentimiento'), 'el resultado del envio cuenta los omitidos por falta de consentimiento');
select pg_temp.igual((select (total = enviados + omitidos)::text from public.adn_mensajes where clave = '22222222-2222-2222-2222-222222222222'), 'true', 'el total del mensaje cuadra con enviados y omitidos');

-- 5. Borrar al miembro borra su consentimiento
delete from public.miembros where id = 'ac400000-0000-0000-0000-000000000001';
select pg_temp.igual((select count(*)::text from public.adn_consentimientos where miembro_id = 'ac400000-0000-0000-0000-000000000001'), '0', 'borrar a un miembro borra sus consentimientos');
rollback;
