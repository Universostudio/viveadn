-- Evidencia del consentimiento: qué aceptó una persona, con qué texto y cuándo.
--  * Registro por QR: cada alta o reconocimiento deja una fila con la versión del texto aceptado (y su huella), el idioma,
--    el evento y la fecha. Los textos viven en adn_consentimiento_textos, versionados e inmutables: cambiar una palabra
--    obliga a crear una versión nueva.
--  * Importación: junto al estado que se aplica se guarda el valor original del archivo (por ejemplo, el de la columna
--    «Estado de suscriptor por email»), cuál fue el estado resultante y si cambió el consentimiento de la persona.
--  * Esto es solo evidencia. NO cambia a quién se le envía: eso lo siguen decidiendo adn_consentimientos y Comunicación.
--    Si el texto del registro por QR basta como consentimiento de algún canal es una decisión jurídica pendiente.
-- Reversión: supabase/reversiones/20261111210000_adn_consentimiento_evidencia.down.sql

-- Textos que se muestran al pedir el consentimiento. Una versión no se edita ni se borra: se crea otra.
create table public.adn_consentimiento_textos (
  finalidad text not null check (finalidad ~ '^[a-z0-9_]{1,30}$'),
  version text not null check (version ~ '^[a-z0-9._-]{1,20}$'),
  idioma text not null check (idioma in ('es', 'en', 'fr', 'pt-BR')),
  texto text not null check (char_length(texto) between 1 and 2000),
  texto_hash text not null check (texto_hash = encode(sha256(convert_to(texto, 'UTF8')), 'hex')),
  created_at timestamptz not null default now(),
  primary key (finalidad, version, idioma)
);
alter table public.adn_consentimiento_textos enable row level security;
create policy adn_consentimiento_textos_ver on public.adn_consentimiento_textos for select to authenticated using (true);
revoke all on public.adn_consentimiento_textos from public, anon, authenticated;
grant select on public.adn_consentimiento_textos to authenticated;
grant all on public.adn_consentimiento_textos to service_role;
create or replace function private.trg_consentimiento_inmutable() returns trigger language plpgsql set search_path to '' as $$
begin
  raise exception 'ADN_REGISTRO_INMUTABLE';
end $$;
create trigger adn_consentimiento_textos_inmutable before update or delete on public.adn_consentimiento_textos
  for each row execute function private.trg_consentimiento_inmutable();

-- El texto del registro por QR tal como está en la web (src/i18n/locales, clave checkin.consentimiento), versión v1.
-- scripts/comprobar-textos-consentimiento.mts falla si la web cambia el texto sin crear una versión nueva.
insert into public.adn_consentimiento_textos (finalidad, version, idioma, texto, texto_hash) values
  ('checkin', 'v1', 'es', 'Acepto que {iglesia} guarde estos datos para contactarme y acompañarme tras mi visita.', encode(sha256(convert_to('Acepto que {iglesia} guarde estos datos para contactarme y acompañarme tras mi visita.', 'UTF8')), 'hex')),
  ('checkin', 'v1', 'en', 'I agree that {iglesia} stores this information to contact me and follow up after my visit.', encode(sha256(convert_to('I agree that {iglesia} stores this information to contact me and follow up after my visit.', 'UTF8')), 'hex')),
  ('checkin', 'v1', 'fr', 'J''accepte que {iglesia} conserve ces données pour me contacter et m''accompagner après ma visite.', encode(sha256(convert_to('J''accepte que {iglesia} conserve ces données pour me contacter et m''accompagner après ma visite.', 'UTF8')), 'hex')),
  ('checkin', 'v1', 'pt-BR', 'Aceito que {iglesia} guarde estes dados para entrar em contato comigo e me acompanhar após a minha visita.', encode(sha256(convert_to('Aceito que {iglesia} guarde estes dados para entrar em contato comigo e me acompanhar após a minha visita.', 'UTF8')), 'hex'));

-- Evidencias: solo altas. Las escriben las funciones, nunca la web.
create table public.adn_consentimiento_evidencias (
  id bigint generated always as identity primary key,
  iglesia_id uuid not null references public.iglesias (id) on delete cascade,
  miembro_id uuid not null,
  tipo text not null check (tipo in ('checkin', 'importacion')),
  canal text check (canal in ('email', 'sms', 'whatsapp')),
  finalidad text check (finalidad ~ '^[a-z0-9_]{1,30}$'),
  texto_version text check (texto_version ~ '^[a-z0-9._-]{1,20}$'),
  idioma text check (idioma in ('es', 'en', 'fr', 'pt-BR')),
  texto_hash text check (texto_hash ~ '^[0-9a-f]{64}$'),
  evento_id uuid,
  texto_original text check (char_length(texto_original) <= 60),
  estado_importado text check (estado_importado in ('suscrito', 'nunca', 'cancelado', 'sin_dato')),
  aplicado boolean,
  origen text not null check (origen ~ '^[a-z0-9_-]{1,30}$'),
  created_at timestamptz not null default now(),
  constraint adn_consentimiento_evidencias_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id) on delete cascade,
  constraint adn_consentimiento_evidencias_forma check (
    (tipo = 'checkin' and finalidad is not null and texto_version is not null and canal is null)
    or (tipo = 'importacion' and canal is not null and texto_original is not null))
);
create index adn_consentimiento_evidencias_miembro_idx on public.adn_consentimiento_evidencias (iglesia_id, miembro_id, created_at desc);
alter table public.adn_consentimiento_evidencias enable row level security;
create policy adn_consentimiento_evidencias_ver on public.adn_consentimiento_evidencias for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
         and ((select private.tiene_permiso('comunicacion.ver')) or (select private.tiene_permiso('comunicacion.enviar'))));
revoke all on public.adn_consentimiento_evidencias from public, anon, authenticated;
grant select on public.adn_consentimiento_evidencias to authenticated;
grant all on public.adn_consentimiento_evidencias to service_role;
create trigger adn_consentimiento_evidencias_inmutable before update on public.adn_consentimiento_evidencias
  for each row execute function private.trg_consentimiento_inmutable();

-- Registro por QR: dos parámetros opcionales (versión del texto aceptado e idioma) y la anotación de la evidencia
drop function public.registrar_checkin(text, text, text, text, text, text);
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text, p_texto_version text default null, p_idioma text default null)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
  v_ver text := nullif(btrim(coalesce(p_texto_version, '')), ''); v_hash text;
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

  return case when v_nuevo then 'ok_nuevo' else 'ok_existente' end;
end;
$$;

revoke execute on function public.registrar_checkin(text, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.registrar_checkin(text, text, text, text, text, text, text, text) to service_role;

-- Importación: guarda el valor original que traía el archivo para cada canal, aunque no se pueda interpretar
drop function private.adn_aplicar_consentimiento(uuid, jsonb, text, text);
create or replace function private.adn_aplicar_consentimiento(p_miembro uuid, p_consent jsonb, p_origen text, p_modo text, p_original jsonb default null)
returns void language plpgsql security definer set search_path to '' as $$
declare
  ig uuid := private.get_iglesia_id();
  v_canal text; v_nuevo text; v_actual text; v_despues text; v_orig text;
  rango constant jsonb := '{"suscrito": 0, "sin_dato": 1, "nunca": 2, "cancelado": 3}';
begin
  if ig is null or p_miembro is null then return; end if;
  if jsonb_typeof(p_consent) is distinct from 'object' and jsonb_typeof(p_original) is distinct from 'object' then return; end if;
  if not (select private.tiene_permiso('miembros.importar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if not exists (select 1 from public.miembros m where m.id = p_miembro and m.iglesia_id = ig) then return; end if;
  foreach v_canal in array array['email', 'sms', 'whatsapp'] loop
    v_nuevo := case when jsonb_typeof(p_consent) = 'object' then p_consent ->> v_canal end;
    if v_nuevo is not null and v_nuevo not in ('suscrito', 'nunca', 'cancelado') then v_nuevo := null; end if;
    select k.estado into v_actual from public.adn_consentimientos k where k.miembro_id = p_miembro and k.canal = v_canal;
    if v_nuevo is not null then
      if v_actual is null then
        -- Sin registro: una persona nueva se guarda como venga; una existente solo si el estado restringe
        if p_modo = 'nuevo' or v_nuevo in ('nunca', 'cancelado') then
          perform private.adn_escribir_consentimiento(ig, p_miembro, v_canal, v_nuevo, p_origen, (select auth.uid()));
        end if;
      elsif (rango ->> v_nuevo)::int > (rango ->> v_actual)::int then
        perform private.adn_escribir_consentimiento(ig, p_miembro, v_canal, v_nuevo, p_origen, (select auth.uid()));
      end if;
    end if;
    -- Evidencia: el texto tal como venía en el archivo (sin saltos, caracteres de control ni espacios repetidos, hasta 60 caracteres)
    v_orig := case when jsonb_typeof(p_original) = 'object' then left(btrim(regexp_replace(coalesce(p_original ->> v_canal, ''), '[[:cntrl:][:space:]]+', ' ', 'g')), 60) end;
    if v_orig is not null and v_orig <> '' then
      select k.estado into v_despues from public.adn_consentimientos k where k.miembro_id = p_miembro and k.canal = v_canal;
      insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, canal, texto_original, estado_importado, aplicado, origen)
      values (ig, p_miembro, 'importacion', v_canal, v_orig, v_nuevo, v_despues is distinct from v_actual, p_origen);
    end if;
  end loop;
end $$;
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
