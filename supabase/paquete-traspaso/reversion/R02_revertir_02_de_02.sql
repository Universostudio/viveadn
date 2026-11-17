-- Vive ADN, REVERSIÓN del traspaso, archivo 2 de 2. Solo si Gerencia lo ordena. Aplicar en orden y detenerse en el primer error. Deja el real como estaba antes del traspaso (salvo los datos que se hayan creado después).
set search_path = public, extensions;

-- ===== reversión de 20261111200000_adn_consentimiento_auditoria =====
-- Reversion de 20261111200000_adn_consentimiento_auditoria.sql. No es una migracion: se ejecuta a mano, solo si Gerencia
-- lo ordena, y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
-- Borra la auditoria de consentimientos y los enlaces de baja (tablas y filas) y devuelve las funciones de consentimiento
-- a su definicion anterior. NO borra adn_consentimientos: los consentimientos se conservan.

begin;
drop function if exists public.adn_registrar_consentimiento(uuid, text, text, text);
drop function if exists private.adn_registrar_consentimiento(uuid, text, text, text);
drop function if exists public.adn_baja_consumir(text);
drop function if exists public.adn_baja_crear_enlace(uuid, text, integer);
create or replace function private.adn_aplicar_consentimiento(p_miembro uuid, p_consent jsonb, p_origen text, p_modo text)
returns void language plpgsql security definer set search_path to '' as $$
declare
  ig uuid := private.get_iglesia_id();
  v_canal text; v_nuevo text; v_actual text;
  rango constant jsonb := '{"suscrito": 0, "sin_dato": 1, "nunca": 2, "cancelado": 3}';
begin
  if ig is null or p_miembro is null or jsonb_typeof(p_consent) is distinct from 'object' then return; end if;
  if not (select private.tiene_permiso('miembros.importar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if not exists (select 1 from public.miembros m where m.id = p_miembro and m.iglesia_id = ig) then return; end if;
  foreach v_canal in array array['email', 'sms', 'whatsapp'] loop
    v_nuevo := p_consent ->> v_canal;
    continue when v_nuevo is null or v_nuevo not in ('suscrito', 'nunca', 'cancelado');
    select k.estado into v_actual from public.adn_consentimientos k where k.miembro_id = p_miembro and k.canal = v_canal;
    if v_actual is null then
      -- Sin registro: una persona nueva se guarda como venga; una existente solo si el estado restringe
      if p_modo = 'nuevo' or v_nuevo in ('nunca', 'cancelado') then
        insert into public.adn_consentimientos (iglesia_id, miembro_id, canal, estado, origen) values (ig, p_miembro, v_canal, v_nuevo, p_origen);
      end if;
    elsif (rango ->> v_nuevo)::int > (rango ->> v_actual)::int then
      update public.adn_consentimientos set estado = v_nuevo, origen = p_origen, actualizado_en = now()
       where miembro_id = p_miembro and canal = v_canal;
    end if;
  end loop;
end $$;

create or replace function private.adn_registrar_consentimiento(p_miembro uuid, p_canal text, p_estado text)
returns void language plpgsql security definer set search_path to '' as $$
declare ig uuid := private.get_iglesia_id();
begin
  if ig is null or not (select private.tiene_permiso('miembros.editar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_canal not in ('email', 'sms', 'whatsapp') or p_estado not in ('suscrito', 'nunca', 'cancelado', 'sin_dato') then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  if not exists (select 1 from public.miembros m where m.id = p_miembro and m.iglesia_id = ig) then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  insert into public.adn_consentimientos (iglesia_id, miembro_id, canal, estado, origen) values (ig, p_miembro, p_canal, p_estado, 'manual')
  on conflict (miembro_id, canal) do update set estado = excluded.estado, origen = 'manual', actualizado_en = now();
end $$;
revoke execute on function private.adn_registrar_consentimiento(uuid, text, text) from public, anon;
grant execute on function private.adn_registrar_consentimiento(uuid, text, text) to authenticated, service_role;
create or replace function public.adn_registrar_consentimiento(p_miembro uuid, p_canal text, p_estado text)
returns void language sql set search_path to '' as $$ select private.adn_registrar_consentimiento(p_miembro, p_canal, p_estado) $$;
revoke all on function public.adn_registrar_consentimiento(uuid, text, text) from public, anon;
grant execute on function public.adn_registrar_consentimiento(uuid, text, text) to authenticated, service_role;
drop function if exists private.adn_escribir_consentimiento(uuid, uuid, text, text, text, uuid);
drop table if exists public.adn_bajas_enlaces;
drop table if exists public.adn_consentimiento_auditoria;
drop function if exists private.trg_consentimiento_auditoria_inmutable();
commit;

-- ===== reversión de 20261111190000_adn_consentimiento =====
-- Reversion de 20261111190000_adn_consentimiento.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena,
-- y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
-- Borra la tabla de consentimientos con sus filas y devuelve las cuatro funciones a su definicion anterior.
-- Los destinatarios omitidos por falta de consentimiento pasan a constar como 'sin_destino' (del buzon de pruebas).

begin;
create or replace function private.adn_destinatarios(p_iglesia uuid, p_canal text, p_segmento text)
returns table (miembro_id uuid, nombre text, dia text, destino text, motivo text)
language sql stable security definer set search_path to '' as $$
  with dest as (
    select m.id, m.nombre, m.activo, m.created_at, m.nivel_compromiso, m.casa_oracion_id,
      case when p_canal = 'email'
             then case when lower(btrim(m.email)) ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(btrim(m.email)) <= 254 then lower(btrim(m.email)) end
           else case when public.adn_telefono_canonico(m.telefono) ~ '^\+?[0-9]{7,15}$' and public.adn_telefono_canonico(m.telefono) !~ '^\+?(.)\1+$'
                     then public.adn_telefono_canonico(m.telefono) end
      end as destino
    from public.miembros m where m.iglesia_id = p_iglesia
  ), de_baja as (
    select d.id, d.destino from dest d
    where exists (select 1 from public.adn_comunicacion_bajas x where x.iglesia_id = p_iglesia and x.miembro_id = d.id and x.canal = p_canal)
  ), base as (
    select d.id, d.nombre, nullif(btrim(coalesce(c.dia_reunion, '')), '') as dia, d.destino
    from dest d
    left join public.casas_oracion c on c.id = d.casa_oracion_id and c.iglesia_id = p_iglesia
    where d.activo
      and case p_segmento
            when 'todos' then true
            when 'nuevos' then d.created_at >= now() - interval '30 days'
            when 'lideres' then d.nivel_compromiso in ('lider', 'multiplicador')
            when 'consolidacion' then exists (select 1 from public.consolidaciones k where k.miembro_id = d.id and k.iglesia_id = p_iglesia and not k.completado)
            else false end
  ), previo as (
    select b.*, case when b.destino is null then 'sin_destino'
                     when exists (select 1 from de_baja x where x.id = b.id or x.destino = b.destino) then 'baja'
                end as motivo_a
    from base b
  ), numerado as (
    select p.*, case when p.motivo_a is null then row_number() over (partition by p.destino order by p.id) end as rn from previo p
  )
  select n.id, n.nombre, n.dia, n.destino, coalesce(n.motivo_a, case when n.rn > 1 then 'repetido' end) from numerado n
$$;

create or replace function private.adn_vista_previa_envio(p_canal text, p_segmento text)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare ig uuid := private.get_iglesia_id(); r jsonb;
begin
  if ig is null or not ((select private.tiene_permiso('comunicacion.enviar')) and (select private.tiene_permiso('miembros.ver'))) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_canal not in ('email', 'whatsapp') or p_segmento not in ('todos', 'nuevos', 'lideres', 'consolidacion') then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  select jsonb_build_object('total', count(*), 'recibiran', count(*) filter (where motivo is null),
    'sin_destino', count(*) filter (where motivo = 'sin_destino'), 'baja', count(*) filter (where motivo = 'baja'), 'repetido', count(*) filter (where motivo = 'repetido'))
  into r from private.adn_destinatarios(ig, p_canal, p_segmento);
  return r;
end $$;


create or replace function private.adn_enviar_mensaje(p_clave uuid, p_canal text, p_segmento text, p_asunto text, p_texto text, p_dia text default '')
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  ig uuid := private.get_iglesia_id();
  nombre_ig text;
  texto text := btrim(coalesce(p_texto, ''));
  asunto text := nullif(btrim(coalesce(p_asunto, '')), '');
  existente public.adn_mensajes;
  id_msg uuid;
  n_total int; n_env int; n_sin int; n_baja int; n_rep int;
begin
  if ig is null or not ((select private.tiene_permiso('comunicacion.enviar')) and (select private.tiene_permiso('miembros.ver'))) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_clave is null or p_canal not in ('email', 'whatsapp') or p_segmento not in ('todos', 'nuevos', 'lideres', 'consolidacion') then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  if char_length(texto) not between 1 and 4096 then raise exception 'ADN_TEXTO_INVALIDO'; end if;
  if p_canal = 'email' and (asunto is null or char_length(asunto) > 150) then raise exception 'ADN_ASUNTO_INVALIDO'; end if;
  if p_canal <> 'email' then asunto := null; end if;

  -- Repetir la misma peticion devuelve el envio ya hecho
  select * into existente from public.adn_mensajes where iglesia_id = ig and clave = p_clave;
  if found then
    return jsonb_build_object('mensaje_id', existente.id, 'total', existente.total, 'enviados', existente.enviados, 'omitidos', existente.omitidos,
                              'proveedor', existente.proveedor, 'repetido', true);
  end if;
  -- Tope diario por iglesia, contra el abuso y los errores de pulsacion
  if (select count(*) from public.adn_mensajes where iglesia_id = ig and created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') >= 20 then
    raise exception 'ADN_LIMITE_DIARIO';
  end if;
  select count(*) into n_total from private.adn_destinatarios(ig, p_canal, p_segmento);
  if n_total > 2000 then raise exception 'ADN_DEMASIADOS_DESTINATARIOS'; end if;
  select nombre into nombre_ig from public.iglesias where id = ig;

  insert into public.adn_mensajes (iglesia_id, clave, canal, segmento, asunto, texto, estado, total, enviados, omitidos)
  values (ig, p_clave, p_canal, p_segmento, asunto, texto, 'sin_destinatarios', 0, 0, 0)
  returning id into id_msg;

  -- Variables de la plantilla: {{nombre}}, {{iglesia}} y {{dia}} (el de su casa de oracion o, si no tiene, el que se pase)
  insert into public.adn_mensaje_destinatarios (iglesia_id, mensaje_id, miembro_id, destino, texto_final, estado, motivo, referencia, enviado_en)
  select ig, id_msg, d.miembro_id,
         case when d.motivo is null then d.destino end,
         case when d.motivo is null then replace(replace(replace(texto, '{{nombre}}', d.nombre), '{{iglesia}}', nombre_ig), '{{dia}}', coalesce(d.dia, nullif(btrim(coalesce(p_dia, '')), ''), '')) end,
         case when d.motivo is null then 'enviado' else 'omitido' end, d.motivo,
         case when d.motivo is null then 'sumidero:' || gen_random_uuid()::text end,
         case when d.motivo is null then now() end
  from private.adn_destinatarios(ig, p_canal, p_segmento) d;

  select count(*) filter (where estado = 'enviado'), count(*) filter (where motivo = 'sin_destino'), count(*) filter (where motivo = 'baja'), count(*) filter (where motivo = 'repetido')
    into n_env, n_sin, n_baja, n_rep
    from public.adn_mensaje_destinatarios where iglesia_id = ig and mensaje_id = id_msg;
  update public.adn_mensajes set total = n_env + n_sin + n_baja + n_rep, enviados = n_env, omitidos = n_sin + n_baja + n_rep,
         estado = case when n_env > 0 then 'enviado' else 'sin_destinatarios' end
   where id = id_msg;
  return jsonb_build_object('mensaje_id', id_msg, 'total', n_env + n_sin + n_baja + n_rep, 'enviados', n_env,
                            'omitidos', jsonb_build_object('sin_destino', n_sin, 'baja', n_baja, 'repetido', n_rep),
                            'proveedor', 'sumidero', 'repetido', false);
end $$;


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
        n_dup_correo := n_dup_correo + 1; continue;
      end if;
    elsif array_length(telefonos, 1) > 0 then
      if telefonos && vistos_tel
         or exists (select 1 from public.miembros m where public.adn_telefono_canonico(m.telefono) = any (telefonos))
         or exists (select 1 from public.adn_miembro_contactos x where x.tipo = 'telefono' and public.adn_telefono_canonico(x.valor) = any (telefonos)) then
        n_dup_tel := n_dup_tel + 1; continue;
      end if;
    else
      clave_nombre := lower(regexp_replace(btrim(nombre || ' ' || apellido), '\s+', ' ', 'g'));
      if clave_nombre = any (vistos_nombre)
         or exists (select 1 from public.miembros m where lower(regexp_replace(btrim(m.nombre || ' ' || m.apellido), '\s+', ' ', 'g')) = clave_nombre) then
        n_dup_nombre := n_dup_nombre + 1; continue;
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


update public.adn_mensaje_destinatarios set motivo = 'sin_destino' where motivo = 'sin_consentimiento';
alter table public.adn_mensaje_destinatarios drop constraint adn_mensaje_destinatarios_motivo_check;
alter table public.adn_mensaje_destinatarios add constraint adn_mensaje_destinatarios_motivo_check
  check (motivo in ('sin_destino', 'baja', 'repetido'));
drop function if exists public.adn_registrar_consentimiento(uuid, text, text);
drop function if exists private.adn_registrar_consentimiento(uuid, text, text);
drop function if exists private.adn_miembro_existente(text[], text[], text);
drop function if exists private.adn_aplicar_consentimiento(uuid, jsonb, text, text);
drop table if exists public.adn_consentimientos;
commit;

-- ===== reversión de 20261111180000_adn_descargas_informe =====
-- Reversion de 20261111180000_adn_descargas_informe.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena,
-- y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
-- Borra el registro de descargas (la tabla y sus filas) y devuelve adn_informe_miembros a su definicion anterior.

begin;
create or replace function public.adn_informe_miembros()
returns table (crm_id text, nombre text, apellido text, email text, telefono text, fecha_nacimiento date, genero text, casa text,
               nivel_compromiso text, bautizado boolean, fecha_conversion date, activo boolean, registrado date)
language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
begin
  if not (select private.tiene_permiso('miembros.exportar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  return query
  select m.crm_id, m.nombre, m.apellido, m.email, m.telefono, m.fecha_nacimiento, m.genero, h.nombre,
         m.nivel_compromiso, coalesce(m.bautizado, false), m.fecha_conversion, coalesce(m.activo, false), m.created_at::date
  from public.miembros m left join public.casas_oracion h on h.id = m.casa_oracion_id and h.iglesia_id = m.iglesia_id
  order by m.crm_id;
end $$;
drop function if exists private.adn_registrar_descarga(text, integer);
drop table if exists public.adn_informe_descargas;
drop function if exists private.trg_descarga_inmutable();
commit;

-- ===== reversión de 20261111170000_adn_panel_inicio =====
-- Reversion de 20261111170000_adn_panel_inicio.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena.
-- Solo borra una funcion de lectura: no toca ninguna tabla ni ningun dato.

begin;
drop function if exists public.adn_panel_inicio(date);
commit;

-- ===== reversión de 20261111160000_adn_comunicacion =====
-- Reversion de 20261111160000_adn_comunicacion.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena,
-- y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
--
-- Efectos sobre datos, a tener en cuenta antes de ejecutarla:
--  * Se borran adn_mensajes, adn_mensaje_destinatarios y adn_comunicacion_bajas: el historial del buzon de pruebas y
--    la lista de personas que pidieron no recibir mensajes se pierden. Las bajas son una obligacion legal en cuanto
--    exista un proveedor real: copiarlas antes con \copy public.adn_comunicacion_bajas to 'bajas.csv' csv header
--  * Se quitan los permisos comunicacion.ver y comunicacion.enviar de todos los roles.
--  * No toca ninguna otra fila de negocio.

begin;
drop function if exists public.adn_vista_previa_envio(text, text);
drop function if exists public.adn_enviar_mensaje(uuid, text, text, text, text, text);
drop function if exists private.adn_vista_previa_envio(text, text);
drop function if exists private.adn_enviar_mensaje(uuid, text, text, text, text, text);
drop function if exists private.adn_destinatarios(uuid, text, text);
drop table if exists public.adn_mensaje_destinatarios;
drop table if exists public.adn_mensajes;
drop table if exists public.adn_comunicacion_bajas;

-- Cadena de siembra de roles anterior (la de 20261105235306_motor_formacion.sql)
create or replace function private.trg_sembrar_roles()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  perform private.sembrar_roles(new.id);
  perform private.sembrar_roles_nuevos(new.id);
  perform private.sembrar_eventos(new.id);
  perform private.sembrar_formacion(new.id);
  return new;
end $$;
drop function if exists private.sembrar_comunicacion(uuid);

delete from public.rol_permisos where permiso in ('comunicacion.ver', 'comunicacion.enviar');
delete from public.permisos where clave in ('comunicacion.ver', 'comunicacion.enviar');
commit;

-- ===== reversión de 20261111150000_adn_informes =====
-- Reversion de 20261111150000_adn_informes.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena,
-- y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
-- Solo borra funciones de lectura (adn_informe_*): no toca ninguna tabla ni ningun dato.

begin;
drop function if exists public.adn_informe_miembros();
drop function if exists public.adn_informe_miembros_resumen();
drop function if exists public.adn_informe_asistencia(date, date);
drop function if exists public.adn_informe_crecimiento(integer);
commit;

-- ===== reversión de 20261111140000_adn_importar_contactos =====
-- Reversion de 20261111140000_adn_importar_contactos.sql. No es una migracion: se ejecuta a mano, solo si
-- Gerencia lo ordena, y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
--
-- Efectos sobre datos, a tener en cuenta antes de ejecutarla:
--  * Se borra `adn_miembro_contactos`: los segundos correos, telefonos adicionales, direcciones y etiquetas
--    importados se pierden. Los miembros importados NO se tocan (nombre, apellido, correo y telefono principales,
--    fecha de nacimiento y notas viven en `miembros`). Para conservar los extras, copiarlos antes con:
--      \copy public.adn_miembro_contactos to 'contactos.csv' csv header
--  * No toca ninguna otra fila de negocio.

begin;
drop function if exists public.adn_importar_miembros(jsonb, text);
drop function if exists public.adn_telefono_canonico(text);
drop table if exists public.adn_miembro_contactos;
commit;

-- ===== reversión de 20261111130000_adn_exportacion =====
-- Reversion de 20261111130000_adn_exportacion.sql. No es una migracion: se ejecuta a mano, solo si Gerencia
-- lo ordena, y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
-- Solo borra funciones nuevas (adn_*): no toca ninguna tabla ni ningun dato. exportar_iglesia, la funcion
-- original de exportacion, no se modifica en la migracion y sigue funcionando igual.

begin;
drop function if exists public.adn_verificar_carga(jsonb);
drop function if exists public.adn_exportar_paquete(uuid);
drop function if exists public.adn_tablas_exportables();
drop function if exists public.adn_fila_exportable(jsonb, text[]);
drop function if exists public.adn_csv_campo(jsonb);
commit;

-- ===== reversión de 20261111120000_adn_ciclo_vida =====
-- Reversion de 20261111120000_adn_ciclo_vida.sql. No es una migracion: vive fuera de
-- `migrations/` para que el CLI de Supabase no la aplique sola. Se ejecuta a mano, solo si
-- Gerencia lo ordena, y la prueba supabase/tests/adn_reversion.sh demuestra que deja el
-- esquema identico al de antes de la migracion.
--
-- Efectos sobre datos, a tener en cuenta antes de ejecutarla:
--  * Se borra `adn_ciclo_auditoria`: el historial de borrados suaves, recuperaciones y purgas se pierde.
--    Si importa conservarlo, copiarlo antes con: \copy public.adn_ciclo_auditoria to 'auditoria.csv' csv header
--  * Una iglesia que estuviera en borrado suave NO se recupera ni se purga: conserva etapa `suspendida` y su
--    `borrado_programado_en` (el mismo plazo de 30 dias), de modo que el mecanismo anterior sigue protegiendola
--    y el borrado manual existente la podra borrar al vencer el plazo. Se pierden solo las marcas adn_*.
--  * No toca ninguna fila de negocio.

begin;

drop trigger if exists iglesias_zz_adn_coherencia on public.iglesias;
drop function if exists private.adn_coherencia_borrado();

drop function if exists public.adn_purgar_iglesia(uuid, uuid);
drop function if exists public.adn_iglesias_vencidas();
drop function if exists public.adn_recuperar_iglesia(uuid, uuid, text);
drop function if exists public.adn_borrar_suave(uuid, uuid, text);
drop function if exists public.adn_auditar_ciclo(uuid, text, uuid, text, jsonb);

alter table public.iglesias
  drop constraint if exists adn_iglesias_borrada_check,
  drop column if exists adn_borrada_en,
  drop column if exists adn_borrada_por,
  drop column if exists adn_estado_previo;

-- Cuerpo anterior de la guarda (el de 20261105221251_exportar_borrar_iglesia.sql)
create or replace function private.guardar_iglesia()
returns trigger language plpgsql set search_path to '' as $$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if new.plan is distinct from old.plan or new.activa is distinct from old.activa
     or new.slug is distinct from old.slug or new.es_demo is distinct from old.es_demo
     or new.iglesia_madre_id is distinct from old.iglesia_madre_id or new.red_acceso is distinct from old.red_acceso
     or new.etapa is distinct from old.etapa or new.etapa_desde is distinct from old.etapa_desde
     or new.prueba_hasta is distinct from old.prueba_hasta
     or new.borrado_programado_en is distinct from old.borrado_programado_en then
    raise exception 'El plan, el estado, la etapa, la direccion y la red de la iglesia solo los cambia la plataforma';
  end if;
  return new;
end;
$$;

drop table if exists public.adn_ciclo_auditoria;

commit;
