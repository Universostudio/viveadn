-- Vive ADN, verificación del incremental desde 20261111340000 hasta 20261111400000 (soporte, precios por plan, prueba vencida en solo lectura, estado de la tarea de purga, ayuda con la prueba vencida y agregados en SQL).
-- Solo lee. Resultado correcto: TODAS las filas con ok = true.
set search_path = pg_catalog;
with f(nombre, obtenido, esperado) as (values
  ('g01_existen_las_seis_tablas',
    (select string_agg(c.relname, ',' order by c.relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind = 'r' and c.relname in ('adn_tickets','adn_ticket_mensajes','adn_novedades','adn_novedades_vistas','adn_avisos','adn_avisos_entregas')),
    'adn_avisos,adn_avisos_entregas,adn_novedades,adn_novedades_vistas,adn_ticket_mensajes,adn_tickets'),
  ('g02_todas_con_seguridad_por_filas',
    (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname in ('adn_tickets','adn_ticket_mensajes','adn_novedades','adn_novedades_vistas','adn_avisos','adn_avisos_entregas') and c.relrowsecurity), '6'),
  ('g03_nadie_sin_sesion_toca_nada',
    (select (not exists (select 1 from unnest(array['adn_tickets','adn_ticket_mensajes','adn_novedades','adn_novedades_vistas','adn_avisos','adn_avisos_entregas']) t
       where to_regclass('public.' || t) is not null and (has_table_privilege('anon', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'insert'))))::text), 'true'),
  ('g04_la_iglesia_no_borra_ni_cambia_tickets',
    (select (not has_table_privilege('authenticated', 'public.adn_tickets', 'update') and not has_table_privilege('authenticated', 'public.adn_tickets', 'delete')
       and not has_table_privilege('authenticated', 'public.adn_ticket_mensajes', 'update') and not has_table_privilege('authenticated', 'public.adn_ticket_mensajes', 'delete'))::text), 'true'),
  ('g05_la_iglesia_solo_escribe_asunto_prioridad_y_texto',
    (select (has_column_privilege('authenticated', 'public.adn_tickets', 'asunto', 'insert') and has_column_privilege('authenticated', 'public.adn_tickets', 'prioridad', 'insert')
       and not has_column_privilege('authenticated', 'public.adn_tickets', 'estado', 'insert') and not has_column_privilege('authenticated', 'public.adn_tickets', 'iglesia_id', 'insert')
       and has_column_privilege('authenticated', 'public.adn_ticket_mensajes', 'texto', 'insert') and not has_column_privilege('authenticated', 'public.adn_ticket_mensajes', 'autor_tipo', 'insert'))::text), 'true'),
  ('g06_la_iglesia_no_escribe_novedades_ni_avisos',
    (select (not has_table_privilege('authenticated', 'public.adn_novedades', 'insert') and not has_table_privilege('authenticated', 'public.adn_avisos', 'insert')
       and not has_table_privilege('authenticated', 'public.adn_avisos', 'update'))::text), 'true'),
  ('g07_de_una_entrega_solo_se_cambia_leido_y_descartado',
    (select (has_column_privilege('authenticated', 'public.adn_avisos_entregas', 'leido_en', 'update') and has_column_privilege('authenticated', 'public.adn_avisos_entregas', 'descartado_en', 'update')
       and not has_column_privilege('authenticated', 'public.adn_avisos_entregas', 'iglesia_id', 'update') and not has_table_privilege('authenticated', 'public.adn_avisos_entregas', 'insert'))::text), 'true'),
  ('g08_funciones_de_la_iglesia_son_invoker',
    (select string_agg(p.proname || ':' || p.prosecdef::text, ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('adn_ticket_crear','adn_novedades_marcar_vistas','adn_aviso_entregar')),
    'adn_aviso_entregar:false,adn_novedades_marcar_vistas:false,adn_ticket_crear:false'),
  ('g09_repartir_un_aviso_solo_lo_hace_el_servidor',
    (select (has_function_privilege('service_role', 'public.adn_aviso_entregar(uuid)', 'execute') and not has_function_privilege('authenticated', 'public.adn_aviso_entregar(uuid)', 'execute')
       and not has_function_privilege('anon', 'public.adn_aviso_entregar(uuid)', 'execute'))::text), 'true'),
  ('g10_tres_disparadores_de_tickets',
    (select string_agg(t.tgname, ',' order by t.tgname) from pg_trigger t where not t.tgisinternal and t.tgrelid in ('public.adn_tickets'::regclass, 'public.adn_ticket_mensajes'::regclass)),
    'adn_ticket_mensajes_estado,adn_ticket_mensajes_iglesia,adn_tickets_limite'),
  ('g11_la_exportacion_no_incluye_las_entregas_de_avisos',
    (select count(*)::text from public.adn_tablas_exportables() where nombre = 'adn_avisos_entregas'), '0'),
  ('g12_la_exportacion_si_incluye_tickets_y_mensajes',
    (select string_agg(nombre, ',' order by nombre) from public.adn_tablas_exportables() where nombre in ('adn_tickets','adn_ticket_mensajes','adn_novedades_vistas')), 'adn_novedades_vistas,adn_ticket_mensajes,adn_tickets'),
  ('h01_columnas_de_precio_en_planes',
    (select string_agg(a.attname, ',' order by a.attname) from pg_attribute a where a.attrelid = 'public.planes'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attname in ('precio_mensual_centimos', 'precio_anual_centimos', 'moneda')), 'moneda,precio_anual_centimos,precio_mensual_centimos'),
  ('h02_existe_la_regla_de_coherencia',
    (select count(*)::text from pg_constraint c where c.conrelid = 'public.planes'::regclass and c.conname = 'adn_planes_precio_coherente' and c.contype = 'c'), '1'),
  ('h03_las_sesiones_no_cambian_precios',
    (select (not has_table_privilege('authenticated', 'public.planes', 'update') and not has_table_privilege('anon', 'public.planes', 'update'))::text), 'true'),
  ('h04_el_servidor_si_los_cambia',
    (select has_table_privilege('service_role', 'public.planes', 'update')::text), 'true'),
  ('i01_existe_la_regla_de_lectura_del_nucleo',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'adn_nucleo_en_lectura'), '1'),
  ('i02_tiene_permiso_usa_la_regla',
    (select (p.prosrc like '%adn_nucleo_en_lectura%' and p.prosrc like '%tiene_modulo%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'tiene_permiso'), 'true'),
  ('i03_la_regla_solo_concede_lectura',
    (select (p.prosrc like '%ver_asignados%' and p.prosrc like '%exportar%' and p.prosrc not like '%crear%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'adn_nucleo_en_lectura'), 'true'),
  ('i04_nadie_sin_sesion_ejecuta_la_regla',
    (select case when to_regprocedure('private.adn_nucleo_en_lectura(text, text)') is null then 'sin funcion'
       else (not has_function_privilege('anon', 'private.adn_nucleo_en_lectura(text, text)', 'execute') and has_function_privilege('authenticated', 'private.adn_nucleo_en_lectura(text, text)', 'execute'))::text end), 'true'),
  ('j01_existe_la_funcion_publica_de_estado',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'adn_purga_tarea_estado'), '1'),
  ('j02_existe_la_funcion_de_definidor_en_private',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'adn_purga_tarea_estado' and p.prosecdef), '1'),
  ('j03_la_publica_es_de_invocador',
    (select (not p.prosecdef)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'adn_purga_tarea_estado'), 'true'),
  ('j04_solo_el_servidor_la_ejecuta',
    (select case when to_regprocedure('public.adn_purga_tarea_estado()') is null then 'sin funcion'
       else (has_function_privilege('service_role', 'public.adn_purga_tarea_estado()', 'execute') and not has_function_privilege('authenticated', 'public.adn_purga_tarea_estado()', 'execute') and not has_function_privilege('anon', 'public.adn_purga_tarea_estado()', 'execute'))::text end), 'true'),
  ('k01_existe_la_regla_de_ayuda_con_la_prueba_vencida',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'adn_puede_pedir_ayuda'), '1'),
  ('k02_las_cuatro_politicas_de_tickets_usan_la_regla',
    (select count(*)::text from pg_policies where schemaname = 'public' and tablename in ('adn_tickets', 'adn_ticket_mensajes') and policyname in ('adn_tickets_ver', 'adn_tickets_crear', 'adn_ticket_mensajes_ver', 'adn_ticket_mensajes_crear')
       and coalesce(qual, '') || coalesce(with_check, '') like '%adn_puede_pedir_ayuda%'), '4'),
  ('k03_la_regla_no_la_ejecuta_nadie_sin_sesion',
    (select case when to_regprocedure('private.adn_puede_pedir_ayuda()') is null then 'sin funcion' else (not has_function_privilege('anon', 'private.adn_puede_pedir_ayuda()', 'execute'))::text end), 'true'),
  ('l01_existen_los_tres_agregados',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('adn_plataforma_facturacion', 'adn_soporte_resumen', 'adn_avisos_estadisticas')), '3'),
  ('l02_solo_el_servidor_ejecuta_los_agregados',
    (select case when to_regprocedure('public.adn_soporte_resumen(boolean)') is null or to_regprocedure('public.adn_plataforma_facturacion()') is null or to_regprocedure('public.adn_avisos_estadisticas(uuid[])') is null then 'sin funcion'
       else (has_function_privilege('service_role', 'public.adn_soporte_resumen(boolean)', 'execute') and not has_function_privilege('anon', 'public.adn_soporte_resumen(boolean)', 'execute') and not has_function_privilege('authenticated', 'public.adn_soporte_resumen(boolean)', 'execute')
         and not has_function_privilege('anon', 'public.adn_plataforma_facturacion()', 'execute') and not has_function_privilege('authenticated', 'public.adn_plataforma_facturacion()', 'execute')
         and not has_function_privilege('anon', 'public.adn_avisos_estadisticas(uuid[])', 'execute') and not has_function_privilege('authenticated', 'public.adn_avisos_estadisticas(uuid[])', 'execute'))::text end), 'true')
)
select nombre, obtenido, esperado, (obtenido is not distinct from esperado) as ok from f
union all
select 'zz_todo_ok', null, null, bool_and(obtenido is not distinct from esperado) from f
order by 1;
