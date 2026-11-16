-- Vive ADN, verificación del incremental (20261111360000_adn_precios_plan: precios por plan, vacíos). Solo lee. Resultado correcto: TODAS las filas con ok = true.
set search_path = pg_catalog;
with f(nombre, obtenido, esperado) as (values
  ('h01_columnas_de_precio_en_planes',
    (select string_agg(a.attname, ',' order by a.attname) from pg_attribute a where a.attrelid = 'public.planes'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attname in ('precio_mensual_centimos', 'precio_anual_centimos', 'moneda')), 'moneda,precio_anual_centimos,precio_mensual_centimos'),
  ('h02_existe_la_regla_de_coherencia',
    (select count(*)::text from pg_constraint c where c.conrelid = 'public.planes'::regclass and c.conname = 'adn_planes_precio_coherente' and c.contype = 'c'), '1'),
  ('h03_las_sesiones_no_cambian_precios',
    (select (not has_table_privilege('authenticated', 'public.planes', 'update') and not has_table_privilege('anon', 'public.planes', 'update'))::text), 'true'),
  ('h04_el_servidor_si_los_cambia',
    (select has_table_privilege('service_role', 'public.planes', 'update')::text), 'true')
)
select nombre, obtenido, esperado, (obtenido is not distinct from esperado) as ok from f
union all
select 'zz_todo_ok', null, null, bool_and(obtenido is not distinct from esperado) from f
order by 1;
