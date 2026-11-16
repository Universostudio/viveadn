-- Vive ADN, verificación del incremental (20261111370000_adn_prueba_vencida_lectura: prueba vencida, núcleo en solo lectura). Solo lee. Resultado correcto: TODAS las filas con ok = true.
set search_path = pg_catalog;
with f(nombre, obtenido, esperado) as (values
  ('i01_existe_la_regla_de_lectura_del_nucleo',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'adn_nucleo_en_lectura'), '1'),
  ('i02_tiene_permiso_usa_la_regla',
    (select (p.prosrc like '%adn_nucleo_en_lectura%' and p.prosrc like '%tiene_modulo%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'tiene_permiso'), 'true'),
  ('i03_la_regla_solo_concede_lectura',
    (select (p.prosrc like '%ver_asignados%' and p.prosrc like '%exportar%' and p.prosrc not like '%crear%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'adn_nucleo_en_lectura'), 'true'),
  ('i04_nadie_sin_sesion_ejecuta_la_regla',
    (select case when to_regprocedure('private.adn_nucleo_en_lectura(text, text)') is null then 'sin funcion'
       else (not has_function_privilege('anon', 'private.adn_nucleo_en_lectura(text, text)', 'execute') and has_function_privilege('authenticated', 'private.adn_nucleo_en_lectura(text, text)', 'execute'))::text end), 'true')
)
select nombre, obtenido, esperado, (obtenido is not distinct from esperado) as ok from f
union all
select 'zz_todo_ok', null, null, bool_and(obtenido is not distinct from esperado) from f
order by 1;
