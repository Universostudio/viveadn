-- Vive ADN, verificación del incremental 20261111310000_adn_asistencias_unico. Solo lee. Resultado correcto: TODAS las filas con ok = true.
set search_path = pg_catalog;
with f(nombre, obtenido, esperado) as (values
  ('f01_indice_unico_de_asistencias',
    (select count(*)::text from pg_index i join pg_class c on c.oid = i.indexrelid join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = 'adn_asistencias_unica_idx' and i.indisunique), '1'),
  ('f02_columnas_del_indice',
    (select pg_get_indexdef(c.oid) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'adn_asistencias_unica_idx'),
    'CREATE UNIQUE INDEX adn_asistencias_unica_idx ON public.asistencias USING btree (casa_oracion_id, miembro_id, fecha)'),
  ('f03_no_quedan_asistencias_repetidas',
    (select count(*)::text from (select 1 from public.asistencias group by casa_oracion_id, miembro_id, fecha having count(*) > 1) x), '0'),
  ('f04_existe_el_archivo_de_duplicados',
    (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'adn_asistencias_duplicadas' and c.relkind = 'r'), '1'),
  ('f05_el_archivo_tiene_seguridad_por_filas',
    (select c.relrowsecurity::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'adn_asistencias_duplicadas'), 'true'),
  ('f06_con_sesion_no_se_lee_el_archivo',
    (select case when to_regclass('public.adn_asistencias_duplicadas') is null then 'sin tabla'
       else (has_table_privilege('anon', 'public.adn_asistencias_duplicadas', 'select') or has_table_privilege('authenticated', 'public.adn_asistencias_duplicadas', 'select'))::text end), 'false'),
  ('f07_el_servidor_si_lo_lee',
    (select case when to_regclass('public.adn_asistencias_duplicadas') is null then 'sin tabla' else has_table_privilege('service_role', 'public.adn_asistencias_duplicadas', 'select')::text end), 'true')
)
select nombre, obtenido, esperado, (obtenido is not distinct from esperado) as ok from f
union all
select 'zz_todo_ok', null, null, bool_and(obtenido is not distinct from esperado) from f
order by 1;
