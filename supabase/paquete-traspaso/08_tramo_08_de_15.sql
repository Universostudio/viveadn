-- Vive ADN, traspaso al proyecto real, archivo 9 de 19: tramo 8 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regclass('public.adn_confirmaciones') is not null then raise notice 'Tramo 8 de 15 ya aplicado: no se repite'; return; end if;
  if not (to_regprocedure('private.adn_aplicar_consentimiento(uuid,jsonb,text,text,jsonb)') is not null) then raise exception 'Falta aplicar antes el tramo 7 de 15: no se sigue.'; end if;
  execute $cuerpo$

revoke execute on function private.adn_aplicar_consentimiento(uuid, jsonb, text, text, jsonb) from public, anon;
grant execute on function private.adn_aplicar_consentimiento(uuid, jsonb, text, text, jsonb) to authenticated, service_role;

create or replace function public.adn_importar_miembros(p_filas jsonb, p_origen text default 'google')
returns jsonb language plpgsql set search_path to '' as $$
declare
  ig uuid := private.get_iglesia_id();
  hoy date := (now() at time zone 'UTC')::date;
  f jsonb;
  c jsonb;
  nuevo uuid;
  nombre text; apellido text; email text; tel text; nac date; notas text;
  correos text[]; telefonos text[];
  clave_nombre text;
  existe boolean;
  n_ok int := 0; n_dup_correo int := 0; n_dup_tel int := 0; n_dup_nombre int := 0; n_invalidas int := 0; n_notas int := 0;
  extra_tipo text; extra_valor text; extra_etiqueta text; extra_tel text;
  orden int;
  -- Una nota que parece guardar una clave no se importa
  clave_re constant text := '\m(contrase(ñ|n)a|password|passwd|passcode|clave|pin|secreto?|secret)\s*[:=]';
  -- En este lote, para detectar repetidos entre sus propias filas
  vistos_correos text[] := '{}'; vistos_tel text[] := '{}'; vistos_nombre text[] := '{}';
begin
  if ig is null then raise exception 'ADN_SIN_IGLESIA'; end if;
  if not (select private.tiene_permiso('miembros.importar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if coalesce((select modo_alias from public.iglesias where id = ig), false) then raise exception 'ADN_MODO_ALIAS'; end if;
  if p_origen is null or p_origen !~ '^[a-z0-9_-]{1,30}$' then raise exception 'ADN_ORIGEN_INVALIDO'; end if;
  if jsonb_typeof(p_filas) is distinct from 'array' or jsonb_array_length(p_filas) > 1000 then raise exception 'ADN_LOTE_INVALIDO'; end if;

  for f in select value from jsonb_array_elements(p_filas) loop
    nombre := left(btrim(coalesce(f ->> 'nombre', '')), 100);
    apellido := left(btrim(coalesce(f ->> 'apellido', '')), 100);
    if nombre = '' then n_invalidas := n_invalidas + 1; continue; end if;

    -- Correo principal y adicionales, en minusculas y con forma de correo
    correos := '{}';
    email := lower(btrim(coalesce(f ->> 'email', '')));
    if email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(email) <= 254 then correos := array[email]; else email := null; end if;
    -- Telefono principal y adicionales, solo digitos y un + inicial, entre 7 y 15 digitos
    telefonos := '{}';
    tel := public.adn_telefono_canonico(f ->> 'telefono');
    if tel ~ '^\+?[0-9]{7,15}$' and tel !~ '^\+?(.)\1+$' then telefonos := array[tel]; else tel := null; end if;
    for c in select value from jsonb_array_elements(case when jsonb_typeof(f -> 'contactos') = 'array' then f -> 'contactos' else '[]'::jsonb end) loop
      if c ->> 'tipo' = 'correo' then
        extra_valor := lower(btrim(coalesce(c ->> 'valor', '')));
        if extra_valor ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(extra_valor) <= 254 and not extra_valor = any (correos) then correos := correos || extra_valor; end if;
      elsif c ->> 'tipo' = 'telefono' then
        extra_tel := public.adn_telefono_canonico(c ->> 'valor');
        if extra_tel ~ '^\+?[0-9]{7,15}$' and extra_tel !~ '^\+?(.)\1+$' and not extra_tel = any (telefonos) then telefonos := telefonos || extra_tel; end if;
      end if;
    end loop;

    -- Duplicados
    existe := false;
    if array_length(correos, 1) > 0 then
      if correos && vistos_correos
         or exists (select 1 from public.miembros m where lower(m.email) = any (correos))
         or exists (select 1 from public.adn_miembro_contactos x where x.tipo = 'correo' and lower(x.valor) = any (correos)) then
        n_dup_correo := n_dup_correo + 1;
        perform private.adn_aplicar_consentimiento(private.adn_miembro_existente(correos, '{}', null), f -> 'consentimiento', p_origen, 'endurecer', f -> 'consentimiento_original');
        continue;
      end if;
    elsif array_length(telefonos, 1) > 0 then
      if telefonos && vistos_tel
         or exists (select 1 from public.miembros m where public.adn_telefono_canonico(m.telefono) = any (telefonos))
         or exists (select 1 from public.adn_miembro_contactos x where x.tipo = 'telefono' and public.adn_telefono_canonico(x.valor) = any (telefonos)) then
        n_dup_tel := n_dup_tel + 1;
        perform private.adn_aplicar_consentimiento(private.adn_miembro_existente('{}', telefonos, null), f -> 'consentimiento', p_origen, 'endurecer', f -> 'consentimiento_original');
        continue;
      end if;
    else
      clave_nombre := lower(regexp_replace(btrim(nombre || ' ' || apellido), '\s+', ' ', 'g'));
      if clave_nombre = any (vistos_nombre)
         or exists (select 1 from public.miembros m where lower(regexp_replace(btrim(m.nombre || ' ' || m.apellido), '\s+', ' ', 'g')) = clave_nombre) then
        n_dup_nombre := n_dup_nombre + 1;
        perform private.adn_aplicar_consentimiento(private.adn_miembro_existente('{}', '{}', clave_nombre), f -> 'consentimiento', p_origen, 'endurecer', f -> 'consentimiento_original');
        continue;
      end if;
    end if;

    -- Fecha de nacimiento: solo una fecha real entre 1900 y hoy
    nac := null;
    begin
      nac := nullif(btrim(coalesce(f ->> 'fecha_nacimiento', '')), '')::date;
      if nac < date '1900-01-01' or nac > hoy then nac := null; end if;
    exception when others then nac := null;
    end;

    notas := nullif(left(btrim(coalesce(f ->> 'notas', '')), 1000), '');
    if notas ~* clave_re then notas := null; n_notas := n_notas + 1; end if;

    nuevo := gen_random_uuid();
    insert into public.miembros (id, nombre, apellido, email, telefono, fecha_nacimiento, notas, activo)
    values (nuevo, nombre, apellido, correos[1], telefonos[1], nac, notas, true);
    -- Estado de suscripcion de cada canal que traiga el archivo (consentimiento): lo guarda la funcion privada
    perform private.adn_aplicar_consentimiento(nuevo, f -> 'consentimiento', p_origen, 'nuevo', f -> 'consentimiento_original');

    -- Datos adicionales: el segundo correo en adelante, el segundo telefono en adelante, direcciones y etiquetas
    orden := 0;
    foreach extra_valor in array coalesce(correos[2:array_length(correos, 1)], '{}') loop
      orden := orden + 1;
      insert into public.adn_miembro_contactos (miembro_id, tipo, valor, orden) values (nuevo, 'correo', extra_valor, orden) on conflict do nothing;
    end loop;
    foreach extra_valor in array coalesce(telefonos[2:array_length(telefonos, 1)], '{}') loop
      orden := orden + 1;
      insert into public.adn_miembro_contactos (miembro_id, tipo, valor, orden) values (nuevo, 'telefono', extra_valor, orden) on conflict do nothing;
    end loop;
    for c in select value from jsonb_array_elements(case when jsonb_typeof(f -> 'contactos') = 'array' then f -> 'contactos' else '[]'::jsonb end) loop
      extra_tipo := c ->> 'tipo';
      continue when extra_tipo not in ('direccion', 'etiqueta');
      extra_valor := left(btrim(coalesce(c ->> 'valor', '')), 500);
      continue when extra_valor = '';
      extra_etiqueta := nullif(left(btrim(coalesce(c ->> 'etiqueta', '')), 60), '');
      orden := orden + 1;
      insert into public.adn_miembro_contactos (miembro_id, tipo, etiqueta, valor, orden)
      values (nuevo, extra_tipo, extra_etiqueta, extra_valor, orden) on conflict do nothing;
    end loop;
    -- Marca de la importacion, para poder encontrar (y deshacer) lo que entro de una vez
    insert into public.adn_miembro_contactos (miembro_id, tipo, etiqueta, valor, orden)
    values (nuevo, 'etiqueta', 'importacion', 'Importado ' || hoy::text || ' (' || p_origen || ')', 999) on conflict do nothing;

    vistos_correos := vistos_correos || correos;
    vistos_tel := vistos_tel || telefonos;
    if array_length(correos, 1) is null and array_length(telefonos, 1) is null then
      vistos_nombre := vistos_nombre || lower(regexp_replace(btrim(nombre || ' ' || apellido), '\s+', ' ', 'g'));
    end if;
    n_ok := n_ok + 1;
  end loop;

  return jsonb_build_object('importados', n_ok, 'duplicados_correo', n_dup_correo, 'duplicados_telefono', n_dup_tel,
                            'duplicados_nombre', n_dup_nombre, 'invalidas', n_invalidas, 'notas_descartadas', n_notas);
end $$;
-- ===== 20261111220000_adn_checkin_canales (origen sha256 0244eea166b4, compilado sha256 fab7e8375ad8) =====
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
-- ===== 20261111230000_adn_doble_confirmacion (origen sha256 37234524eaf9, compilado sha256 28ab1a9d617d) =====
-- Doble confirmación del consentimiento de correo para quien se registra por QR. TODO APAGADO POR DEFECTO.
--  * Ajuste adn_doble_confirmacion (false). Apagado: el registro por QR se comporta como hasta ahora. Encendido: la casilla
--    de correo de una persona nueva no concede nada; se crea una solicitud y el consentimiento llega solo cuando la
--    persona confirma desde un enlace enviado a esa dirección. WhatsApp y SMS no tienen mecanismo de confirmación: con el
--    ajuste encendido no se conceden.
--  * Solicitud pendiente (adn_confirmaciones, solo servidor): estado por_enviar, pendiente, confirmada o caducada. Enlace
--    de un solo uso: el secreto (244 bits) solo existe al prepararlo, la base guarda su huella SHA-256, y caduca.
--  * Confirmar solo concede consentimiento si el canal está sin registro o en sin_dato: nunca deshace una baja (cancelado)
--    ni un «nunca», y queda anotado como evidencia de tipo confirmacion y en la auditoría.
--  * Cada solicitud preparada crea además un enlace de baja de un solo uso, para la cabecera List-Unsubscribe del correo.
-- NO se envía ningún correo desde aquí. Reversión: supabase/reversiones/20261111230000_adn_doble_confirmacion.down.sql

insert into public.plataforma_ajustes (clave, valor) values ('adn_doble_confirmacion', 'false'::jsonb) on conflict (clave) do nothing;

create table public.adn_confirmaciones (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null references public.iglesias (id) on delete cascade,
  miembro_id uuid not null,
  canal text not null check (canal = 'email'),
  destino text not null check (destino ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(destino) <= 254),
  idioma text check (idioma in ('es', 'en', 'fr', 'pt-BR')),
  estado text not null default 'por_enviar' check (estado in ('por_enviar', 'pendiente', 'confirmada', 'caducada')),
  token_hash text unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  expira_en timestamptz,
  confirmada_en timestamptz,
  constraint adn_confirmaciones_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id) on delete cascade,
  constraint adn_confirmaciones_forma check ((estado = 'por_enviar' and token_hash is null and expira_en is null) or (estado <> 'por_enviar' and token_hash is not null and expira_en is not null))
);
$cuerpo$;
end $tramo$;
select 'ok: tramo 8 de 15 aplicado' as resultado, (to_regclass('public.adn_confirmaciones') is not null) as comprobado;
