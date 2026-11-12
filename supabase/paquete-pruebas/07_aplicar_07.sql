-- Vive ADN, paquete de aplicación 07 de 07. Aplicar en orden y detenerse en el primer error.
set search_path = public, extensions;

-- ===== migrations/20261111230000_adn_doble_confirmacion.sql (sha256 37234524eaf9) =====
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

-- ===== migrations/20261111240000_adn_purga_estado.sql (sha256 fba57547598a) =====
-- Estado de la purga programada, para vigilar que la tarea programada de borrado funciona.
--  * adn_purga_estado(p_horas) devuelve solo cifras (sin datos de personas ni de iglesias): cuántas iglesias están en borrado suave,
--    cuántas tienen el plazo vencido y esperan purga, cuántas horas lleva esperando la más atrasada y si ese retraso supera p_horas
--    (48 por defecto). Una purga sana deja las vencidas en cero a las pocas horas.
--  * Solo la ejecuta el servidor. Es de solo lectura: no purga nada. La purga sigue siendo la del ciclo de vida.
-- Reversión: supabase/reversiones/20261111240000_adn_purga_estado.down.sql
create or replace function public.adn_purga_estado(p_horas integer default 48)
returns jsonb language sql stable set search_path to '' as $$
  select jsonb_build_object(
    'en_borrado', count(*) filter (where adn_borrada_en is not null),
    'vencidas', count(*) filter (where adn_borrada_en is not null and borrado_programado_en <= now()),
    'horas_mas_atrasada', coalesce(floor(max(extract(epoch from now() - borrado_programado_en)) filter (where adn_borrada_en is not null and borrado_programado_en <= now()) / 3600), 0)::int,
    'atrasada', coalesce(bool_or(adn_borrada_en is not null and borrado_programado_en <= now() - make_interval(hours => greatest(coalesce(p_horas, 48), 0))), false))
  from public.iglesias
$$;
revoke all on function public.adn_purga_estado(integer) from public, anon, authenticated;
grant execute on function public.adn_purga_estado(integer) to service_role;

-- ===== migrations/20261111250000_adn_purgas_libro.sql (sha256 c0a0e32b9dad) =====
-- Libro externo de iglesias purgadas: la pieza de la base que lo hace posible.
-- El problema: restaurar una copia anterior a una purga devuelve los datos de una iglesia ya borrada, y la auditoría de la purga vive
-- en la misma base, así que se pierde con la restauración. El libro es una lista guardada FUERA de la base que dice qué iglesias se
-- purgaron y cuándo. Solo contiene identificadores y fechas: ningún dato de personas ni de iglesias.
--  * adn_purgas_desde(p_desde) exporta ese libro desde la auditoría: una fila por purga, con el identificador y la fecha. Con una fecha
--    devuelve solo lo posterior (o igual), para añadirlo al libro; sin fecha, todo. Es de solo lectura.
--  * adn_repurgar_registradas(p_ids, p_actor) se usa tras una restauración: toma los identificadores del libro y, de los que reaparecen en la
--    base restaurada, los vuelve a marcar como borrados con el plazo vencido. No borra nada por sí misma: la purga normal
--    (adn_iglesias_vencidas y adn_purgar_iglesia, desde la función de borde) las elimina por completo, con sus archivos y cuentas.
--    Las que ya no existen se ignoran. Devuelve los identificadores marcados.
--  * Solo las ejecuta el servidor.
-- Reversión: supabase/reversiones/20261111250000_adn_purgas_libro.down.sql
create or replace function public.adn_purgas_desde(p_desde timestamptz default null)
returns table (iglesia_ref uuid, purgada_en timestamptz) language sql stable set search_path to '' as $$
  select a.iglesia_ref, a.ocurrido_en
  from public.adn_ciclo_auditoria a
  where a.accion = 'purga' and (p_desde is null or a.ocurrido_en >= p_desde)
  order by a.ocurrido_en, a.id
$$;

create or replace function public.adn_repurgar_registradas(p_ids uuid[], p_actor uuid)
returns uuid[] language plpgsql set search_path to '' as $$
declare
  r record;
  marcadas uuid[] := '{}';
begin
  if p_ids is null or cardinality(p_ids) > 5000 then raise exception 'ADN_LISTA_INVALIDA'; end if;
  for r in select id from public.iglesias where id = any (p_ids) order by id for update loop
    update public.iglesias set
      adn_borrada_en = coalesce(adn_borrada_en, now()), adn_borrada_por = coalesce(adn_borrada_por, p_actor),
      etapa = 'suspendida', borrado_programado_en = now()
    where id = r.id;
    perform public.adn_auditar_ciclo(r.id, 'borrado_suave', p_actor, null, jsonb_build_object('origen', 'libro_externo'));
    marcadas := marcadas || r.id;
  end loop;
  return marcadas;
end $$;

revoke all on function public.adn_purgas_desde(timestamptz), public.adn_repurgar_registradas(uuid[], uuid) from public, anon, authenticated;
grant execute on function public.adn_purgas_desde(timestamptz), public.adn_repurgar_registradas(uuid[], uuid) to service_role;

-- ===== migrations/20261111260000_adn_exportacion_paginada.sql (sha256 6db9ef062dd7) =====
-- Exportación completa por páginas: para iglesias grandes, donde un único JSON con todo el paquete (adn_exportar_paquete) supera los
-- límites de tamaño y de memoria. adn_exportar_paquete NO se modifica y sigue valiendo para iglesias pequeñas y como reserva.
-- Reversión: supabase/reversiones/20261111260000_adn_exportacion_paginada.down.sql
--
--  * adn_exportar_plan(iglesia): el esqueleto del manifiesto, sin leer filas: por tabla, orden de carga, columnas, omitidas, clave
--    primaria y número de filas. Las tablas, su orden y sus columnas se calculan igual que en adn_exportar_paquete.
--  * adn_exportar_pagina(iglesia, tabla, formato, despues, limite): una página de una tabla, ordenada por su clave primaria y paginada
--    con un cursor de esa clave (nunca con desplazamientos, que se encarecen con cada página). Devuelve, según el formato:
--      'json' -> las filas como un texto JSON ('[...]'), tal como salen en la exportación, y el md5 de cada fila
--      'csv'  -> las filas como CSV sin cabecera (RFC 4180, CRLF)
--    El texto viaja como cadena para conservar exactamente la escala de los numéricos. El md5 de cada fila es el mismo que usa
--    adn_verificar_carga, así que el cliente calcula la huella de la tabla (md5 de los md5 ordenados) sin que la base la lea entera.
--  * Una tabla fuera de adn_tablas_exportables se rechaza: la lista cerrada impide pedir cualquier otra.
--  * Solo las ejecuta el servidor.
create or replace function public.adn_exportar_secretos()
returns text[] language sql immutable set search_path to '' as $$
  -- Columnas que nunca salen: secretos y marcas internas del borrado suave (la misma lista que adn_exportar_paquete)
  select array['token', 'token_hash', 'ip_hash', 'adn_borrada_en', 'adn_borrada_por', 'adn_estado_previo']
$$;

-- Tablas exportables con su filtro y su orden de carga: una tabla va después de las que referencia (las autorreferencias no cuentan)
create or replace function public.adn_exportar_orden()
returns table (o_nombre text, o_filtro text, o_nivel integer) language sql stable set search_path to '' as $$
  with recursive tb as (select x.nombre, x.filtro from public.adn_tablas_exportables() x),
  fk as (
    select co.relname::text collate "default" as origen, cd.relname::text collate "default" as destino
    from pg_constraint c
    join pg_class co on co.oid = c.conrelid join pg_class cd on cd.oid = c.confrelid
    where c.contype = 'f' and c.connamespace = 'public'::regnamespace and c.conrelid <> c.confrelid
  ),
  niv(nombre, n) as (
    select nombre, 0 from tb
    union
    select fk.origen, niv.n + 1 from niv join fk on fk.destino = niv.nombre
    where fk.origen in (select nombre from tb) and niv.n < 50
  )
  select t.nombre, t.filtro, max(niv.n)::integer
  from tb t join niv on niv.nombre = t.nombre
  group by t.nombre, t.filtro
  order by max(niv.n), t.nombre
$$;

create or replace function public.adn_exportar_plan(p_iglesia uuid)
returns jsonb language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
declare
  r record;
  cols jsonb; omitidas text[]; pk text[]; n bigint;
  tablas jsonb := '[]'::jsonb;
  total bigint := 0;
begin
  if not exists (select 1 from public.iglesias where id = p_iglesia) then
    raise exception 'La iglesia no existe';
  end if;
  for r in select * from public.adn_exportar_orden() loop
    select coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text = any (public.adn_exportar_secretos())), '{}'),
           coalesce(jsonb_agg(jsonb_build_object('nombre', a.attname, 'tipo', format_type(a.atttypid, a.atttypmod), 'obligatoria', a.attnotnull)
                              order by a.attnum) filter (where a.attname::text <> all (public.adn_exportar_secretos())), '[]')
      into omitidas, cols
      from pg_attribute a
      where a.attrelid = ('public.' || quote_ident(r.o_nombre))::regclass and a.attnum > 0 and not a.attisdropped;
    select array_agg(a.attname::text order by k.ord) into pk
      from pg_index i
      cross join lateral unnest(i.indkey::int2[]) with ordinality k(attnum, ord)
      join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
      where i.indrelid = ('public.' || quote_ident(r.o_nombre))::regclass and i.indisprimary;
    execute format('select count(*) from public.%I t where %s', r.o_nombre, r.o_filtro) into n using p_iglesia;
    total := total + n;
    tablas := tablas || jsonb_build_array(jsonb_build_object(
      'nombre', r.o_nombre, 'orden_carga', r.o_nivel, 'archivo_csv', 'csv/' || r.o_nombre || '.csv',
      'filas', n, 'columnas', cols, 'omitidas', to_jsonb(omitidas), 'clave', to_jsonb(coalesce(pk, '{}'))));
  end loop;
  return jsonb_build_object('formato', 'viveadn-exportacion-2', 'iglesia_id', p_iglesia, 'exportado_en', now(), 'total_filas', total, 'tablas', tablas);
end $$;

create or replace function public.adn_exportar_pagina(p_iglesia uuid, p_tabla text, p_formato text, p_despues jsonb default null, p_limite integer default 1000)
returns jsonb language plpgsql set search_path to '' set timezone to 'UTC' as $$
declare
  filtro text;
  nombres text[]; omitidas text[]; pk text[]; tipos text[];
  lim integer;
  condicion text := '';
  orden text; claves text;
  res record;
begin
  if p_formato is null or p_formato not in ('json', 'csv') then raise exception 'ADN_FORMATO_INVALIDO'; end if;
  select x.filtro into filtro from public.adn_tablas_exportables() x where x.nombre = p_tabla;
  if filtro is null then raise exception 'ADN_TABLA_NO_EXPORTABLE'; end if;
  if not exists (select 1 from public.iglesias where id = p_iglesia) then raise exception 'La iglesia no existe'; end if;
  lim := least(greatest(coalesce(p_limite, 1000), 1), 5000);

  select coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text <> all (public.adn_exportar_secretos())), '{}'),
         coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text = any (public.adn_exportar_secretos())), '{}')
    into nombres, omitidas
    from pg_attribute a
    where a.attrelid = ('public.' || quote_ident(p_tabla))::regclass and a.attnum > 0 and not a.attisdropped;
  select array_agg(a.attname::text order by k.ord), array_agg(format_type(a.atttypid, a.atttypmod) order by k.ord) into pk, tipos
    from pg_index i
    cross join lateral unnest(i.indkey::int2[]) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
    where i.indrelid = ('public.' || quote_ident(p_tabla))::regclass and i.indisprimary;
  if pk is null then raise exception 'ADN_SIN_CLAVE'; end if;

  orden := (select string_agg(format('t.%I', c), ', ' order by ord) from unnest(pk) with ordinality u(c, ord));
  claves := (select string_agg(format('t.%I::text', c), ', ' order by ord) from unnest(pk) with ordinality u(c, ord));
  if p_despues is not null then
    if jsonb_typeof(p_despues) <> 'array' or jsonb_array_length(p_despues) <> cardinality(pk)
       or exists (select 1 from jsonb_array_elements(p_despues) e where jsonb_typeof(e) <> 'string') then
      raise exception 'ADN_CURSOR_INVALIDO';
    end if;
    condicion := format(' and (%s) > (%s)', orden,
      (select string_agg(format('%L::%s', p_despues ->> (ord - 1)::integer, tipos[ord]), ', ' order by ord) from generate_series(1, cardinality(pk)) ord));
  end if;

  execute format($q$
    with pag as (
      select public.adn_fila_exportable(to_jsonb(t), $2) as f,
             to_jsonb(array[%s]) as clave,
             row_number() over (order by %s) as rn
      from public.%I t where %s %s
      order by %s
      limit $3 + 1
    )
    select count(*) filter (where rn <= $3) as n,
           bool_or(rn > $3) as hay_mas,
           case when $5 = 'json'
             then '[' || coalesce(string_agg(f::text, ',' order by rn) filter (where rn <= $3), '') || ']' end as json,
           case when $5 = 'csv'
             then coalesce(string_agg(
                    (select string_agg(public.adn_csv_campo(f -> c.n), ',' order by c.ord) from unnest($4::text[]) with ordinality c(n, ord)),
                    E'\r\n' order by rn) filter (where rn <= $3) || E'\r\n', '') end as csv,
           case when $5 = 'json' then coalesce(jsonb_agg(md5(f::text) order by rn) filter (where rn <= $3), '[]'::jsonb) end as hashes,
           (jsonb_agg(clave order by rn) filter (where rn <= $3)) -> -1 as ultima
    from pag
  $q$, claves, orden, p_tabla, filtro, condicion, orden)
    into res using p_iglesia, omitidas, lim, nombres, p_formato;

  return jsonb_strip_nulls(jsonb_build_object(
    'n', res.n, 'json', res.json, 'csv', res.csv, 'hashes', res.hashes,
    'siguiente', case when coalesce(res.hay_mas, false) then res.ultima end));
end $$;

revoke all on function
  public.adn_exportar_secretos(), public.adn_exportar_orden(), public.adn_exportar_plan(uuid), public.adn_exportar_pagina(uuid, text, text, jsonb, integer)
  from public, anon, authenticated;
grant execute on function
  public.adn_exportar_secretos(), public.adn_exportar_orden(), public.adn_exportar_plan(uuid), public.adn_exportar_pagina(uuid, text, text, jsonb, integer)
  to service_role;

-- ===== migrations/20261111270000_adn_autoservicio_datos.sql (sha256 099c92b1e67c) =====
-- Autoservicio del propietario de la iglesia: descargar todos sus datos y pedir la baja, sin pasar por la plataforma.
-- Reglas:
--  * Solo el propietario (rol con es_propietario, perfil activo) de esa iglesia. Se comprueba aquí, en la base, no solo en la función de borde.
--  * La baja NO borra nada: reutiliza el borrado suave que ya existe. La iglesia queda suspendida y se purga a los 30 días; hasta entonces
--    su propietario puede cancelar la baja. Una baja que abrió la plataforma no la puede cancelar la iglesia.
--  * Cada descarga y cada baja o cancelación queda en adn_datos_auditoria: quién, cuándo y qué. Sin datos de personas. Sin clave foránea
--    a iglesias a propósito, para que sobreviva a la purga, como adn_ciclo_auditoria. Solo se agrega: nada se edita ni se borra.
--  * Las descargas se limitan a 6 por hora y por iglesia, para que nadie convierta la exportación en un modo de cargar la base.
--  * Solo las ejecuta el servidor (función de borde `datos-iglesia`), que identifica a quien llama con su sesión.
-- Reversión: supabase/reversiones/20261111270000_adn_autoservicio_datos.down.sql
create table public.adn_datos_auditoria (
  id bigint generated always as identity primary key,
  iglesia_ref uuid not null,
  accion text not null check (accion in ('exportacion', 'baja_solicitada', 'baja_cancelada')),
  actor uuid not null,
  detalle jsonb not null default '{}'::jsonb,
  ocurrido_en timestamptz not null default now()
);
create index adn_datos_auditoria_iglesia_idx on public.adn_datos_auditoria (iglesia_ref, accion, ocurrido_en desc);
alter table public.adn_datos_auditoria enable row level security;  -- sin políticas: solo service_role
revoke all on public.adn_datos_auditoria from public, anon, authenticated;
revoke all on sequence public.adn_datos_auditoria_id_seq from public, anon, authenticated;
grant select, insert on public.adn_datos_auditoria to service_role;
grant usage, select on sequence public.adn_datos_auditoria_id_seq to service_role;

create or replace function public.adn_es_propietario(p_iglesia uuid, p_actor uuid)
returns boolean language sql stable set search_path to '' as $$
  select exists (
    select 1 from public.perfiles pf
    join public.roles r on r.iglesia_id = pf.iglesia_id and r.clave = pf.rol
    where pf.id = p_actor and pf.iglesia_id = p_iglesia and pf.activo and r.es_propietario
  )
$$;

-- Estado para la pantalla del propietario: la baja si la hay (cuándo se pidió, cuándo se purga, si la pidió la iglesia y se puede cancelar)
-- y cuántas descargas le quedan en esta hora
create or replace function public.adn_autoservicio_estado(p_iglesia uuid, p_actor uuid)
returns jsonb language plpgsql stable set search_path to '' as $$
declare
  v record;
  baja jsonb := null;
  propia boolean;
  usadas integer;
begin
  if not public.adn_es_propietario(p_iglesia, p_actor) then raise exception 'ADN_NO_PROPIETARIO'; end if;
  select nombre, slug, etapa, adn_borrada_en, adn_borrada_por, borrado_programado_en into v from public.iglesias where id = p_iglesia;
  if not found then raise exception 'ADN_NO_PROPIETARIO'; end if;
  if v.adn_borrada_en is not null then
    propia := exists (select 1 from public.adn_datos_auditoria a
      where a.iglesia_ref = p_iglesia and a.accion = 'baja_solicitada' and a.actor = v.adn_borrada_por and a.ocurrido_en = v.adn_borrada_en);
    baja := jsonb_build_object('solicitada_en', v.adn_borrada_en, 'purga_el', v.borrado_programado_en,
      'por_la_iglesia', propia, 'cancelable', propia and v.borrado_programado_en > now());
  end if;
  select count(*) into usadas from public.adn_datos_auditoria a
    where a.iglesia_ref = p_iglesia and a.accion = 'exportacion' and a.ocurrido_en > now() - interval '1 hour';
  return jsonb_build_object('nombre', v.nombre, 'slug', v.slug, 'etapa', v.etapa, 'baja', baja,
    'descargas_restantes', greatest(0, 6 - usadas), 'plazo_dias', 30);
end $$;

-- Anota una descarga completa (se llama una vez, al empezar) y aplica el límite de 6 por hora
create or replace function public.adn_autoservicio_exportar(p_iglesia uuid, p_actor uuid)
returns void language plpgsql set search_path to '' as $$
declare
  usadas integer;
begin
  if not public.adn_es_propietario(p_iglesia, p_actor) then raise exception 'ADN_NO_PROPIETARIO'; end if;
  perform pg_advisory_xact_lock(hashtextextended('adn_descarga_' || p_iglesia::text, 0));
  select count(*) into usadas from public.adn_datos_auditoria a
    where a.iglesia_ref = p_iglesia and a.accion = 'exportacion' and a.ocurrido_en > now() - interval '1 hour';
  if usadas >= 6 then raise exception 'ADN_LIMITE_DESCARGAS'; end if;
  insert into public.adn_datos_auditoria (iglesia_ref, accion, actor, detalle) values (p_iglesia, 'exportacion', p_actor, '{"paginado": true}'::jsonb);
end $$;

-- Pide la baja: borrado suave con el actor y el motivo. Devuelve la fecha de la purga (30 días). No borra nada ahora.
create or replace function public.adn_autoservicio_baja(p_iglesia uuid, p_actor uuid, p_motivo text default null)
returns timestamptz language plpgsql set search_path to '' as $$
declare
  purga timestamptz;
begin
  if not public.adn_es_propietario(p_iglesia, p_actor) then raise exception 'ADN_NO_PROPIETARIO'; end if;
  purga := public.adn_borrar_suave(p_iglesia, p_actor, 'autoservicio: ' || left(coalesce(p_motivo, ''), 480));
  -- La misma transacción fija la misma fecha en el borrado y en esta anotación: así se reconoce después que la baja la pidió la iglesia
  insert into public.adn_datos_auditoria (iglesia_ref, accion, actor, detalle) values (p_iglesia, 'baja_solicitada', p_actor, jsonb_build_object('purga_el', purga));
  return purga;
end $$;

-- Cancela una baja que pidió la propia iglesia y que aún está dentro del plazo. Devuelve la etapa a la que vuelve.
create or replace function public.adn_autoservicio_cancelar_baja(p_iglesia uuid, p_actor uuid, p_motivo text default null)
returns text language plpgsql set search_path to '' as $$
declare
  v record;
  etapa text;
begin
  if not public.adn_es_propietario(p_iglesia, p_actor) then raise exception 'ADN_NO_PROPIETARIO'; end if;
  select adn_borrada_en, adn_borrada_por into v from public.iglesias where id = p_iglesia for update;
  if v.adn_borrada_en is null then raise exception 'ADN_NO_BORRADA'; end if;
  if not exists (select 1 from public.adn_datos_auditoria a
      where a.iglesia_ref = p_iglesia and a.accion = 'baja_solicitada' and a.actor = v.adn_borrada_por and a.ocurrido_en = v.adn_borrada_en) then
    raise exception 'ADN_BAJA_DE_PLATAFORMA';
  end if;
  etapa := public.adn_recuperar_iglesia(p_iglesia, p_actor, 'autoservicio: ' || left(coalesce(p_motivo, ''), 480));
  insert into public.adn_datos_auditoria (iglesia_ref, accion, actor, detalle) values (p_iglesia, 'baja_cancelada', p_actor, jsonb_build_object('etapa', etapa));
  return etapa;
end $$;

revoke all on function public.adn_es_propietario(uuid, uuid), public.adn_autoservicio_estado(uuid, uuid), public.adn_autoservicio_exportar(uuid, uuid),
  public.adn_autoservicio_baja(uuid, uuid, text), public.adn_autoservicio_cancelar_baja(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.adn_es_propietario(uuid, uuid), public.adn_autoservicio_estado(uuid, uuid), public.adn_autoservicio_exportar(uuid, uuid),
  public.adn_autoservicio_baja(uuid, uuid, text), public.adn_autoservicio_cancelar_baja(uuid, uuid, text) to service_role;

-- ===== migrations/20261111280000_adn_envios_topes.sql (sha256 5aff7c7b9cb3) =====
-- Topes de envío de correo (docs/COSTE-ENVIO.md, aprobados por Gerencia). Un contador por día en la base: antes de enviar, la función
-- de borde reserva un envío; si algún tope está alcanzado, no se envía y se anota. Los topes los pasa quien llama (variables de la
-- función, con valores por defecto del plan gratuito), la base solo cuenta y decide de forma atómica.
--  * adn_envios_dia: una fila por día (UTC), tipo de correo e iglesia (la iglesia vacía usa un identificador de ceros). Solo números.
--  * adn_envio_reservar(tipo, iglesia, tope_iglesia, tope_tipo, tope_global): devuelve 'ok' y suma uno, o el primer tope alcanzado:
--    'tope_global', 'tope_tipo' o 'tope_iglesia'. Se comprueba en ese orden para que, con el plan gratuito, el fallo sea limpio y no a medias.
--  * adn_envio_liberar(tipo, iglesia): devuelve la reserva si el proveedor no aceptó el correo (no gasta cupo).
--  * Solo las ejecuta el servidor.
-- Reversión: supabase/reversiones/20261111280000_adn_envios_topes.down.sql
create table public.adn_envios_dia (
  dia date not null,
  tipo text not null check (tipo in ('purga', 'baja', 'confirmacion')),
  iglesia_ref uuid not null default '00000000-0000-0000-0000-000000000000',
  n integer not null check (n >= 0),
  primary key (dia, tipo, iglesia_ref)
);
alter table public.adn_envios_dia enable row level security;  -- sin políticas: solo service_role
revoke all on public.adn_envios_dia from public, anon, authenticated;
grant select, insert, update on public.adn_envios_dia to service_role;

create or replace function public.adn_envio_reservar(p_tipo text, p_iglesia uuid, p_tope_iglesia integer, p_tope_tipo integer, p_tope_global integer)
returns text language plpgsql set search_path to '' as $$
declare
  hoy date := (now() at time zone 'utc')::date;
  clave uuid := coalesce(p_iglesia, '00000000-0000-0000-0000-000000000000');
  global_n integer;
  tipo_n integer;
  iglesia_n integer;
begin
  if p_tipo is null or p_tipo not in ('purga', 'baja', 'confirmacion') then raise exception 'ADN_TIPO_INVALIDO'; end if;
  if p_tope_global is null or p_tope_global < 0 or p_tope_tipo < 0 or p_tope_iglesia < 0 then raise exception 'ADN_TOPE_INVALIDO'; end if;
  perform pg_advisory_xact_lock(hashtextextended('adn_envios_dia', 0));
  select coalesce(sum(n), 0) into global_n from public.adn_envios_dia where dia = hoy;
  if global_n >= p_tope_global then return 'tope_global'; end if;
  select coalesce(sum(n), 0) into tipo_n from public.adn_envios_dia where dia = hoy and tipo = p_tipo;
  if p_tope_tipo is not null and tipo_n >= p_tope_tipo then return 'tope_tipo'; end if;
  select coalesce(n, 0) into iglesia_n from public.adn_envios_dia where dia = hoy and tipo = p_tipo and iglesia_ref = clave;
  iglesia_n := coalesce(iglesia_n, 0);
  if p_tope_iglesia is not null and p_iglesia is not null and iglesia_n >= p_tope_iglesia then return 'tope_iglesia'; end if;
  insert into public.adn_envios_dia (dia, tipo, iglesia_ref, n) values (hoy, p_tipo, clave, 1)
    on conflict (dia, tipo, iglesia_ref) do update set n = public.adn_envios_dia.n + 1;
  return 'ok';
end $$;

create or replace function public.adn_envio_liberar(p_tipo text, p_iglesia uuid)
returns void language sql set search_path to '' as $$
  update public.adn_envios_dia set n = n - 1
  where dia = (now() at time zone 'utc')::date and tipo = p_tipo
    and iglesia_ref = coalesce(p_iglesia, '00000000-0000-0000-0000-000000000000') and n > 0
$$;

revoke all on function public.adn_envio_reservar(text, uuid, integer, integer, integer), public.adn_envio_liberar(text, uuid) from public, anon, authenticated;
grant execute on function public.adn_envio_reservar(text, uuid, integer, integer, integer), public.adn_envio_liberar(text, uuid) to service_role;
