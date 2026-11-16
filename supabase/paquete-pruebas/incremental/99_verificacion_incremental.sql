-- Vive ADN, verificación del incremental 20261111290000_adn_plataforma_resumen. Solo lee. Resultado correcto: TODAS las filas con ok = true.
set search_path = pg_catalog;
with f(nombre, obtenido, esperado) as (values
  ('f01_tres_funciones_del_panel',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('adn_plataforma_resumen', 'adn_plataforma_actividad', 'adn_plataforma_historial')), '3'),
  ('f02_ninguna_es_security_definer',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('adn_plataforma_resumen', 'adn_plataforma_actividad', 'adn_plataforma_historial') and p.prosecdef), '0'),
  ('f03_anon_y_authenticated_no_ejecutan_ninguna',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace, unnest(array['anon', 'authenticated']) r
      where n.nspname = 'public' and p.proname in ('adn_plataforma_resumen', 'adn_plataforma_actividad', 'adn_plataforma_historial') and has_function_privilege(r, p.oid, 'execute')), '0'),
  ('f04_service_role_las_ejecuta_todas',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('adn_plataforma_resumen', 'adn_plataforma_actividad', 'adn_plataforma_historial') and has_function_privilege('service_role', p.oid, 'execute')), '3'),
  ('f05_columnas_del_resumen',
    (select pg_get_function_result(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'adn_plataforma_resumen'),
    'TABLE(iglesia_id uuid, miembros bigint, usuarios bigint)'),
  ('f06_columnas_de_la_actividad_sin_detalle',
    (select pg_get_function_result(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'adn_plataforma_actividad'),
    'TABLE(tipo text, accion text, iglesia_id uuid, iglesia_nombre text, fecha timestamp with time zone)'),
  ('f07_columnas_del_historial_sin_detalle',
    (select pg_get_function_result(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'adn_plataforma_historial'),
    'TABLE(accion text, fecha timestamp with time zone)'),
  ('f08_una_fila_por_iglesia', (select count(*)::text from public.adn_plataforma_resumen()), (select count(*)::text from public.iglesias)),
  ('f09_la_actividad_respeta_el_limite', (select (count(*) <= 5)::text from public.adn_plataforma_actividad(5)), 'true')
)
select nombre, obtenido, esperado, (obtenido is not distinct from esperado) as ok from f
union all
select 'zz_todo_ok', null, null, bool_and(obtenido is not distinct from esperado) from f
order by 1;
