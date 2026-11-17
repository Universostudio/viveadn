-- Vive ADN, traspaso al proyecto real, archivo 4 de 19: tramo 3 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regprocedure('public.adn_informe_miembros()') is not null then raise notice 'Tramo 3 de 15 ya aplicado: no se repite'; return; end if;
  if not (to_regprocedure('public.adn_telefono_canonico(text)') is not null) then raise exception 'Falta aplicar antes el tramo 2 de 15: no se sigue.'; end if;
  execute $cuerpo$


-- Importacion atomica de un lote de hasta 1000 contactos ya limpiados por la web. Cada elemento:
--   { nombre, apellido, email, telefono, fecha_nacimiento, notas,
--     contactos: [ { tipo: correo|telefono|direccion|etiqueta, etiqueta, valor } ] }
-- Se ejecuta con los permisos de quien llama (seguridad por filas, limites del plan y disparadores incluidos).
-- Duplicados, en este orden: un correo ya existente (principal o adicional) en la iglesia; si el contacto no tiene
-- correo, un telefono ya existente; si no tiene ni correo ni telefono, el mismo nombre. Tambien entre las filas del lote.
-- Devuelve conteos. Si algo falla (p. ej. el limite del plan), no se importa nada de ese lote.
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

revoke all on function public.adn_importar_miembros(jsonb, text) from public, anon;
grant execute on function public.adn_importar_miembros(jsonb, text) to authenticated, service_role;
-- ===== 20261111150000_adn_informes (origen sha256 dd00ad653f32, compilado sha256 fbec0e0f8543) =====
-- Datos de los informes en PDF y Excel (miembros, asistencia, crecimiento).
-- Reversion: supabase/reversiones/20261111150000_adn_informes.down.sql. Solo funciones de lectura.
--
-- Se ejecutan con los permisos de quien las llama: la seguridad por filas decide que filas cuentan, de modo que un
-- informe nunca incluye datos que esa persona no podria ver en pantalla. Ademas exigen el permiso del informe:
-- `miembros.exportar` (dato sensible) para el de miembros y `reportes.ver` para asistencia y crecimiento.

-- Crecimiento mes a mes de los ultimos p_meses meses (1 a 60), incluido el actual
create or replace function public.adn_informe_crecimiento(p_meses integer default 12)
returns table (mes date, nuevos_miembros bigint, miembros_acumulados bigint, conversiones bigint, bautizos bigint,
               consolidaciones_iniciadas bigint, consolidaciones_completadas bigint)
language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
begin
  if not (select private.tiene_permiso('reportes.ver')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_meses is null or p_meses < 1 or p_meses > 60 then raise exception 'ADN_PERIODO_INVALIDO'; end if;
  return query
  with meses as (
    select g::date as m
    from generate_series(date_trunc('month', now()) - make_interval(months => p_meses - 1), date_trunc('month', now()), interval '1 month') g
  )
  select ms.m,
    (select count(*) from public.miembros x where x.created_at >= ms.m and x.created_at < ms.m + interval '1 month'),
    (select count(*) from public.miembros x where x.created_at < ms.m + interval '1 month'),
    (select count(*) from public.miembros x where x.fecha_conversion >= ms.m and x.fecha_conversion < (ms.m + interval '1 month')::date),
    (select count(*) from public.miembros x where x.fecha_bautismo >= ms.m and x.fecha_bautismo < (ms.m + interval '1 month')::date),
    (select count(*) from public.consolidaciones c where c.fecha_conversion >= ms.m and c.fecha_conversion < ms.m + interval '1 month'),
    (select count(*) from public.consolidaciones c where c.completado_at >= ms.m and c.completado_at < ms.m + interval '1 month')
  from meses ms
  order by ms.m;
end $$;

-- Asistencia entre dos fechas (como maximo 366 dias): reuniones de casa por semana y por casa, y eventos
create or replace function public.adn_informe_asistencia(p_desde date, p_hasta date)
returns jsonb language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
declare
  semanal jsonb; por_casa jsonb; eventos jsonb;
  tot_casas record; tot_eventos record;
begin
  if not (select private.tiene_permiso('reportes.ver')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta or p_hasta - p_desde > 366 then raise exception 'ADN_PERIODO_INVALIDO'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('semana', s.semana, 'registros', s.registros, 'presentes', s.presentes) order by s.semana), '[]'::jsonb)
    into semanal
    from (select date_trunc('week', a.fecha)::date as semana, count(*) as registros, count(*) filter (where a.presente) as presentes
          from public.asistencias a where a.fecha between p_desde and p_hasta group by 1) s;

  select coalesce(jsonb_agg(jsonb_build_object('casa', c.nombre, 'registros', c.registros, 'presentes', c.presentes, 'personas', c.personas)
                            order by c.presentes desc, c.nombre), '[]'::jsonb)
    into por_casa
    from (select coalesce(h.nombre, h.codigo_zona, '') as nombre, count(*) as registros, count(*) filter (where a.presente) as presentes,
                 count(distinct a.miembro_id) filter (where a.presente) as personas
          from public.asistencias a join public.casas_oracion h on h.id = a.casa_oracion_id
          where a.fecha between p_desde and p_hasta group by h.id, h.nombre, h.codigo_zona) c;

  select coalesce(jsonb_agg(jsonb_build_object('titulo', e.titulo, 'tipo', e.tipo, 'inicia_en', e.inicia_en, 'registros', e.registros, 'presentes', e.presentes)
                            order by e.inicia_en), '[]'::jsonb)
    into eventos
    from (select ev.titulo, ev.tipo, ev.inicia_en, count(*) as registros, count(*) filter (where ae.presente) as presentes
          from public.asistencia_evento ae join public.eventos ev on ev.id = ae.evento_id
          where ev.inicia_en >= p_desde and ev.inicia_en < p_hasta + 1 group by ev.id, ev.titulo, ev.tipo, ev.inicia_en) e;

  select count(*) as registros, count(*) filter (where a.presente) as presentes into tot_casas
    from public.asistencias a where a.fecha between p_desde and p_hasta;
  select count(*) as registros, count(*) filter (where ae.presente) as presentes into tot_eventos
    from public.asistencia_evento ae join public.eventos ev on ev.id = ae.evento_id where ev.inicia_en >= p_desde and ev.inicia_en < p_hasta + 1;

  return jsonb_build_object(
    'desde', p_desde, 'hasta', p_hasta,
    'casas', jsonb_build_object('registros', tot_casas.registros, 'presentes', tot_casas.presentes, 'semanal', semanal, 'por_casa', por_casa),
    'eventos', jsonb_build_object('registros', tot_eventos.registros, 'presentes', tot_eventos.presentes, 'lista', eventos));
end $$;

-- Cifras del conjunto de miembros
create or replace function public.adn_informe_miembros_resumen()
returns jsonb language plpgsql stable set search_path to '' as $$
declare r jsonb;
begin
  if not (select private.tiene_permiso('miembros.exportar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  select jsonb_build_object(
    'total', count(*), 'activos', count(*) filter (where activo), 'inactivos', count(*) filter (where not activo),
    'bautizados', count(*) filter (where bautizado), 'con_correo', count(*) filter (where email is not null),
    'con_telefono', count(*) filter (where telefono is not null), 'sin_casa', count(*) filter (where casa_oracion_id is null),
    'por_nivel', coalesce((select jsonb_object_agg(x.nivel, x.n) from (select nivel_compromiso as nivel, count(*) as n from public.miembros group by 1) x), '{}'::jsonb))
  into r
  from public.miembros;
  return r;
end $$;

-- Lista de miembros para el informe, ordenada por codigo. Se pagina con .range() desde la web
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

revoke all on function public.adn_informe_crecimiento(integer), public.adn_informe_asistencia(date, date),
  public.adn_informe_miembros_resumen(), public.adn_informe_miembros() from public, anon;
grant execute on function public.adn_informe_crecimiento(integer), public.adn_informe_asistencia(date, date),
  public.adn_informe_miembros_resumen(), public.adn_informe_miembros() to authenticated, service_role;
$cuerpo$;
end $tramo$;
select 'ok: tramo 3 de 15 aplicado' as resultado, (to_regprocedure('public.adn_informe_miembros()') is not null) as comprobado;
