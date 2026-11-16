-- Vive ADN, verificación del incremental (20261111380000_adn_purga_tarea_estado: estado de la tarea programada de purga). Solo lee. Resultado correcto: TODAS las filas con ok = true.
set search_path = pg_catalog;
with f(nombre, obtenido, esperado) as (values
  ('j01_existe_la_funcion_publica_de_estado',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'adn_purga_tarea_estado'), '1'),
  ('j02_existe_la_funcion_de_definidor_en_private',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'adn_purga_tarea_estado' and p.prosecdef), '1'),
  ('j03_la_publica_es_de_invocador',
    (select (not p.prosecdef)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'adn_purga_tarea_estado'), 'true'),
  ('j04_solo_el_servidor_la_ejecuta',
    (select case when to_regprocedure('public.adn_purga_tarea_estado()') is null then 'sin funcion'
       else (has_function_privilege('service_role', 'public.adn_purga_tarea_estado()', 'execute') and not has_function_privilege('authenticated', 'public.adn_purga_tarea_estado()', 'execute') and not has_function_privilege('anon', 'public.adn_purga_tarea_estado()', 'execute'))::text end), 'true')
)
select nombre, obtenido, esperado, (obtenido is not distinct from esperado) as ok from f
union all
select 'zz_todo_ok', null, null, bool_and(obtenido is not distinct from esperado) from f
order by 1;
