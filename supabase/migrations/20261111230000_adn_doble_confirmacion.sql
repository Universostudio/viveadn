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
create unique index adn_confirmaciones_activa_idx on public.adn_confirmaciones (miembro_id, canal) where estado in ('por_enviar', 'pendiente');
create index adn_confirmaciones_iglesia_idx on public.adn_confirmaciones (iglesia_id, estado);
alter table public.adn_confirmaciones enable row level security;
revoke all on public.adn_confirmaciones from public, anon, authenticated;
grant all on public.adn_confirmaciones to service_role;

-- La evidencia admite ahora la confirmación
alter table public.adn_consentimiento_evidencias drop constraint adn_consentimiento_evidencias_tipo_check;
alter table public.adn_consentimiento_evidencias add constraint adn_consentimiento_evidencias_tipo_check check (tipo in ('checkin', 'importacion', 'confirmacion'));
alter table public.adn_consentimiento_evidencias drop constraint adn_consentimiento_evidencias_forma;
alter table public.adn_consentimiento_evidencias add constraint adn_consentimiento_evidencias_forma check (
  (tipo = 'checkin' and finalidad is not null and texto_version is not null)
  or (tipo = 'importacion' and canal is not null and texto_original is not null)
  or (tipo = 'confirmacion' and canal is not null));

create or replace function private.adn_doble_confirmacion_activa() returns boolean
language sql stable set search_path to '' as $$
  select coalesce((select valor = 'true'::jsonb from public.plataforma_ajustes where clave = 'adn_doble_confirmacion'), false)
$$;
revoke execute on function private.adn_doble_confirmacion_activa() from public, anon, authenticated;
grant execute on function private.adn_doble_confirmacion_activa() to service_role;

-- Registro por QR: con la doble confirmación activa crea la solicitud en lugar de conceder el consentimiento
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text, p_texto_version text default null, p_idioma text default null, p_canales text[] default null)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
  v_ver text := nullif(btrim(coalesce(p_texto_version, '')), ''); v_hash text;
  v_canal text; v_hash_c text; v_doble boolean := private.adn_doble_confirmacion_activa(); v_aplica boolean;
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
    -- Con la doble confirmación activa, la casilla NO concede nada todavía: el consentimiento llega cuando la persona
    -- confirma desde el enlace que se le envía. Hoy solo el correo tiene ese mecanismo; WhatsApp y SMS quedan sin conceder.
    v_aplica := v_nuevo and v_hash_c is not null and not v_doble;
    insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, canal, finalidad, texto_version, idioma, texto_hash, evento_id, aplicado, origen)
      values (c.iglesia_id, v_miembro, 'checkin', v_canal, 'checkin_' || v_canal, case when v_hash_c is null then 'sin_version' else v_ver end,
              case when v_hash_c is null then null else p_idioma end, v_hash_c, c.evento_id, v_aplica, 'qr');
    if v_aplica then
      perform private.adn_escribir_consentimiento(c.iglesia_id, v_miembro, v_canal, 'suscrito', 'qr', null);
    elsif v_nuevo and v_hash_c is not null and v_doble and v_canal = 'email'
          and lower(btrim(p_email)) ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(btrim(p_email)) <= 254 then
      insert into public.adn_confirmaciones (iglesia_id, miembro_id, canal, destino, idioma)
        values (c.iglesia_id, v_miembro, 'email', lower(btrim(p_email)), p_idioma) on conflict do nothing;
    end if;
  end loop;

  return case when v_nuevo then 'ok_nuevo' else 'ok_existente' end;
end;
$$;

revoke execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]) to service_role;

-- Prepara un lote de solicitudes por enviar: genera el secreto de cada una (una sola vez), guarda su huella y crea el enlace
-- de baja que acompañará al correo. Con el ajuste apagado no devuelve nada. Solo el servidor.
create or replace function public.adn_confirmacion_preparar(p_max integer default 50, p_dias integer default 3)
returns table (id uuid, destino text, idioma text, nombre text, iglesia text, token text, baja_token text, expira_en timestamptz)
language plpgsql set search_path to '' as $$
declare r record; v_token text; v_baja text; v_exp timestamptz;
begin
  if p_max is null or p_max not between 1 and 500 or p_dias is null or p_dias not between 1 and 14 then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  if not private.adn_doble_confirmacion_activa() then return; end if;
  for r in
    select c.id as cid, c.iglesia_id, c.miembro_id, c.destino as cdestino, c.idioma as cidioma, m.nombre as mnombre, i.nombre as inombre
    from public.adn_confirmaciones c
    join public.miembros m on m.id = c.miembro_id and m.iglesia_id = c.iglesia_id
    join public.iglesias i on i.id = c.iglesia_id
    where c.estado = 'por_enviar' order by c.created_at limit p_max for update of c skip locked
  loop
    v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    v_baja := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    v_exp := now() + make_interval(days => p_dias);
    update public.adn_confirmaciones set estado = 'pendiente', token_hash = encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), expira_en = v_exp where adn_confirmaciones.id = r.cid;
    insert into public.adn_bajas_enlaces (iglesia_id, miembro_id, canal, token_hash, expira_en)
      values (r.iglesia_id, r.miembro_id, 'email', encode(sha256(convert_to(v_baja, 'UTF8')), 'hex'), v_exp + interval '365 days');
    id := r.cid; destino := r.cdestino; idioma := r.cidioma; nombre := r.mnombre; iglesia := r.inombre; token := v_token; baja_token := v_baja; expira_en := v_exp;
    return next;
  end loop;
end $$;
revoke all on function public.adn_confirmacion_preparar(integer, integer) from public, anon, authenticated;
grant execute on function public.adn_confirmacion_preparar(integer, integer) to service_role;

-- Si el envío falla, la solicitud vuelve a por_enviar (sin secreto) para reintentarla
create or replace function public.adn_confirmacion_fallida(p_id uuid) returns void
language sql set search_path to '' as $$
  update public.adn_confirmaciones set estado = 'por_enviar', token_hash = null, expira_en = null where id = p_id and estado = 'pendiente'
$$;
revoke all on function public.adn_confirmacion_fallida(uuid) from public, anon, authenticated;
grant execute on function public.adn_confirmacion_fallida(uuid) to service_role;

-- Consume el enlace de confirmación. Respuesta sin datos de la persona ni de la iglesia.
create or replace function public.adn_confirmacion_consumir(p_token text) returns jsonb
language plpgsql set search_path to '' as $$
declare c public.adn_confirmaciones; v_actual text; v_aplica boolean := false;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return jsonb_build_object('ok', false, 'motivo', 'invalido'); end if;
  select * into c from public.adn_confirmaciones where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') for update;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'invalido'); end if;
  if c.estado = 'confirmada' then return jsonb_build_object('ok', false, 'motivo', 'usado'); end if;
  if c.estado = 'caducada' or c.expira_en < now() then
    update public.adn_confirmaciones set estado = 'caducada' where id = c.id and estado = 'pendiente';
    return jsonb_build_object('ok', false, 'motivo', 'caducado');
  end if;
  update public.adn_confirmaciones set estado = 'confirmada', confirmada_en = now() where id = c.id;
  -- Solo concede si no hay registro o consta sin_dato: nunca deshace una baja ni un «nunca»
  select k.estado into v_actual from public.adn_consentimientos k where k.miembro_id = c.miembro_id and k.canal = c.canal;
  if v_actual is null or v_actual = 'sin_dato' then
    perform private.adn_escribir_consentimiento(c.iglesia_id, c.miembro_id, c.canal, 'suscrito', 'qr_confirmado', null);
    v_aplica := true;
  end if;
  insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, canal, aplicado, origen)
    values (c.iglesia_id, c.miembro_id, 'confirmacion', c.canal, v_aplica, 'qr_confirmado');
  return jsonb_build_object('ok', true, 'canal', c.canal);
end $$;
revoke all on function public.adn_confirmacion_consumir(text) from public, anon, authenticated;
grant execute on function public.adn_confirmacion_consumir(text) to service_role;
