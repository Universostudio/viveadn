-- Huellas del esquema de Vive ADN: una fila (nombre, valor) por comprobación. Se ejecuta tal cual sobre la base de referencia (para sacar los valores
-- esperados) y, incrustada, dentro de 99_verificacion.sql del paquete de aplicación. Solo lee el catálogo. Usa search_path vacío para que las
-- expresiones se muestren siempre con sus nombres completos.
select 'a01_tablas_en_public' as nombre, count(*)::text as valor from pg_tables where schemaname = 'public'
union all select 'a02_funciones_en_public_y_private', count(*)::text from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname in ('public', 'private')
union all select 'a03_extensiones_uuid_ossp_pgcrypto', count(*)::text from pg_extension where extname in ('uuid-ossp', 'pgcrypto')
union all select 'b01_nombres_de_tablas', md5(coalesce(string_agg(tablename, ',' order by tablename), '')) from pg_tables where schemaname = 'public'
union all select 'b02_columnas', md5(coalesce(string_agg(format('%s.%s:%s:%s:%s', c.relname, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull, coalesce(pg_get_expr(d.adbin, d.adrelid), '')), '|' order by c.relname, a.attnum), ''))
  from pg_class c join pg_namespace n on n.oid = c.relnamespace join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
  where n.nspname = 'public' and c.relkind in ('r', 'p')
union all select 'b03_funciones_con_su_codigo', md5(coalesce(string_agg(format('%s.%s(%s):%s:%s:%s', s.nspname, p.proname, pg_get_function_identity_arguments(p.oid), p.prosecdef, coalesce(array_to_string(p.proconfig, ','), ''), md5(p.prosrc)), '|' order by s.nspname, p.proname, pg_get_function_identity_arguments(p.oid)), ''))
  from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname in ('public', 'private')
union all select 'b04_restricciones', md5(coalesce(string_agg(format('%s.%s:%s', c.conrelid::regclass::text, c.conname, pg_get_constraintdef(c.oid)), '|' order by c.conrelid::regclass::text, c.conname), ''))
  from pg_constraint c join pg_namespace n on n.oid = c.connamespace where n.nspname = 'public'
union all select 'b05_indices', md5(coalesce(string_agg(indexdef, '|' order by tablename, indexname), '')) from pg_indexes where schemaname = 'public'
union all select 'b06_politicas_public', md5(coalesce(string_agg(format('%s.%s:%s:%s:%s:%s', tablename, policyname, cmd, array_to_string(roles, ','), coalesce(qual, ''), coalesce(with_check, '')), '|' order by tablename, policyname), '')) from pg_policies where schemaname = 'public'
union all select 'b07_politicas_de_archivos_en_storage', coalesce(string_agg(policyname, ',' order by policyname), '') from pg_policies where schemaname = 'storage' and policyname like 'archivos\_%'
union all select 'b08_disparadores', md5(coalesce(string_agg(format('%s:%s', t.tgrelid::regclass::text, pg_get_triggerdef(t.oid)), '|' order by t.tgrelid::regclass::text, t.tgname), ''))
  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and not t.tgisinternal
union all select 'b09_tablas_con_seguridad_por_filas', count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('r', 'p') and c.relrowsecurity
union all select 'c01_permisos_de_tablas', md5(coalesce(string_agg(format('%s:%s:%s', grantee, table_name, privilege_type), '|' order by grantee, table_name, privilege_type), ''))
  from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon', 'authenticated', 'service_role')
union all select 'c02_permisos_de_ejecucion', md5(coalesce(string_agg(format('%s.%s(%s):%s%s%s', s.nspname, p.proname, pg_get_function_identity_arguments(p.oid),
    has_function_privilege('anon', p.oid, 'execute')::int, has_function_privilege('authenticated', p.oid, 'execute')::int, has_function_privilege('service_role', p.oid, 'execute')::int), '|'
    order by s.nspname, p.proname, pg_get_function_identity_arguments(p.oid)), ''))
  from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname in ('public', 'private')
union all select 'd01_filas_de_permisos', count(*)::text from public.permisos
union all select 'd02_filas_de_plan_modulos', count(*)::text from public.plan_modulos
union all select 'd03_filas_de_planes', count(*)::text from public.planes
union all select 'd04_iglesias_vacia', count(*)::text from public.iglesias
union all select 'd05_cubos_de_archivos', count(*)::text from storage.buckets where id in ('iglesia-marca', 'iglesia-archivos')
