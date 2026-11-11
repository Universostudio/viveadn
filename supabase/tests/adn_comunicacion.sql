-- Pruebas de la comunicacion: destinatarios, personalizacion, bajas, permisos, aislamiento, limites y,
-- sobre todo, que el unico proveedor posible es el sumidero (no sale nada a nadie).
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
create or replace function pg_temp.falla(sentencia text, texto text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if sqlerrm like '%' || texto || '%' then raise notice 'OK: %', msg; return; end if;
    raise exception 'FALLO: % (error inesperado: %)', msg, sqlerrm;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.falla(text, text, text) to authenticated, anon, service_role;

insert into auth.users (id) select ('ab000000-0000-0000-0000-00000000000' || n)::uuid from generate_series(1, 7) n;
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ab100000-0000-0000-0000-00000000000a', 'Prueba Com A', 'prueba-com-a', 'ES', 'Sevilla', 'premium'),
  ('ab100000-0000-0000-0000-00000000000b', 'Prueba Com B', 'prueba-com-b', 'ES', 'Sevilla', 'premium'),
  ('ab100000-0000-0000-0000-00000000000d', 'Prueba Com D', 'prueba-com-d', 'ES', 'Sevilla', 'premium'),
  ('ab100000-0000-0000-0000-00000000000e', 'Prueba Com E', 'prueba-com-e', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('ab000000-0000-0000-0000-000000000001', 'ab100000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@prueba.test', 'propietario', true),
  ('ab000000-0000-0000-0000-000000000002', 'ab100000-0000-0000-0000-00000000000a', 'Adm', 'A', 'adm@prueba.test', 'administrador', true),
  ('ab000000-0000-0000-0000-000000000003', 'ab100000-0000-0000-0000-00000000000a', 'Col', 'A', 'col@prueba.test', 'colaborador', true),
  ('ab000000-0000-0000-0000-000000000004', 'ab100000-0000-0000-0000-00000000000a', 'Lid', 'A', 'lid@prueba.test', 'lider_casa', true),
  ('ab000000-0000-0000-0000-000000000005', 'ab100000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@prueba.test', 'propietario', true),
  ('ab000000-0000-0000-0000-000000000006', 'ab100000-0000-0000-0000-00000000000d', 'P', 'D', 'pd@prueba.test', 'propietario', true),
  ('ab000000-0000-0000-0000-000000000007', 'ab100000-0000-0000-0000-00000000000e', 'P', 'E', 'pe@prueba.test', 'propietario', true);

select pg_temp.igual((select string_agg(r.clave, ',' order by r.clave) from public.roles r join public.rol_permisos rp on rp.rol_id = r.id where r.iglesia_id = 'ab100000-0000-0000-0000-00000000000a' and rp.permiso = 'comunicacion.enviar'), 'administrador,coadministrador', 'una iglesia nueva siembra comunicacion.enviar en el administrador y el coadministrador (el propietario lo tiene de serie)');
select pg_temp.igual((select sensible::text from public.permisos where clave = 'comunicacion.enviar'), 'true', 'enviar mensajes es un permiso sensible');

insert into public.casas_oracion (id, iglesia_id, codigo_zona, nombre, pais, ciudad, direccion, dia_reunion) values
  ('ab300000-0000-0000-0000-000000000001', 'ab100000-0000-0000-0000-00000000000a', 'ZN-1', 'Casa Norte', 'ES', 'Sevilla', 'x', 'miércoles');
insert into public.miembros (id, iglesia_id, nombre, apellido, email, telefono, nivel_compromiso, casa_oracion_id, created_at, activo) values
  ('ab400000-0000-0000-0000-000000000001', 'ab100000-0000-0000-0000-00000000000a', 'Ana', 'Pérez', 'ana@x.test', '+34 600 111 222', 'nuevo', 'ab300000-0000-0000-0000-000000000001', now() - interval '3 days', true),
  ('ab400000-0000-0000-0000-000000000002', 'ab100000-0000-0000-0000-00000000000a', 'Luis', 'Gil', ' LUIS@x.test ', null, 'lider', null, now() - interval '100 days', true),
  ('ab400000-0000-0000-0000-000000000003', 'ab100000-0000-0000-0000-00000000000a', 'Eva', 'Sol', 'eva@x.test', null, 'maduro', null, now() - interval '100 days', true),
  ('ab400000-0000-0000-0000-000000000004', 'ab100000-0000-0000-0000-00000000000a', 'Max', 'Ray', null, '600333444', 'nuevo', null, now() - interval '5 days', true),
  ('ab400000-0000-0000-0000-000000000005', 'ab100000-0000-0000-0000-00000000000a', 'Pía', 'Mar', 'ana@x.test', null, 'multiplicador', null, now() - interval '100 days', true),
  ('ab400000-0000-0000-0000-000000000006', 'ab100000-0000-0000-0000-00000000000a', 'Inactivo', 'X', 'inactivo@x.test', '600999888', 'lider', null, now() - interval '100 days', false),
  ('ab400000-0000-0000-0000-000000000007', 'ab100000-0000-0000-0000-00000000000a', 'Mal', 'Correo', 'no-es-correo', '0000000', 'maduro', null, now() - interval '100 days', true),
  ('ab400000-0000-0000-0000-0000000000b1', 'ab100000-0000-0000-0000-00000000000b', 'OTRA-IGLESIA', 'B', 'otra@x.test', '600777666', 'lider', null, now(), true);
insert into public.consolidaciones (iglesia_id, miembro_id, fecha_conversion, completado) values
  ('ab100000-0000-0000-0000-00000000000a', 'ab400000-0000-0000-0000-000000000004', now(), false),
  ('ab100000-0000-0000-0000-00000000000a', 'ab400000-0000-0000-0000-000000000003', now(), true);
insert into public.adn_comunicacion_bajas (iglesia_id, miembro_id, canal) values ('ab100000-0000-0000-0000-00000000000a', 'ab400000-0000-0000-0000-000000000003', 'email');

-- 1. Vista previa y envio, como propietario de A
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select (public.adn_vista_previa_envio('email', 'todos') = '{"baja": 1, "total": 6, "recibiran": 2, "repetido": 1, "sin_destino": 2}'::jsonb)::text), 'true', 'vista previa por correo: 6 activos, 2 reciben, 2 sin correo valido, 1 de baja y 1 repetido');
select pg_temp.igual((select public.adn_vista_previa_envio('whatsapp', 'todos') ->> 'recibiran'), '2', 'por WhatsApp reciben Ana y Max (el telefono de ceros no vale)');
select pg_temp.igual((select public.adn_vista_previa_envio('email', 'nuevos') ->> 'recibiran'), '1', 'nuevos (ultimos 30 dias) por correo: Ana');
select pg_temp.igual((select public.adn_vista_previa_envio('email', 'lideres') ->> 'recibiran'), '2', 'lideres por correo: Luis y Pia (Ana no esta en el segmento, asi que Pia ya no es repetida)');
select pg_temp.igual((select public.adn_vista_previa_envio('whatsapp', 'consolidacion') ->> 'recibiran'), '1', 'en consolidacion por WhatsApp: Max (Eva ya completo)');
create temp table env as select public.adn_enviar_mensaje('11111111-1111-1111-1111-111111111111', 'email', 'todos', 'Hola desde {{iglesia}}', 'Hola {{nombre}}, bienvenido a {{iglesia}}. Este {{dia}} nos vemos.', 'día acordado') r;
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select ((r -> 'enviados') = '2'::jsonb and (r -> 'omitidos') = '{"baja": 1, "repetido": 1, "sin_destino": 2}'::jsonb)::text from env), 'true', 'el envio entrega a 2 y omite a 4, con su motivo');
select pg_temp.igual((select proveedor || ':' || estado || ':' || total || ':' || enviados || ':' || omitidos from public.adn_mensajes where clave = '11111111-1111-1111-1111-111111111111'), 'sumidero:enviado:6:2:4', 'el mensaje queda registrado en el sumidero');
select pg_temp.igual((select destino || ' | ' || texto_final from public.adn_mensaje_destinatarios d join public.miembros m on m.id = d.miembro_id where m.nombre = 'Ana' and d.estado = 'enviado'), 'ana@x.test | Hola Ana, bienvenido a Prueba Com A. Este miércoles nos vemos.', 'personalizado: nombre, iglesia y el dia de su casa de oracion');
select pg_temp.igual((select destino || ' | ' || texto_final from public.adn_mensaje_destinatarios d join public.miembros m on m.id = d.miembro_id where m.nombre = 'Luis' and d.estado = 'enviado'), 'luis@x.test | Hola Luis, bienvenido a Prueba Com A. Este día acordado nos vemos.', 'sin casa, usa el dia por defecto, y el correo se normaliza');
select pg_temp.igual((select string_agg(m.nombre || ':' || d.motivo, ',' order by m.nombre) from public.adn_mensaje_destinatarios d join public.miembros m on m.id = d.miembro_id where d.estado = 'omitido'), 'Eva:baja,Mal:sin_destino,Max:sin_destino,Pía:repetido', 'los omitidos quedan con su motivo');
select pg_temp.igual((select count(*)::text from public.adn_mensaje_destinatarios where estado = 'enviado' and referencia not like 'sumidero:%'), '0', 'toda entrega lleva la referencia del sumidero: ninguna salio a un proveedor');
select pg_temp.igual((select count(*)::text from public.adn_mensaje_destinatarios d join public.miembros m on m.id = d.miembro_id where m.nombre in ('Inactivo', 'OTRA-IGLESIA')), '0', 'ni un miembro inactivo ni uno de otra iglesia');

-- 2. Idempotencia: repetir la peticion no duplica nada
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select (public.adn_enviar_mensaje('11111111-1111-1111-1111-111111111111', 'email', 'todos', 'x', 'otro texto distinto') ->> 'repetido')), 'true', 'repetir la misma clave devuelve el envio ya hecho');
reset role;
select pg_temp.igual((select count(*)::text from public.adn_mensajes where iglesia_id = 'ab100000-0000-0000-0000-00000000000a'), '1', 'y no crea otro mensaje');
select pg_temp.igual((select count(*)::text from public.adn_mensaje_destinatarios where iglesia_id = 'ab100000-0000-0000-0000-00000000000a'), '6', 'ni otras entregas');

-- 3. Otros canales y segmentos
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select public.adn_enviar_mensaje('22222222-2222-2222-2222-222222222222', 'whatsapp', 'todos', null, 'Hola {{nombre}}') ->> 'enviados'), '2', 'WhatsApp: entrega a Ana y a Max');
select pg_temp.igual((select asunto from public.adn_mensajes where clave = '22222222-2222-2222-2222-222222222222'), null, 'WhatsApp no lleva asunto');
select pg_temp.igual((select destino from public.adn_mensaje_destinatarios d join public.miembros m on m.id = d.miembro_id where m.nombre = 'Max' and d.estado = 'enviado' and d.mensaje_id = (select id from public.adn_mensajes where clave = '22222222-2222-2222-2222-222222222222')), '600333444', 'el telefono sale en forma canonica');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- 4. Datos invalidos
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.falla($$select public.adn_enviar_mensaje(gen_random_uuid(), 'email', 'todos', 'Asunto', '   ')$$, 'ADN_TEXTO_INVALIDO', 'un texto vacio se rechaza');
select pg_temp.falla($$select public.adn_enviar_mensaje(gen_random_uuid(), 'email', 'todos', 'Asunto', repeat('x', 4097))$$, 'ADN_TEXTO_INVALIDO', 'un texto de mas de 4096 se rechaza');
select pg_temp.falla($$select public.adn_enviar_mensaje(gen_random_uuid(), 'email', 'todos', null, 'Hola')$$, 'ADN_ASUNTO_INVALIDO', 'un correo sin asunto se rechaza');
select pg_temp.falla($$select public.adn_enviar_mensaje(gen_random_uuid(), 'email', 'todos', repeat('x', 151), 'Hola')$$, 'ADN_ASUNTO_INVALIDO', 'un asunto de mas de 150 se rechaza');
select pg_temp.falla($$select public.adn_enviar_mensaje(gen_random_uuid(), 'push', 'todos', null, 'Hola')$$, 'ADN_DATOS_INVALIDOS', 'el canal push no existe todavia');
select pg_temp.falla($$select public.adn_enviar_mensaje(gen_random_uuid(), 'email', 'otro', 'A', 'Hola')$$, 'ADN_DATOS_INVALIDOS', 'un segmento desconocido se rechaza');
select pg_temp.falla($$select public.adn_enviar_mensaje(null, 'email', 'todos', 'A', 'Hola')$$, 'ADN_DATOS_INVALIDOS', 'sin clave se rechaza');
select pg_temp.falla($$select public.adn_vista_previa_envio('sms', 'todos')$$, 'ADN_DATOS_INVALIDOS', 'la vista previa tambien valida');
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select count(*)::text from public.adn_mensajes where iglesia_id = 'ab100000-0000-0000-0000-00000000000a'), '2', 'ningun rechazo deja un mensaje a medias');

-- 5. Permisos: administrador si; colaborador, lider de casa y visitante no
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select public.adn_enviar_mensaje('33333333-3333-3333-3333-333333333333', 'whatsapp', 'lideres', null, 'Hola') ->> 'proveedor'), 'sumidero', 'un administrador envia');
select pg_temp.igual((select count(*)::text from public.adn_mensajes), '3', 'y ve el historial');
reset role;
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.falla($$select public.adn_enviar_mensaje(gen_random_uuid(), 'whatsapp', 'todos', null, 'Hola')$$, 'ADN_SIN_PERMISO', 'un colaborador no envia');
select pg_temp.falla($$select public.adn_vista_previa_envio('email', 'todos')$$, 'ADN_SIN_PERMISO', 'ni ve la vista previa');
select pg_temp.igual((select count(*)::text from public.adn_mensajes), '0', 'ni ve el historial');
select pg_temp.igual((select count(*)::text from public.adn_mensaje_destinatarios), '0', 'ni las entregas');
select pg_temp.falla($$insert into public.adn_comunicacion_bajas (miembro_id, canal) values ('ab400000-0000-0000-0000-000000000001', 'email')$$, 'row-level security', 'ni registra bajas');
reset role;
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.falla($$select public.adn_enviar_mensaje(gen_random_uuid(), 'whatsapp', 'todos', null, 'Hola')$$, 'ADN_SIN_PERMISO', 'un lider de casa no envia');
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select pg_temp.falla($$select public.adn_enviar_mensaje(gen_random_uuid(), 'whatsapp', 'todos', null, 'Hola')$$, 'permission denied', 'un visitante no envia');
select pg_temp.falla($$select * from public.adn_mensajes$$, 'permission denied', 'ni lee el historial');
reset role;

-- 6. Nadie escribe ni toca el historial a mano; el proveedor solo puede ser el sumidero
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.falla($$insert into public.adn_mensajes (clave, canal, segmento, texto, total, enviados, omitidos) values (gen_random_uuid(), 'whatsapp', 'todos', 'x', 0, 0, 0)$$, 'permission denied', 'ni el propietario inserta mensajes a mano');
select pg_temp.falla($$update public.adn_mensajes set texto = 'otro'$$, 'permission denied', 'ni los edita');
select pg_temp.falla($$delete from public.adn_mensaje_destinatarios$$, 'permission denied', 'ni borra entregas');
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.falla($$update public.adn_mensajes set proveedor = 'twilio'$$, 'adn_mensajes_proveedor_check', 'ni siquiera el servidor puede apuntar a un proveedor real: exige una migracion nueva');
select pg_temp.falla($$insert into public.adn_mensajes (iglesia_id, clave, canal, segmento, texto, proveedor, total, enviados, omitidos) values ('ab100000-0000-0000-0000-00000000000a', gen_random_uuid(), 'whatsapp', 'todos', 'x', 'smtp', 0, 0, 0)$$, 'adn_mensajes_proveedor_check', 'tampoco insertando directamente');

-- 7. Aislamiento entre iglesias
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_mensajes), '0', 'B no ve los mensajes de A');
select pg_temp.igual((select (public.adn_vista_previa_envio('email', 'todos') ->> 'recibiran')), '1', 'B solo cuenta a sus propios miembros');
select pg_temp.igual((select public.adn_enviar_mensaje('44444444-4444-4444-4444-444444444444', 'email', 'todos', 'Hola', 'Hola {{nombre}}') ->> 'enviados'), '1', 'B envia solo a su miembro');
select pg_temp.falla($$insert into public.adn_comunicacion_bajas (iglesia_id, miembro_id, canal) values ('ab100000-0000-0000-0000-00000000000b', 'ab400000-0000-0000-0000-000000000001', 'email')$$, 'adn_bajas_miembro_fk', 'B no da de baja a un miembro de A');
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select count(*)::text from public.adn_mensaje_destinatarios d join public.miembros m on m.id = d.miembro_id where d.mensaje_id = (select id from public.adn_mensajes where clave = '44444444-4444-4444-4444-444444444444') and m.iglesia_id <> 'ab100000-0000-0000-0000-00000000000b'), '0', 'ninguna entrega de B apunta a un miembro de A');

-- 8. Bajas: darse de baja saca de la lista, tambien a quien comparte la direccion, y quitarla lo devuelve
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into public.adn_comunicacion_bajas (miembro_id, canal) values ('ab400000-0000-0000-0000-000000000001', 'email');
select pg_temp.igual((select (public.adn_vista_previa_envio('email', 'todos') = '{"baja": 3, "total": 6, "recibiran": 1, "repetido": 0, "sin_destino": 2}'::jsonb)::text), 'true',
  'Ana de baja del correo: ella, Eva y Pia (que comparte la direccion de Ana) quedan fuera; solo recibe Luis');
select pg_temp.igual((select public.adn_vista_previa_envio('whatsapp', 'todos') ->> 'recibiran'), '2', 'la baja del correo no afecta a WhatsApp');
delete from public.adn_comunicacion_bajas where miembro_id = 'ab400000-0000-0000-0000-000000000001' and canal = 'email';
select pg_temp.igual((select (public.adn_vista_previa_envio('email', 'todos') = '{"baja": 1, "total": 6, "recibiran": 2, "repetido": 1, "sin_destino": 2}'::jsonb)::text), 'true', 'quitar la baja devuelve a Ana a la lista');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- 9. Tope diario: 20 mensajes por iglesia y dia (iglesia D, sin miembros)
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000006', true);
set local role authenticated;
do $$ begin
  for i in 1..20 loop perform public.adn_enviar_mensaje(gen_random_uuid(), 'whatsapp', 'todos', null, 'x'); end loop;
end $$;
select pg_temp.falla($$select public.adn_enviar_mensaje(gen_random_uuid(), 'whatsapp', 'todos', null, 'x')$$, 'ADN_LIMITE_DIARIO', 'el mensaje 21 del dia se rechaza');
select pg_temp.igual((select count(*)::text from public.adn_mensajes), '20', 'y no deja nada a medias');
select pg_temp.igual((select estado from public.adn_mensajes limit 1), 'sin_destinatarios', 'un envio sin nadie a quien llegar queda como sin destinatarios');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- 10. Tope de destinatarios: 2000 por mensaje (iglesia E)
insert into public.miembros (iglesia_id, nombre, apellido, email) select 'ab100000-0000-0000-0000-00000000000e', 'M' || i, 'E', 'm' || i || '@e.test' from generate_series(1, 2001) i;
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000007', true);
set local role authenticated;
select pg_temp.falla($$select public.adn_enviar_mensaje(gen_random_uuid(), 'email', 'todos', 'A', 'Hola')$$, 'ADN_DEMASIADOS_DESTINATARIOS', 'mas de 2000 destinatarios se rechaza');
select pg_temp.igual((select count(*)::text from public.adn_mensajes), '0', 'y no se registra nada');
reset role;
select set_config('request.jwt.claim.sub', '', true);
delete from public.miembros where nombre = 'M1' and iglesia_id = 'ab100000-0000-0000-0000-00000000000e';
select set_config('request.jwt.claim.sub', 'ab000000-0000-0000-0000-000000000007', true);
set local role authenticated;
select pg_temp.igual((select public.adn_enviar_mensaje(gen_random_uuid(), 'email', 'todos', 'A', 'Hola {{nombre}}') ->> 'enviados'), '2000', 'exactamente 2000 si entra');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- 11. Borrar a un miembro borra sus entregas y sus bajas
insert into public.adn_comunicacion_bajas (iglesia_id, miembro_id, canal) values ('ab100000-0000-0000-0000-00000000000a', 'ab400000-0000-0000-0000-000000000001', 'whatsapp');
delete from public.miembros where id = 'ab400000-0000-0000-0000-000000000001';
select pg_temp.igual((select (select count(*) from public.adn_mensaje_destinatarios where miembro_id = 'ab400000-0000-0000-0000-000000000001') + (select count(*) from public.adn_comunicacion_bajas where miembro_id = 'ab400000-0000-0000-0000-000000000001'))::text, '0', 'sus entregas y sus bajas se van con el');
rollback;
