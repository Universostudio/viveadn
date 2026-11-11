-- Exportacion completa de una iglesia en formato universal: JSON y un CSV por tabla, con manifiesto de cifras.
-- Reversion: supabase/reversiones/20261111130000_adn_exportacion.down.sql. No modifica exportar_iglesia.
--
-- adn_exportar_paquete devuelve, para una iglesia:
--   formato, exportado_en, iglesia, tablas   -> igual que exportar_iglesia (superconjunto, mismas claves)
--   manifiesto                               -> por tabla: filas, columnas con tipo, columnas omitidas, orden de carga,
--                                               huella (md5 del contenido) y md5 del CSV
--   csv                                      -> un CSV por tabla (RFC 4180, UTF-8, CRLF; NULL = campo vacio sin comillas,
--                                               cadena vacia = "")
-- El CSV se genera aqui, no en el navegador, para conservar exactamente la escala de los numericos y los tipos.
-- Nunca salen los secretos (token, token_hash, ip_hash) ni las marcas internas de borrado suave (adn_*).
-- adn_verificar_carga recalcula esas cifras en la base donde se cargo la exportacion y las compara con el manifiesto.

-- Un campo CSV a partir de un valor JSON
create or replace function public.adn_csv_campo(p_valor jsonb)
returns text language sql immutable set search_path to '' as $$
  select case
    when p_valor is null or jsonb_typeof(p_valor) = 'null' then ''
    else (
      select case when t = '' or t ~ '["\r\n,]' or t ~ '^\s|\s$' then '"' || replace(t, '"', '""') || '"' else t end
      from (select case jsonb_typeof(p_valor) when 'string' then p_valor #>> '{}' else p_valor::text end as t) x
    )
  end
$$;

-- La fila tal como sale en la exportacion: sin las columnas omitidas y sin secretos anidados en `detalle`.
-- La usan la exportacion y la verificacion, para que las huellas se calculen igual.
create or replace function public.adn_fila_exportable(p_fila jsonb, p_omitidas text[])
returns jsonb language sql immutable set search_path to '' as $$
  select case
    when jsonb_typeof(p_fila -> 'detalle') = 'object'
      then jsonb_set(p_fila - p_omitidas, '{detalle}', (p_fila -> 'detalle') - array['token', 'token_hash', 'ip_hash'])
    else p_fila - p_omitidas
  end
$$;

-- Tablas que entran en la exportacion y como se filtran por iglesia ($1 es el id de la iglesia):
-- la propia iglesia, toda tabla con iglesia_id y rol_permisos (que cuelga de roles)
create or replace function public.adn_tablas_exportables()
returns table (nombre text, filtro text) language sql stable set search_path to '' as $$
  select 'iglesias'::text, 'id = $1'::text
  union all
  select c.relname::text, 'iglesia_id = $1'
  from pg_class c
  where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
    -- La auditoria de la plataforma son acciones internas y puede llevar notas de administracion: no sale en la exportacion de la iglesia
    and c.relname not in ('plataforma_auditoria', 'adn_bajas_enlaces')
    -- (adn_bajas_enlaces: secretos efimeros de un solo uso, sin valor fuera de la base)
    and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and a.attnum > 0 and not a.attisdropped)
  union all
  select 'rol_permisos', 'rol_id in (select id from public.roles where iglesia_id = $1)'
$$;

create or replace function public.adn_exportar_paquete(p_iglesia uuid)
returns jsonb language plpgsql set search_path to '' set timezone to 'UTC' as $$
declare
  -- Columnas que nunca salen: secretos y marcas internas del borrado suave
  secretos constant text[] := array['token', 'token_hash', 'ip_hash', 'adn_borrada_en', 'adn_borrada_por', 'adn_estado_previo'];
  r record;
  cols jsonb;
  nombres text[];
  omitidas text[];
  filas jsonb;
  csv text;
  tablas jsonb := '{}'::jsonb;
  csvs jsonb := '{}'::jsonb;
  man jsonb := '[]'::jsonb;
  total bigint := 0;
  ig jsonb;
begin
  if not exists (select 1 from public.iglesias where id = p_iglesia) then
    raise exception 'La iglesia no existe';
  end if;

  -- Orden de carga: una tabla va despues de las que referencia (las autorreferencias no cuentan)
  for r in
    with recursive tabla as (select x.nombre, x.filtro from public.adn_tablas_exportables() x),
    fk as (
      select co.relname::text collate "default" as origen, cd.relname::text collate "default" as destino
      from pg_constraint c
      join pg_class co on co.oid = c.conrelid join pg_class cd on cd.oid = c.confrelid
      where c.contype = 'f' and c.connamespace = 'public'::regnamespace and c.conrelid <> c.confrelid
    ),
    niv(nombre, n) as (
      select nombre, 0 from tabla
      union
      select fk.origen, niv.n + 1 from niv join fk on fk.destino = niv.nombre
      where fk.origen in (select nombre from tabla) and niv.n < 50
    )
    select t.nombre, t.filtro, max(niv.n) as nivel
    from tabla t join niv on niv.nombre = t.nombre
    group by t.nombre, t.filtro
    order by max(niv.n), t.nombre
  loop
    select coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text <> all (secretos)), '{}'),
           coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text = any (secretos)), '{}'),
           coalesce(jsonb_agg(jsonb_build_object('nombre', a.attname, 'tipo', format_type(a.atttypid, a.atttypmod), 'obligatoria', a.attnotnull)
                              order by a.attnum) filter (where a.attname::text <> all (secretos)), '[]')
      into nombres, omitidas, cols
      from pg_attribute a
      where a.attrelid = ('public.' || quote_ident(r.nombre))::regclass and a.attnum > 0 and not a.attisdropped;

    -- Filas en un orden estable para que dos exportaciones iguales den el mismo resultado
    execute format(
      'select coalesce(jsonb_agg(public.adn_fila_exportable(to_jsonb(t), $2) order by to_jsonb(t)::text), ''[]''::jsonb) from public.%I t where %s',
      r.nombre, r.filtro) into filas using p_iglesia, omitidas;

    csv := (select string_agg(public.adn_csv_campo(to_jsonb(c.n)), ',' order by c.ord) from unnest(nombres) with ordinality c(n, ord))
           || E'\r\n'
           || coalesce((
                select string_agg(
                  (select string_agg(public.adn_csv_campo(e.f -> c.n), ',' order by c.ord) from unnest(nombres) with ordinality c(n, ord)),
                  E'\r\n' order by e.fo)
                from jsonb_array_elements(filas) with ordinality e(f, fo)
              ) || E'\r\n', '');

    if r.nombre = 'iglesias' then ig := filas -> 0; end if;
    csvs := csvs || jsonb_build_object(r.nombre, csv);
    -- La iglesia va en su propio campo, no dentro de `tablas`, igual que en exportar_iglesia
    if r.nombre <> 'iglesias' then tablas := tablas || jsonb_build_object(r.nombre, filas); end if;
    total := total + jsonb_array_length(filas);
    man := man || jsonb_build_array(jsonb_build_object(
      'nombre', r.nombre, 'orden_carga', r.nivel, 'archivo_csv', 'csv/' || r.nombre || '.csv',
      'filas', jsonb_array_length(filas), 'columnas', cols, 'omitidas', to_jsonb(omitidas),
      'huella', (select md5(coalesce(string_agg(md5(e.f::text), ',' order by md5(e.f::text)), '')) from jsonb_array_elements(filas) e(f)),
      'md5_csv', md5(csv)));
  end loop;

  return jsonb_build_object(
    'formato', 'viveadn-exportacion-2',
    'exportado_en', now(),
    'iglesia', ig,
    'tablas', tablas,
    'csv', csvs,
    'manifiesto', jsonb_build_object(
      'formato', 'viveadn-exportacion-2', 'iglesia_id', p_iglesia, 'exportado_en', now(),
      'codificacion', 'UTF-8 sin BOM', 'separador', ',', 'fin_de_linea', 'CRLF',
      'nulos', 'campo vacio sin comillas; la cadena vacia va entre comillas ("")',
      'total_filas', total, 'tablas', man));
end $$;

-- Recalcula en la base actual las cifras del manifiesto, tabla a tabla, para la iglesia del manifiesto.
-- Devuelve una fila por tabla: filas y huella esperadas frente a las cargadas.
create or replace function public.adn_verificar_carga(p_manifiesto jsonb)
returns table (tabla text, filas_esperadas bigint, filas_cargadas bigint, huella_ok boolean, ok boolean)
language plpgsql set search_path to '' set timezone to 'UTC' as $$
declare
  t jsonb;
  f record;
  filas bigint;
  huella text;
  omitidas text[];
  iglesia uuid := (p_manifiesto ->> 'iglesia_id')::uuid;
begin
  for t in select * from jsonb_array_elements(p_manifiesto -> 'tablas') loop
    select * into f from public.adn_tablas_exportables() x where x.nombre = t ->> 'nombre';
    if not found then
      tabla := t ->> 'nombre'; filas_esperadas := (t ->> 'filas')::bigint; filas_cargadas := 0; huella_ok := false; ok := false;
      return next; continue;
    end if;
    select coalesce(array_agg(v), '{}') into omitidas from jsonb_array_elements_text(t -> 'omitidas') v;
    execute format(
      'select count(*), md5(coalesce(string_agg(md5(public.adn_fila_exportable(to_jsonb(x), $2)::text), '','' order by md5(public.adn_fila_exportable(to_jsonb(x), $2)::text)), '''')) from public.%I x where %s',
      f.nombre, f.filtro) into filas, huella using iglesia, omitidas;
    tabla := f.nombre;
    filas_esperadas := (t ->> 'filas')::bigint;
    filas_cargadas := filas;
    huella_ok := huella = (t ->> 'huella');
    ok := filas = filas_esperadas and huella_ok;
    return next;
  end loop;
end $$;

revoke all on function
  public.adn_csv_campo(jsonb), public.adn_fila_exportable(jsonb, text[]), public.adn_tablas_exportables(), public.adn_exportar_paquete(uuid), public.adn_verificar_carga(jsonb)
  from public, anon, authenticated;
grant execute on function
  public.adn_csv_campo(jsonb), public.adn_fila_exportable(jsonb, text[]), public.adn_tablas_exportables(), public.adn_exportar_paquete(uuid), public.adn_verificar_carga(jsonb)
  to service_role;
