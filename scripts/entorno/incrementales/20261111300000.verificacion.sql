-- Vive ADN, verificación del incremental 20261111300000_adn_checkin_nuevo_creyente. Solo lee. Resultado correcto: TODAS las filas con ok = true.
set search_path = pg_catalog;
with f(nombre, obtenido, esperado) as (values
  ('f01_una_sola_version_de_registrar_checkin',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'registrar_checkin'), '1'),
  ('f02_argumentos_con_la_respuesta_nuevo_creyente',
    (select pg_get_function_identity_arguments(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'registrar_checkin'),
    'p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text, p_texto_version text, p_idioma text, p_canales text[], p_nuevo_creyente boolean'),
  ('f03_el_cuerpo_decide_el_seguimiento_con_la_respuesta',
    (select (p.prosrc like '%coalesce(p_nuevo_creyente, true)%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'registrar_checkin'), 'true'),
  ('f04_conserva_la_doble_confirmacion',
    (select (p.prosrc like '%adn_confirmacion%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'registrar_checkin'), 'true'),
  ('f05_no_es_security_definer',
    (select p.prosecdef::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'registrar_checkin'), 'false'),
  ('f06_anon_y_authenticated_no_la_ejecutan',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace, unnest(array['anon', 'authenticated']) r
      where n.nspname = 'public' and p.proname = 'registrar_checkin' and has_function_privilege(r, p.oid, 'execute')), '0'),
  ('f07_service_role_la_ejecuta',
    (select has_function_privilege('service_role', p.oid, 'execute')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'registrar_checkin'), 'true')
)
select nombre, obtenido, esperado, (obtenido is not distinct from esperado) as ok from f
union all
select 'zz_todo_ok', null, null, bool_and(obtenido is not distinct from esperado) from f
order by 1;
