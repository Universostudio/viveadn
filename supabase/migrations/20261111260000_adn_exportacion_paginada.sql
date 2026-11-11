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
