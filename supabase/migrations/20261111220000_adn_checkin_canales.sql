-- Registro por QR, versión v2 del texto: el consentimiento de comunicación se pide por canal, con casillas separadas
-- y sin marcar (correo, WhatsApp y SMS), además de la aceptación de guardar los datos.
--  * Textos versionados: 'checkin' (guardar los datos) y una finalidad por canal, todos en la versión v2 y en cuatro idiomas.
--    La v1 se conserva: es lo que aceptó quien se registró antes.
--  * registrar_checkin recibe las casillas marcadas. Cada una deja evidencia con su texto, su versión y su huella.
--  * Solo una persona nueva queda suscrita (origen qr, con auditoría). A una persona que ya existía no se le cambia el
--    consentimiento: el correo o el teléfono de un formulario público no prueban su identidad. Un envío real debería
--    pedir antes una confirmación (doble confirmación) a la dirección registrada.
-- Reversión: supabase/reversiones/20261111220000_adn_checkin_canales.down.sql

insert into public.adn_consentimiento_textos (finalidad, version, idioma, texto, texto_hash) values
  ('checkin', 'v2', 'es', 'Acepto que {iglesia} guarde estos datos para registrar mi asistencia y acompañarme tras mi visita.', encode(sha256(convert_to('Acepto que {iglesia} guarde estos datos para registrar mi asistencia y acompañarme tras mi visita.', 'UTF8')), 'hex')),
  ('checkin', 'v2', 'en', 'I agree that {iglesia} stores this information to record my attendance and follow up after my visit.', encode(sha256(convert_to('I agree that {iglesia} stores this information to record my attendance and follow up after my visit.', 'UTF8')), 'hex')),
  ('checkin', 'v2', 'fr', 'J''accepte que {iglesia} conserve ces données pour enregistrer ma présence et m''accompagner après ma visite.', encode(sha256(convert_to('J''accepte que {iglesia} conserve ces données pour enregistrer ma présence et m''accompagner après ma visite.', 'UTF8')), 'hex')),
  ('checkin', 'v2', 'pt-BR', 'Aceito que {iglesia} guarde estes dados para registrar a minha presença e me acompanhar após a minha visita.', encode(sha256(convert_to('Aceito que {iglesia} guarde estes dados para registrar a minha presença e me acompanhar após a minha visita.', 'UTF8')), 'hex')),
  ('checkin_email', 'v2', 'es', 'Quiero recibir mensajes de {iglesia} por correo electrónico. Puedo darme de baja cuando quiera.', encode(sha256(convert_to('Quiero recibir mensajes de {iglesia} por correo electrónico. Puedo darme de baja cuando quiera.', 'UTF8')), 'hex')),
  ('checkin_email', 'v2', 'en', 'I want to receive messages from {iglesia} by email. I can unsubscribe at any time.', encode(sha256(convert_to('I want to receive messages from {iglesia} by email. I can unsubscribe at any time.', 'UTF8')), 'hex')),
  ('checkin_email', 'v2', 'fr', 'Je souhaite recevoir des messages de {iglesia} par e-mail. Je peux me désinscrire à tout moment.', encode(sha256(convert_to('Je souhaite recevoir des messages de {iglesia} par e-mail. Je peux me désinscrire à tout moment.', 'UTF8')), 'hex')),
  ('checkin_email', 'v2', 'pt-BR', 'Quero receber mensagens de {iglesia} por e-mail. Posso cancelar quando quiser.', encode(sha256(convert_to('Quero receber mensagens de {iglesia} por e-mail. Posso cancelar quando quiser.', 'UTF8')), 'hex')),
  ('checkin_whatsapp', 'v2', 'es', 'Quiero recibir mensajes de {iglesia} por WhatsApp. Puedo darme de baja cuando quiera.', encode(sha256(convert_to('Quiero recibir mensajes de {iglesia} por WhatsApp. Puedo darme de baja cuando quiera.', 'UTF8')), 'hex')),
  ('checkin_whatsapp', 'v2', 'en', 'I want to receive messages from {iglesia} on WhatsApp. I can unsubscribe at any time.', encode(sha256(convert_to('I want to receive messages from {iglesia} on WhatsApp. I can unsubscribe at any time.', 'UTF8')), 'hex')),
  ('checkin_whatsapp', 'v2', 'fr', 'Je souhaite recevoir des messages de {iglesia} sur WhatsApp. Je peux me désinscrire à tout moment.', encode(sha256(convert_to('Je souhaite recevoir des messages de {iglesia} sur WhatsApp. Je peux me désinscrire à tout moment.', 'UTF8')), 'hex')),
  ('checkin_whatsapp', 'v2', 'pt-BR', 'Quero receber mensagens de {iglesia} pelo WhatsApp. Posso cancelar quando quiser.', encode(sha256(convert_to('Quero receber mensagens de {iglesia} pelo WhatsApp. Posso cancelar quando quiser.', 'UTF8')), 'hex')),
  ('checkin_sms', 'v2', 'es', 'Quiero recibir mensajes de {iglesia} por SMS. Puedo darme de baja cuando quiera.', encode(sha256(convert_to('Quiero recibir mensajes de {iglesia} por SMS. Puedo darme de baja cuando quiera.', 'UTF8')), 'hex')),
  ('checkin_sms', 'v2', 'en', 'I want to receive messages from {iglesia} by SMS. I can unsubscribe at any time.', encode(sha256(convert_to('I want to receive messages from {iglesia} by SMS. I can unsubscribe at any time.', 'UTF8')), 'hex')),
  ('checkin_sms', 'v2', 'fr', 'Je souhaite recevoir des messages de {iglesia} par SMS. Je peux me désinscrire à tout moment.', encode(sha256(convert_to('Je souhaite recevoir des messages de {iglesia} par SMS. Je peux me désinscrire à tout moment.', 'UTF8')), 'hex')),
  ('checkin_sms', 'v2', 'pt-BR', 'Quero receber mensagens de {iglesia} por SMS. Posso cancelar quando quiser.', encode(sha256(convert_to('Quero receber mensagens de {iglesia} por SMS. Posso cancelar quando quiser.', 'UTF8')), 'hex'));

alter table public.adn_consentimiento_evidencias drop constraint adn_consentimiento_evidencias_forma;
alter table public.adn_consentimiento_evidencias add constraint adn_consentimiento_evidencias_forma check (
  (tipo = 'checkin' and finalidad is not null and texto_version is not null)
  or (tipo = 'importacion' and canal is not null and texto_original is not null));

drop function public.registrar_checkin(text, text, text, text, text, text, text, text);
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text, p_texto_version text default null, p_idioma text default null, p_canales text[] default null)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
  v_ver text := nullif(btrim(coalesce(p_texto_version, '')), ''); v_hash text;
  v_canal text; v_hash_c text;
begin
  select ec.iglesia_id, ec.evento_id, ec.activo, ec.abre_en, ec.cierra_en, ec.max_registros,
         e.titulo, e.inicia_en, e.termina_en, e.casa_oracion_id, e.cancelado, i.modo_alias
    into c
    from public.evento_checkin ec
    join public.eventos e on e.id = ec.evento_id and e.iglesia_id = ec.iglesia_id
    join public.iglesias i on i.id = ec.iglesia_id and i.activa
   where ec.token = p_token
   for update of ec;
  if not found or not c.activo or c.cancelado then return 'no_valido'; end if;
  -- La pagina publica deja el apellido opcional porque no sabe el modo de la iglesia: aqui se exige si no es modo alias
  if not c.modo_alias and btrim(coalesce(p_apellido, '')) = '' then return 'datos'; end if;

  v_abre := coalesce(c.abre_en, c.inicia_en - interval '2 hours');
  v_cierra := coalesce(c.cierra_en, coalesce(c.termina_en, c.inicia_en + interval '6 hours') + interval '1 hour');
  if now() < v_abre or now() > v_cierra then return 'cerrado'; end if;

  select count(*) into v_n from public.checkin_registros where evento_id = c.evento_id;
  if v_n >= c.max_registros then return 'lleno'; end if;
  select count(*) into v_n from public.checkin_registros
    where evento_id = c.evento_id and ip_hash = p_ip_hash and created_at > now() - interval '10 minutes';
  if v_n >= 5 then return 'limite'; end if;
  select count(*) into v_n from public.checkin_registros
    where evento_id = c.evento_id and created_at > now() - interval '1 minute';
  if v_n >= 40 then return 'limite'; end if;

  -- Ya existe si coincide el correo, o el telefono y el nombre completo juntos (un telefono de familia no fusiona personas)
  v_dig := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  select m.id into v_miembro from public.miembros m
   where m.iglesia_id = c.iglesia_id and m.activo
     and ((coalesce(p_email, '') <> '' and lower(m.email) = lower(p_email))
       or (length(v_dig) >= 7
           and right(regexp_replace(coalesce(m.telefono, ''), '\D', '', 'g'), 9) = right(v_dig, 9)
           and lower(btrim(m.nombre)) = lower(btrim(p_nombre))
           and lower(btrim(m.apellido)) = lower(btrim(p_apellido))))
   order by m.created_at
   limit 1;

  if v_miembro is null then
    begin
      insert into public.miembros (iglesia_id, nombre, apellido, email, telefono, casa_oracion_id, activo, notas)
        values (c.iglesia_id, btrim(p_nombre), btrim(p_apellido), nullif(btrim(coalesce(p_email, '')), ''), btrim(p_telefono),
                c.casa_oracion_id, true, 'Registrado por QR en el evento: ' || c.titulo)
        returning id into v_miembro;
    exception when check_violation then
      if sqlerrm like 'PLAN_LIMITE%' then return 'cerrado'; end if;
      raise;
    end;
    v_nuevo := true;
    insert into public.consolidaciones (iglesia_id, miembro_id, fecha_conversion, notas)
      values (c.iglesia_id, v_miembro, now(), 'Registro por QR en el evento: ' || c.titulo);
  end if;

  insert into public.asistencia_evento (iglesia_id, evento_id, miembro_id, presente)
    values (c.iglesia_id, c.evento_id, v_miembro, true)
    on conflict (evento_id, miembro_id) do update set presente = true;
  insert into public.checkin_registros (iglesia_id, evento_id, miembro_id, ip_hash, creado)
    values (c.iglesia_id, c.evento_id, v_miembro, p_ip_hash, v_nuevo);

  -- Evidencia de lo que aceptó quien se registró: qué texto (versión y huella) y cuándo. Cada registro deja una fila.
  -- La versión la afirma la página: si no consta en la tabla de textos se anota 'sin_version' y no se inventa una huella.
  select t.texto_hash into v_hash from public.adn_consentimiento_textos t where t.finalidad = 'checkin' and t.version = v_ver and t.idioma = p_idioma;
  insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, finalidad, texto_version, idioma, texto_hash, evento_id, origen)
    values (c.iglesia_id, v_miembro, 'checkin', 'checkin', case when v_hash is null then 'sin_version' else v_ver end,
            case when v_hash is null then null else p_idioma end, v_hash, c.evento_id, 'qr');

  -- Casillas de canal (correo, WhatsApp, SMS): cada una marcada deja su evidencia con el texto que acompañaba a esa casilla.
  -- Solo una persona NUEVA queda suscrita: a quien ya existía no se le cambia el consentimiento, porque el correo o el
  -- teléfono que escribe alguien en un formulario público no prueban que sea la misma persona. Sin una versión de texto
  -- verificable en la tabla, la casilla queda anotada pero no concede nada.
  for v_canal in select distinct u from unnest(coalesce(p_canales, '{}')) u order by u loop
    continue when v_canal not in ('email', 'whatsapp', 'sms');
    continue when v_canal = 'email' and coalesce(btrim(p_email), '') = '';
    select t.texto_hash into v_hash_c from public.adn_consentimiento_textos t where t.finalidad = 'checkin_' || v_canal and t.version = v_ver and t.idioma = p_idioma;
    insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, canal, finalidad, texto_version, idioma, texto_hash, evento_id, aplicado, origen)
      values (c.iglesia_id, v_miembro, 'checkin', v_canal, 'checkin_' || v_canal, case when v_hash_c is null then 'sin_version' else v_ver end,
              case when v_hash_c is null then null else p_idioma end, v_hash_c, c.evento_id, v_nuevo and v_hash_c is not null, 'qr');
    if v_nuevo and v_hash_c is not null then
      perform private.adn_escribir_consentimiento(c.iglesia_id, v_miembro, v_canal, 'suscrito', 'qr', null);
    end if;
  end loop;

  return case when v_nuevo then 'ok_nuevo' else 'ok_existente' end;
end;
$$;

revoke execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]) to service_role;
