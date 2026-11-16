-- Vive ADN, verificación del incremental (20261111310000_adn_asistencias_unico y 20261111320000_adn_seguimiento_metodos). Solo lee. Resultado correcto: TODAS las filas con ok = true.
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
    (select case when to_regclass('public.adn_asistencias_duplicadas') is null then 'sin tabla' else has_table_privilege('service_role', 'public.adn_asistencias_duplicadas', 'select')::text end), 'true'),
  ('f08_dos_plantillas_de_plataforma',
    (select string_agg(clave || ':' || pasos || ':' || plazo_horas || ':' || umbral_amarillo_horas || ':' || umbral_naranja_horas, ',' order by clave)
       from public.adn_seguimiento_metodos where iglesia_id is null), 'op72:3:72:24:48,simple:1:168:72:120'),
  ('f09_consolidaciones_tiene_metodo_con_op72_por_defecto',
    (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
       where d.adrelid = 'public.consolidaciones'::regclass and a.attname = 'metodo_id'), '''5e000000-0000-4000-8000-000000000072''::uuid'),
  ('f10_ningun_proceso_sin_metodo',
    (select count(*)::text from public.consolidaciones where metodo_id is null), '0'),
  ('f11_existe_la_configuracion_por_iglesia',
    (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'adn_seguimiento_config' and c.relrowsecurity), '1'),
  ('f12_el_color_con_op72_coincide_con_el_de_siempre',
    (select public.adn_seguimiento_alerta(timestamptz '2026-11-16 12:00+00' - interval '24 hours', false, '5e000000-0000-4000-8000-000000000072', timestamptz '2026-11-16 12:00+00') || '/' ||
            public.adn_seguimiento_alerta(timestamptz '2026-11-16 12:00+00' - interval '48 hours', false, '5e000000-0000-4000-8000-000000000072', timestamptz '2026-11-16 12:00+00') || '/' ||
            public.adn_seguimiento_alerta(timestamptz '2026-11-16 12:00+00' - interval '72 hours', false, '5e000000-0000-4000-8000-000000000072', timestamptz '2026-11-16 12:00+00') || '/' ||
            public.adn_seguimiento_alerta(timestamptz '2026-11-16 12:00+00' - interval '73 hours', false, '5e000000-0000-4000-8000-000000000072', timestamptz '2026-11-16 12:00+00')), 'verde/amarillo/naranja/rojo'),
  ('f13_la_vista_de_estado_es_security_invoker',
    (select coalesce(c.reloptions @> array['security_invoker=true'], false)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'adn_seguimiento_estado'), 'true'),
  ('f14_el_disparador_lee_el_metodo',
    (select (p.prosrc like '%adn_seguimiento_metodos%' and p.prosrc like '%adn_alerta_con_umbrales%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'gestionar_consolidacion'), 'true'),
  ('f15_con_sesion_solo_se_leen_los_metodos',
    (select (has_table_privilege('authenticated', 'public.adn_seguimiento_metodos', 'select') and not has_table_privilege('authenticated', 'public.adn_seguimiento_metodos', 'insert, update, delete'))::text), 'true')
,
  ('f16_las_metricas_leen_el_metodo_de_cada_proceso',
    (select (p.prosrc like '%adn_seguimiento_metodos%' and p.prosrc like '%make_interval%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'metricas_op72'), 'true'),
  ('f17_las_metricas_siguen_con_las_mismas_claves',
    (select (p.prosrc like '%objetivo_primer%' and p.prosrc like '%plazo%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'metricas_op72'), 'true')
)
select nombre, obtenido, esperado, (obtenido is not distinct from esperado) as ok from f
union all
select 'zz_todo_ok', null, null, bool_and(obtenido is not distinct from esperado) from f
order by 1;
