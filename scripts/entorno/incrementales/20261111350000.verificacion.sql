-- Vive ADN, verificación del incremental (20261111350000_adn_soporte: tickets, novedades y avisos dentro de la aplicación). Solo lee. Resultado correcto: TODAS las filas con ok = true.
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
    (select string_agg(nombre, ',' order by nombre) from public.adn_tablas_exportables() where nombre in ('adn_tickets','adn_ticket_mensajes','adn_novedades_vistas')), 'adn_novedades_vistas,adn_ticket_mensajes,adn_tickets')
)
select nombre, obtenido, esperado, (obtenido is not distinct from esperado) as ok from f
union all
select 'zz_todo_ok', null, null, bool_and(obtenido is not distinct from esperado) from f
order by 1;
